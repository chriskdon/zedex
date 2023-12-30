defmodule Zedex.Debug do
  @moduledoc false

  def erl_to_ast(erl_str) do
    {:ok, expr_tokens, _} = :erl_scan.string(String.to_charlist(erl_str))
    {:ok, body_ast} = :erl_parse.parse_exprs(expr_tokens)

    body_ast
  end

  def disassemble(module) do
    # Get Code
    {_mod, beam_code, _file} = :code.get_object_code(module)

    {:ok, {_, [{:abstract_code, {_, abstract_code}}]}} =
      :beam_lib.chunks(beam_code, [:abstract_code])

    erlang_code = abstract_code |> :erl_syntax.form_list() |> :erl_prettypr.format()
    :io.fwrite(~c"~s~n", [erlang_code])
  end

  def inspect_ast(ast) do
    :code.ensure_loaded(:erl_syntax)
    :code.ensure_loaded(:erl_prettypr)

    # erlang_code = :erl_prettypr.format(ast) |> :binary.list_to_bin()

    IO.puts("----\nAST")
    IO.puts(ast)

    IO.puts("ERLANG")
    :merl.print(ast)
    IO.puts("----")

    ast
  end
end
