defmodule Zedex.Impl.Replacer do
  @moduledoc false

  # This module performs the replacement of functions in another module.

  use GenServer

  alias Zedex.Impl.{Hooks, Store, SyntaxHelpers}

  # Prefix to use for the original function implementation
  @original_function_prefix "__zedex_replacer_original__"

  # Filename prefix for the patched module
  @patched_module_filename_prefix "__zedex__patched__"

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    {:ok, %{}}
  end

  @spec replace_with(mfa(), Zedex.callback()) :: :ok
  def replace_with(mfa, callback) do
    if patched?(mfa) do
      # If the mfa is already patched we can simply replace the callback in ETS
      store_patched_callback(mfa, callback)
      :ok
    else
      case replace([{mfa, callback}]) do
        :ok -> :ok
        {:error, {:not_found, ^mfa}} -> {:error, :not_found}
      end
    end
  end

  @spec replace(list(Zedex.replacement())) :: :ok
  def replace(replacements) do
    GenServer.call(__MODULE__, {:replace, replacements})
  end

  def replace_calls(mfa, original_mfa, replacement_mfa) do
    GenServer.call(__MODULE__, {:replace_calls, mfa, original_mfa, replacement_mfa})
  end

  @spec reset() :: [module()]
  def reset do
    GenServer.call(__MODULE__, :reset_all)
  end

  @spec reset(modules :: list(module()) | module()) :: [module()]
  def reset(modules)

  def reset(modules) when is_list(modules) do
    GenServer.call(__MODULE__, {:reset, modules})
  end

  def reset(module) when is_atom(module) do
    reset([module])
  end

  @doc """
  Get the MFA that can be used to call the original unpatched version of the
  function.
  """
  def original_function_mfa(module, function, arity) do
    original_fun = String.to_atom("#{@original_function_prefix}#{function}")

    case :erlang.function_exported(module, original_fun, arity) do
      true -> {module, original_fun, arity}
      _ -> {module, function, arity}
    end
  end

  @impl GenServer
  def handle_call({:replace, replacements}, _from, state) do
    # FIXME: No replacement should be done unless we are sure we've found
    #        all the modules. Do this in two steps: first find and generate
    #        the patched modules, then load them.
    result =
      replacements
      |> Enum.group_by(fn {{module, _, _}, _} -> module end)
      |> Enum.reduce_while(:ok, fn {mod, mod_replacements}, acc ->
        case replace_module(mod, mod_replacements) do
          :ok ->
            {:cont, acc}

          {:error, {:module_not_found, _}} ->
            {mfa, _} = List.first(mod_replacements)
            {:halt, {:error, {:not_found, mfa}}}

          {:error, {:not_found, _} = reason} ->
            {:halt, {:error, reason}}
        end
      end)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        {:replace_calls, {module, _, _} = caller_mfa, called_mfa, callback},
        _from,
        state
      ) do
    :ok = assert_callback_compatible(called_mfa, callback)

    case generate_patched_replace_calls(caller_mfa, called_mfa) do
      {:ok,
       %{
         original_module_code: original_module_code,
         patched_module_code: patched_module_code,
         patched_module_ast: patched_module_ast
       }} ->
        if Store.get_original_module(module) == {:ok, nil} do
          :ok =
            Store.store_original_module(
              module,
              find_filename(module),
              original_module_code
            )
        end

        Store.store_patched_call_callback(
          caller_mfa,
          called_mfa,
          build_callback(callback)
        )

        Store.store_patched_module(module, patched_module_code, patched_module_ast)

        :ok =
          load_beam_code(
            module,
            "#{@patched_module_filename_prefix}(#{module})",
            patched_module_code
          )

        {:reply, :ok, state}

      {:error, {:not_found, _}} ->
        {:reply, {:error, :caller_not_found}, state}

      {:error, reason} when reason in [:caller_not_found, :called_not_found] ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:reset_all, _from, state) do
    reset_modules = Store.get_all_original_modules()
    ^reset_modules = do_reset(reset_modules)

    {:reply, reset_modules, state}
  end

  @impl GenServer
  def handle_call({:reset, reset_modules}, _from, state) do
    ^reset_modules = do_reset(reset_modules)

    {:reply, reset_modules, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end

  defp generate_patched_replace_calls({caller_module, _, _} = caller_mfa, called_mfa) do
    with {:ok, %{beam_code: beam_code, ast: module_ast}} <- get_module_code(caller_module) do
      case Enum.reduce(
             module_ast,
             %{
               caller_mfa: caller_mfa,
               called_mfa: called_mfa,
               forms: [],
               state: :caller_not_found
             },
             fn form, state ->
               handle_replace_in_form_patch(:erl_syntax.type(form), form, state)
             end
           ) do
        %{state: state} when state in [:caller_not_found, :called_not_found] ->
          {:error, state}

        %{forms: forms, state: :replaced} ->
          patched_beam_code = forms_to_beam_code(forms)

          {:ok,
           %{
             original_module_code: beam_code,
             patched_module_code: patched_beam_code,
             patched_module_ast: forms
           }}
      end
    end
  end

  defp handle_replace_in_form_patch(:function, form, state) do
    %{
      caller_mfa: {caller_module, _, _} = caller_mfa,
      called_mfa: called_mfa,
      forms: forms
    } = state

    case SyntaxHelpers.function_form_to_mfa(caller_module, form) do
      ^caller_mfa ->
        case replace_calls_in_function(form, caller_mfa, called_mfa) do
          {:ok, patched_function} ->
            %{state | forms: forms ++ [patched_function], state: :replaced}

          {:error, :not_found} ->
            %{state | state: :called_not_found}
        end

      _ ->
        %{state | forms: forms ++ [form]}
    end
  end

  defp handle_replace_in_form_patch(_, form, %{forms: forms} = state) do
    %{state | forms: forms ++ [form]}
  end

  defp replace_calls_in_function(function_est, caller_mfa, called_mfa) do
    case SyntaxHelpers.replace_applications_in_function(
           function_est,
           called_mfa,
           fn node ->
             callsite_args =
               :erl_syntax.application_arguments(node)
               |> :erl_syntax.list()

             patch_args = [
               :erl_syntax.abstract(caller_mfa),
               :erl_syntax.abstract(called_mfa),
               callsite_args
             ]

             {hook_module, hook_function, _} = Hooks.call_hook()

             :erl_syntax.application(
               :erl_syntax.atom(hook_module),
               :erl_syntax.atom(hook_function),
               patch_args
             )
           end
         ) do
      :no_change -> {:error, :not_found}
      {:updated, patched_function} -> {:ok, patched_function}
    end
  end

  defp do_reset(modules) when is_list(modules) do
    Enum.each(modules, fn mod ->
      {:ok, {:beam_code, filename, beam_code}} = Store.get_original_module(mod)

      :ok = load_beam_code(mod, filename, beam_code)

      :ok = Store.remove_module_callbacks(mod)
      :ok = Store.remove_call_patch_callback(mod)
      :ok = Store.remove_original_module(mod)
      :ok = Store.remove_patched_module(mod)
    end)

    modules
  end

  defp do_reset(module) when is_atom(module) do
    do_reset([module])
  end

  defp replace_module(module, replacements) do
    :ok = assert_replacements(replacements)

    with {:ok, {original_module_code, patched_module_code, callbacks}} <-
           generate_patched_module(module, replacements) do
      Enum.each(callbacks, fn {mfa, callback} ->
        store_patched_callback(mfa, callback)
      end)

      if Store.get_original_module(module) == {:ok, nil} do
        :ok =
          Store.store_original_module(
            module,
            find_filename(module),
            original_module_code
          )
      end

      :ok =
        load_beam_code(
          module,
          "#{@patched_module_filename_prefix}(#{module})",
          patched_module_code
        )

      :ok
    end
  end

  defp generate_patched_module(module, replacements) do
    case get_module_code(module) do
      {:ok, %{beam_code: beam_code, ast: module_ast}} ->
        %{
          forms: %{start: start_forms, exports: export_forms, rest: rest_forms},
          replacements: remaining_replacements,
          callbacks: callbacks
        } =
          Enum.reduce(
            module_ast,
            %{
              module: module,
              replacements: replacements,
              forms: %{start: [], exports: [], rest: []},
              callbacks: []
            },
            fn form, state ->
              handle_form_patch(:erl_syntax.type(form), form, state)
            end
          )

        case remaining_replacements do
          [] ->
            module_forms = start_forms ++ export_forms ++ rest_forms
            patched_beam_code = forms_to_beam_code(module_forms)

            {:ok, {beam_code, patched_beam_code, callbacks}}

          [{not_found_mfa, _} | _] ->
            {:error, {:not_found, not_found_mfa}}
        end

      {:error, {:not_found, module}} ->
        {:error, {:module_not_found, module}}
    end
  end

  defp handle_form_patch(:function, form, state) do
    %{module: module, replacements: replacements, callbacks: callbacks} = state
    %{start: start_forms, exports: export_forms, rest: rest_forms} = forms = state.forms

    mfa = SyntaxHelpers.function_form_to_mfa(module, form)

    case find_replacement(mfa, replacements) do
      :none ->
        %{state | forms: %{forms | rest: rest_forms ++ [form]}}

      {_, replacement_callback} = replacement ->
        {replaced_est, original_est} = do_replace(mfa, form)
        export_original_est = SyntaxHelpers.export_function_est(original_est)

        module_forms = %{
          start: start_forms,
          exports: export_forms ++ [export_original_est],
          rest: rest_forms ++ [replaced_est, original_est]
        }

        callbacks = callbacks ++ [{mfa, replacement_callback}]
        remaining_replacements = replacements -- [replacement]

        %{state | forms: module_forms, callbacks: callbacks, replacements: remaining_replacements}
    end
  end

  defp handle_form_patch(:attribute, form, state) do
    %{start: start_forms, exports: export_forms, rest: rest_forms} = forms = state.forms

    module_forms =
      case :erl_syntax.atom_value(:erl_syntax.attribute_name(form)) do
        name when name in [:file, :module] ->
          %{forms | start: start_forms ++ [form]}

        :export ->
          %{forms | exports: export_forms ++ [form]}

        _ ->
          %{forms | rest: rest_forms ++ [form]}
      end

    %{state | forms: module_forms}
  end

  defp handle_form_patch(_, form, state) do
    %{rest: rest_forms} = forms = state.forms

    %{state | forms: %{forms | rest: rest_forms ++ [form]}}
  end

  defp forms_to_beam_code(forms) do
    abstract_t = :erl_syntax.revert_forms(forms)
    {:ok, _, patched_beam_code} = :compile.forms(abstract_t, [:report_errors, :binary])
    patched_beam_code
  end

  defp get_module_code(module) do
    case Store.get_patched_module(module) do
      nil ->
        case :code.get_object_code(module) do
          {^module, beam_code, _} ->
            {:ok, {^module, [{:abstract_code, {_, ast}}]}} =
              :beam_lib.chunks(beam_code, [:abstract_code])

            {:ok, %{state: :unpatched, beam_code: beam_code, ast: ast}}

          :error ->
            {:error, {:not_found, module}}
        end

      %{beam_code: _, ast: _} = patched_module ->
        {:ok, Map.put(patched_module, :state, :patched)}
    end
  end

  defp load_beam_code(module, filename, beam_code) do
    # Allow the module to be modified
    true = :code.unstick_mod(module)

    # Remove old module
    :code.purge(module)
    :code.delete(module)

    # Load new module code
    {:module, ^module} = :code.load_binary(module, String.to_charlist(filename), beam_code)

    :ok
  end

  defp assert_replacements(replacements) do
    Enum.each(
      replacements,
      fn
        {mfa, callback} -> :ok = assert_callback_compatible(mfa, callback)
      end
    )

    :ok
  end

  defp assert_callback_compatible({_o_module, _o_func, arity}, {_r_module, _r_func, arity}) do
    :ok
  end

  defp assert_callback_compatible({_mod, _func, arity}, callback) when is_function(callback) do
    case :erlang.fun_info(callback)[:arity] do
      ^arity -> :ok
      _ -> raise "Arity must match"
    end
  end

  defp find_replacement({_module, func, arity}, replacements) do
    case Enum.filter(
           replacements,
           fn {{_o_m, o_f, o_a}, _} ->
             o_f == func and o_a == arity
           end
         ) do
      [replacement] -> replacement
      [] -> :none
      _ -> throw("Duplicate replacements")
    end
  end

  defp do_replace({module, _function, _arity}, function_form) do
    {^module, name, _} = mfa = SyntaxHelpers.function_form_to_mfa(module, function_form)

    # Create the patched function that calls the callback
    replaced_func_est =
      build_patched_function(mfa, :erl_syntax.get_ann(function_form))

    # Rename original function so it can be used if needed
    original_func_est =
      SyntaxHelpers.rename_function_est(function_form, "#{@original_function_prefix}#{name}")

    {replaced_func_est, original_func_est}
  end

  defp build_patched_function({module, name, arity}, annotation) do
    {hook_module, hook_function, _} = Hooks.implementation_hook()

    # Create function with body replaced with call replacement
    args = Enum.map_join(1..arity, ",", fn i -> "Arg@#{i}" end)

    patched_func =
      """
      '#{name}'(#{args}) ->
        '#{hook_module}':#{hook_function}({'#{module}', #{name}, #{arity}}, [#{args}]).
      """

    replaced_func_0 = :merl.quote(String.to_charlist(patched_func))
    replaced_func_1 = :erl_syntax.add_ann(annotation, replaced_func_0)

    replaced_func_1
  end

  defp store_patched_callback(mfa, callback) do
    Store.store_patched_callback(mfa, build_callback(callback))
  end

  defp build_callback(callback) when is_function(callback) do
    fn args ->
      apply(callback, args)
    end
  end

  defp build_callback({module, function, _arity}) do
    fn args ->
      apply(module, function, args)
    end
  end

  defp patched?(mfa) do
    Store.get_patched_callback(mfa) != nil
  end

  defp find_filename(module) do
    # FIXME: There is probably a better way to do this.

    module_name = ~c"#{module}"
    elixir_module_name = ~c"Elixir.#{module}"

    {_, filename, _} =
      Enum.find(:code.all_available(), "nofile", fn {mod, _, _} ->
        mod == module_name || mod == elixir_module_name
      end)

    "#{filename}"
  end
end
