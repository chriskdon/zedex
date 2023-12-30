defmodule Zedex.Replacer do
  @moduledoc false

  use GenServer

  # Prefix to use for the original function implementation
  @original_function_prefix "__zedex_replacer_original__"

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    table = :ets.new(__MODULE__, [:named_table, :set, :private])

    {:ok, %{table: table}}
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
    reset_modules = get_all_original_modules()
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
      {:beam_code, beam_code} = get_original_module(mod)

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

    :ok = store_original_module(module, original_module_code)
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

  defp store_original_module(module, beam_code) do
    true = :ets.insert(__MODULE__, {{:original_module, module}, {:beam_code, beam_code}})
    :ok
  end

  defp get_original_module(module) do
    [{_, {:beam_code, _} = beam_code}] = :ets.lookup(__MODULE__, {:original_module, module})
    beam_code
  end

  defp get_all_original_modules() do
    :ets.match(__MODULE__, {{:original_module, :"$1"}, :_})
    |> Enum.concat()
  end

  defp generate_patched_module(module, replacements) do
    # Get Code
    {beam_code, chunks} = get_module_code(module)

    # TODO: Error if we can't find a function to replace
    # TODO: Clean this all up

    {startForms, exportForms, restForms} =
      Enum.reduce(
        chunks,
        {_start = [], _exports = [], _rest = []},
        fn n, {startForms, exportForms, rest} ->
          case :erl_syntax.type(n) do
            :function ->
              func = :erl_syntax.atom_value(:erl_syntax.function_name(n))
              arity = :erl_syntax.function_arity(n)

              case find_replacement({func, arity}, replacements) do
                :none ->
                  {startForms, exportForms, rest ++ [n]}

                mfa ->
                  {replaced, {newOriginalName, original}} =
                    do_replace(
                      n,
                      {func, arity},
                      mfa
                    )

                  arityQualifier =
                    :erl_syntax.arity_qualifier(
                      :erl_syntax.atom(newOriginalName),
                      :erl_syntax.integer(arity)
                    )

                  exportOriginal =
                    :erl_syntax.attribute(:erl_syntax.atom(:export), [
                      :erl_syntax.list([arityQualifier])
                    ])

                  {startForms, exportForms ++ [exportOriginal], rest ++ [replaced, original]}
              end

            :attribute ->
              case :erl_syntax.atom_value(:erl_syntax.attribute_name(n)) do
                name when name in [:file, :module] ->
                  {startForms ++ [n], exportForms, rest}

                :export ->
                  {startForms, exportForms ++ [n], rest}

                _ ->
                  {startForms, exportForms, rest ++ [n]}
              end

            _ ->
              {startForms, exportForms, rest ++ [n]}
          end
        end
      )

    # Exports must be before functions
    patched_beam_code = forms_to_beam_code(startForms ++ exportForms ++ restForms)

    {beam_code, patched_beam_code}
  end

  defp forms_to_beam_code(forms) do
    abstractT = :erl_syntax.revert_forms(forms)
    {:ok, _, patched_beam_code} = :compile.forms(abstractT, [:report_errors, :binary])
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
      [{_, replacementMFA}] -> replacementMFA
      [] -> :none
      _ -> throw("Duplicate replacements")
    end
  end

  defp do_replace(functionForm, {oFunc, arity}, {rMod, rFunc, arity}) do
    :erl_syntax.function_clauses(functionForm)

    func_name = :erl_syntax.function_name(functionForm) |> :erl_syntax.atom_value()
    ^arity = :erl_syntax.function_arity(functionForm)

    ann = :erl_syntax.get_ann(functionForm)

    # Create function with body replaced with call replacement
    args = Enum.map(1..arity, fn i -> "Arg@#{i}" end) |> Enum.join(",")
    func_charlist = ~c"'#{func_name}'(#{args}) -> '#{rMod}':#{rFunc}(#{args})."

    replacedFunc0 = :merl.quote(func_charlist)
    replacedFunc1 = :erl_syntax.add_ann(ann, replacedFunc0)

    originalFuncNewName = String.to_atom("#{@original_function_prefix}#{oFunc}")

    # Rename original function so it can be used if needed
    originalFunc0 =
      :erl_syntax.function(
        :erl_syntax.atom(originalFuncNewName),
        :erl_syntax.function_clauses(functionForm)
      )

    originalFunc1 = :erl_syntax.add_ann(ann, originalFunc0)

    {replacedFunc1, {originalFuncNewName, originalFunc1}}
  end
end
