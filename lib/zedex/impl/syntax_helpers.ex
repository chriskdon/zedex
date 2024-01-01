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

  def export_function_est(function_est) do
    arity = :erl_syntax.function_arity(function_est)

    function_est
    |> function_name()
    |> export_est(arity)
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

  def replace_applications_in_function(
        function_ast,
        original_mfa,
        replacer_fn
      ) do
    map_typed(
      function_ast,
      fn
        :application, node ->
          case application_est_to_mfa(node) do
            {:ok, ^original_mfa} -> replacer_fn.(node)
            _ -> node
          end

        _, node ->
          node
      end
    )
  end

  def map_typed(ast, fun) do
    :erl_syntax_lib.map(
      fn node ->
        fun.(:erl_syntax.type(node), node)
      end,
      ast
    )
  end

  def application_est_to_mfa(application_est) do
    app_operator =
      application_est
      # application_operator fails if we don't revert first
      |> :erl_syntax.revert()
      |> :erl_syntax.application_operator()

    case :erl_syntax.type(app_operator) do
      :module_qualifier ->
        app_module =
          app_operator
          |> :erl_syntax.module_qualifier_argument()
          |> :erl_syntax.atom_value()

        app_function =
          app_operator
          |> :erl_syntax.module_qualifier_body()
          |> :erl_syntax.atom_value()

        arity =
          :erl_syntax.application_arguments(application_est)
          |> Enum.count()

        {:ok, {app_module, app_function, arity}}

      _ ->
        {:error, {:not_remote, application_est}}
    end
  end
end
