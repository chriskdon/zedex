defmodule Zedex do
  alias Zedex.Replacer

  @type replacement :: {original :: mfa(), replacement :: mfa()}

  @doc """
  Replace module functions with functions from another module.

  Example:
    `replace([
      {{SomeModule, :some_func, 1}, {ReplacementModule, :another_func, 1}}
     ])`
  """
  defdelegate replace(replacements), to: Replacer

  @doc """
  Reset all modules back to their original unhooked state.
  """
  @spec reset() :: :ok
  defdelegate reset, to: Replacer

  @doc """
  Reset the module back to its original unhooked state.
  """
  @spec reset(modules :: list(module()) | module()) :: :ok
  defdelegate reset(modules), to: Replacer

  @doc """
  Call the original version of a function.
  """
  @spec apply_original(module(), atom(), list(any())) :: any()
  def apply_original(module, function, args) do
    {m, f, _arity} = Replacer.original_function_mfa(module, function, Enum.count(args))
    apply(m, f, args)
  end
end
