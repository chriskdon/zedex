defmodule Zedex do
  @moduledoc """
  Replace functions from other modules with your own.
  """

  alias Zedex.Impl.Replacer

  @type callback :: mfa() | function()
  @type replacement :: {original :: mfa(), replacement :: callback()}

  @doc """
  Replace module functions with functions from another module.

  Example:
    `replace([
      {{SomeModule, :some_func, 1}, {ReplacementModule, :another_func_1, 1}},
      {{AnotherModule, :their_func, 2}, {ReplacementModule, :another_func_2, 2}}
     ])`
  """
  @spec replace(list(replacement())) :: :ok
  defdelegate replace(replacements), to: Replacer

  @spec replace_with(mfa(), callback()) :: :ok
  defdelegate replace_with(mfa, callback), to: Replacer

  @doc """
  Reset all modules back to their original unhooked state.
  """
  @spec reset() :: [module()]
  defdelegate reset, to: Replacer

  @doc """
  Reset the module back to its original unhooked state.
  """
  @spec reset(modules :: list(module()) | module()) :: [module()]
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
