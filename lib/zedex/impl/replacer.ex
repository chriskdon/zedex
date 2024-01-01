defmodule Zedex.Impl.Replacer do
  @moduledoc false

  # This module performs the replacement of functions in another module.

  use GenServer

  alias Zedex.Impl.{Store, SyntaxHelpers}

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
    case patched?(mfa) do
      # If the mfa is already patched we can simply replace the callback in ETS
      true ->
        store_patched_callback(mfa, callback)
        :ok

      _ ->
        replace([{mfa, callback}])
    end
  end

  @spec replace(list(Zedex.replacement())) :: :ok
  def replace(replacements) do
    GenServer.call(__MODULE__, {:replace, replacements})
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
    replacements
    |> Enum.group_by(fn {{module, _, _}, _} -> module end)
    |> Enum.each(fn {mod, mod_replacements} ->
      :ok = replace_module(mod, mod_replacements)
    end)

    {:reply, :ok, state}
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

  defp do_reset(modules) when is_list(modules) do
    Enum.each(modules, fn mod ->
      {:ok, {:beam_code, filename, beam_code}} = Store.get_original_module(mod)

      :ok = load_beam_code(mod, filename, beam_code)

      :ok = Store.remove_module_callbacks(mod)
      :ok = Store.remove_original_module(mod)
    end)

    modules
  end

  defp do_reset(module) when is_atom(module) do
    do_reset([module])
  end

  defp replace_module(module, replacements) do
    :ok = assert_replacements(replacements)

    {original_module_code, patched_module_code, callbacks} =
      generate_patched_module(module, replacements)

    Enum.each(callbacks, fn {mfa, callback} ->
      store_patched_callback(mfa, callback)
    end)

    :ok =
      Store.store_original_module(
        module,
        find_filename(module),
        original_module_code
      )

    :ok =
      load_beam_code(
        module,
        "#{@patched_module_filename_prefix}(#{module})",
        patched_module_code
      )

    :ok
  end

  defp generate_patched_module(module, replacements) do
    # Get Code
    {beam_code, chunks} = get_module_code(module)

    # TODO: Error if we can't find a function to replace

    %{
      forms: %{start: start_forms, exports: export_forms, rest: rest_forms},
      callbacks: callbacks
    } =
      Enum.reduce(
        chunks,
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

    module_forms = start_forms ++ export_forms ++ rest_forms
    patched_beam_code = forms_to_beam_code(module_forms)

    {beam_code, patched_beam_code, callbacks}
  end

  defp handle_form_patch(:function, form, state) do
    %{module: module, replacements: replacements, callbacks: callbacks} = state
    %{start: start_forms, exports: export_forms, rest: rest_forms} = forms = state.forms

    mfa = SyntaxHelpers.function_form_to_mfa(module, form)

    case find_replacement(mfa, replacements) do
      :none ->
        %{state | forms: %{forms | rest: rest_forms ++ [form]}}

      replacement_callback ->
        {replaced_est, original_est} = do_replace(mfa, form)
        export_original_est = SyntaxHelpers.export_function_est(original_est)

        module_forms = %{
          start: start_forms,
          exports: export_forms ++ [export_original_est],
          rest: rest_forms ++ [replaced_est, original_est]
        }

        callbacks = callbacks ++ [{mfa, replacement_callback}]

        %{state | forms: module_forms, callbacks: callbacks}
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
    {^module, beam_code, _} = :code.get_object_code(module)

    {:ok, {^module, [{:abstract_code, {_, chunks}}]}} =
      :beam_lib.chunks(beam_code, [:abstract_code])

    {beam_code, chunks}
  end

  defp load_beam_code(module, filename, beam_code) do
    # Allow the module to be modified
    true = :code.unstick_mod(module)

    # Remove old module
    :code.purge(module)

    # Load new module code
    {:module, ^module} = :code.load_binary(module, String.to_charlist(filename), beam_code)

    :ok
  end

  defp assert_replacements(replacements) do
    Enum.each(
      replacements,
      fn
        {{_o_module, _o_func, arity}, {_r_module, _r_func, arity}} ->
          :ok

        {{_o_module, _o_func, arity}, callback} when is_function(callback) ->
          case :erlang.fun_info(callback)[:arity] do
            ^arity -> :ok
            _ -> raise "Arity must match"
          end

        _ ->
          raise "Arity must match"
      end
    )

    :ok
  end

  defp find_replacement({_module, func, arity}, replacements) do
    case Enum.filter(
           replacements,
           fn {{_o_m, o_f, o_a}, _} ->
             o_f == func and o_a == arity
           end
         ) do
      [{_, replacement_mfa}] -> replacement_mfa
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

  defp build_patched_function({module, name, arity} = mfa, annotation) do
    # Create function with body replaced with call replacement
    args = Enum.map_join(1..arity, ",", fn i -> "Arg@#{i}" end)

    callback_table = Store.callback_table(mfa)

    # We may eventually want to inline direct MFA calls for efficiency. For
    # now doing a lookup on a lambda makes other operations simpler.
    patched_func =
      """
      '#{name}'(#{args}) ->
          [{_, Callback}] = ets:lookup('#{callback_table}', {'#{module}', #{name}, #{arity}}),
          Callback([#{args}]).
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
