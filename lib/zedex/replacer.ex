defmodule Zedex.Replacer do
  @moduledoc false

  use GenServer

  alias Zedex.Store

  # Prefix to use for the original function implementation
  @original_function_prefix "__zedex_replacer_original__"

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    {:ok, %{}}
  end

  def replace(replacements) do
    GenServer.call(__MODULE__, {:replace, replacements})
  end

  def reset do
    GenServer.call(__MODULE__, :reset_all)
  end

  def reset(modules) when is_list(modules) do
    GenServer.call(__MODULE__, {:reset, modules})
  end

  def reset(module) when is_atom(module) do
    reset([module])
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
      {:ok, {:beam_code, beam_code}} = Store.get_original_module(mod)

      # TODO: Get the actual original filename
      :ok = load_beam_code(mod, "#{mod}", beam_code)
    end)

    modules
  end

  defp do_reset(module) when is_atom(module) do
    reset([module])
  end

  defp replace_module(module, replacements) do
    :ok = assert_replacements(replacements)

    # Allow the module to be modified
    true = :code.unstick_mod(module)

    {original_module_code, patched_module_code} = generate_patched_module(module, replacements)

    :ok = Store.store_original_module(module, original_module_code)
    :ok = load_beam_code(module, "hooked_#{module}", patched_module_code)

    :ok
  end

  def original_function_mfa(module, function, arity) do
    original_fun = String.to_atom("#{@original_function_prefix}#{function}")

    case :erlang.function_exported(module, original_fun, arity) do
      true -> {module, original_fun, arity}
      _ -> {module, function, arity}
    end
  end

  defp generate_patched_module(module, replacements) do
    # Get Code
    {beam_code, chunks} = get_module_code(module)

    # TODO: Error if we can't find a function to replace

    {start_forms, export_forms, rest_forms} =
      Enum.reduce(
        chunks,
        {_start = [], _exports = [], _rest = []},
        fn form, form_acc ->
          handle_form_patch(:erl_syntax.type(form), form, replacements, form_acc)
        end
      )

    # Exports must be before functions
    module_forms = start_forms ++ export_forms ++ rest_forms
    patched_beam_code = forms_to_beam_code(module_forms)

    {beam_code, patched_beam_code}
  end

  defp handle_form_patch(:function, form, replacements, {start_forms, export_forms, rest}) do
    func = :erl_syntax.atom_value(:erl_syntax.function_name(form))
    arity = :erl_syntax.function_arity(form)

    case find_replacement({func, arity}, replacements) do
      :none ->
        {start_forms, export_forms, rest ++ [form]}

      mfa ->
        {replaced, {new_original_name, original}} =
          do_replace(form, {func, arity}, mfa)

        arity_qualifier =
          :erl_syntax.arity_qualifier(
            :erl_syntax.atom(new_original_name),
            :erl_syntax.integer(arity)
          )

        export_original =
          :erl_syntax.attribute(:erl_syntax.atom(:export), [
            :erl_syntax.list([arity_qualifier])
          ])

        {start_forms, export_forms ++ [export_original], rest ++ [replaced, original]}
    end
  end

  defp handle_form_patch(:attribute, form, _replacements, {start_forms, export_forms, rest}) do
    case :erl_syntax.atom_value(:erl_syntax.attribute_name(form)) do
      name when name in [:file, :module] ->
        {start_forms ++ [form], export_forms, rest}

      :export ->
        {start_forms, export_forms ++ [form], rest}

      _ ->
        {start_forms, export_forms, rest ++ [form]}
    end
  end

  defp handle_form_patch(_, form, _replacements, {start_forms, export_forms, rest}) do
    {start_forms, export_forms, rest ++ [form]}
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
    :code.purge(module)

    # Load Code
    {:module, ^module} = :code.load_binary(module, String.to_charlist(filename), beam_code)

    :ok
  end

  defp assert_replacements(replacements) do
    Enum.each(
      replacements,
      fn
        {{_o_module, _o_func, arity}, {_r_module, _r_func, arity}} -> :ok
        _ -> raise "Arity must match"
      end
    )

    case replacements
         |> Enum.uniq_by(fn {{module, _, _}, _} -> module end)
         |> Enum.count() do
      1 -> :ok
      _ -> raise "Too many replacement modules specified. Only 1 is supported currently."
    end

    :ok
  end

  defp find_replacement({func, arity}, replacements) do
    filter =
      Enum.filter(
        replacements,
        fn {{_o_m, o_f, o_a}, _} ->
          o_f == func and o_a == arity
        end
      )

    case filter do
      [{_, replacement_mfa}] -> replacement_mfa
      [] -> :none
      _ -> throw("Duplicate replacements")
    end
  end

  defp do_replace(
         function_form,
         {original_func, arity},
         {replacement_module, replacement_func, arity}
       ) do
    :erl_syntax.function_clauses(function_form)

    func_name = :erl_syntax.function_name(function_form) |> :erl_syntax.atom_value()
    ^arity = :erl_syntax.function_arity(function_form)

    ann = :erl_syntax.get_ann(function_form)

    # Create function with body replaced with call replacement
    args = Enum.map_join(1..arity, ",", fn i -> "Arg@#{i}" end)

    func_charlist =
      ~c"'#{func_name}'(#{args}) -> '#{replacement_module}':#{replacement_func}(#{args})."

    replaced_func_0 = :merl.quote(func_charlist)
    replaced_func_1 = :erl_syntax.add_ann(ann, replaced_func_0)

    original_func_new_name = String.to_atom("#{@original_function_prefix}#{original_func}")

    # Rename original function so it can be used if needed
    original_func_0 =
      :erl_syntax.function(
        :erl_syntax.atom(original_func_new_name),
        :erl_syntax.function_clauses(function_form)
      )

    original_func_1 = :erl_syntax.add_ann(ann, original_func_0)

    {replaced_func_1, {original_func_new_name, original_func_1}}
  end
end
