defmodule Zedex.Impl.SyntaxHelpers do
  @moduledoc false

  # Helpers for working with Erlang syntax trees

  def function_name(function_est) do
    function_est
    |> :erl_syntax.function_name()
    |> :erl_syntax.atom_value()
  end

  def function_form_to_mfa(module, function_form) do
    func_name = function_name(function_form)
    arity = :erl_syntax.function_arity(function_form)
    {module, func_name, arity}
  end

  def function_est(name, clauses, opts \\ []) do
    :erl_syntax.function(
      :erl_syntax.atom(String.to_atom(name)),
      clauses
    )
    |> maybe_add_ann_est(Keyword.get(opts, :annotation))
  end

  def rename_function_est(function_est, name) do
    function_est(
      "#{name}",
      :erl_syntax.function_clauses(function_est),
      annotation: :erl_syntax.get_ann(function_est)
    )
  end

  def export_est(export_name, arity) do
    arity_qualifier =
      :erl_syntax.arity_qualifier(
        :erl_syntax.atom(export_name),
        :erl_syntax.integer(arity)
      )

    :erl_syntax.attribute(:erl_syntax.atom(:export), [
      :erl_syntax.list([arity_qualifier])
    ])
  end

  def maybe_add_ann_est(est, nil), do: est
  def maybe_add_ann_est(est, ann), do: :erl_syntax.add_ann(ann, est)
end
