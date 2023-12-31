if Mix.env() != :prd do
  defmodule Zedex.Debug do
    @moduledoc false

    def erl_to_ast(erl_str) do
      {:ok, expr_tokens, _} = :erl_scan.string(String.to_charlist(erl_str))
      {:ok, body_ast} = :erl_parse.parse_exprs(expr_tokens)

      body_ast
    end

    def disassemble_module_file(module) do
      {_mod, beam_code, _file} = :code.get_object_code(module)

      {:ok, {_, [{:abstract_code, {_, abstract_code}}]}} =
        :beam_lib.chunks(beam_code, [:abstract_code])

      erlang_code = abstract_code |> :erl_syntax.form_list() |> :erl_prettypr.format()
      :io.fwrite(~c"~s~n", [erlang_code])
    end

    def print_ast_as_erlang(ast) do
      :merl.print(ast)
      :ok
    end

    def print_ast_as_syntax(ast) do
      :io.put_chars(:erl_prettypr.format(:erl_syntax.meta(ast)))
    end
  end
end
