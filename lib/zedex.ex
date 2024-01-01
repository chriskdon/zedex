defmodule Zedex do
  @moduledoc """
  Replace functions from other modules with your own.
  """

  alias Zedex.Impl.Replacer

  @type callback :: mfa() | function()
  @type replacement :: {original :: mfa(), replacement :: callback()}

  @doc """
  Replace module functions with functions from another module.

  ## Examples

      replace([
        {{SomeModule1, :some_func_1, 1}, {ReplacementModule, :another_func_1, 1}},
        {{SomeModule1, :some_func_2, 2}, {ReplacementModule, :another_func_2, 2}},
        {{SomeModule2, :some_func_1, 2}, fn a, b -> a + b end},
      ])
  """
  @spec replace(list(replacement())) :: :ok
  defdelegate replace(replacements), to: Replacer

  @doc """
  Replace a single module function with a different one.

  ## Examples

      replace_with({SomeModule1, :some_fun_1, 1}, {ReplacementModule, :another_func_1, 1})

      replace_with({SomeModule1, :some_fun_1, 1}, fn a -> a + 1 end)

  """
  @spec replace_with(mfa(), callback()) :: :ok
  defdelegate replace_with(mfa, callback), to: Replacer

  @doc """
  Replace calls to one module function with calls to another in a specific MFA.

  ### Examples

      replace_calls(
        {CallerModule, :my_fun_1, 1},
        {CalledModule, :some_fun_1, 2},
        {ReplacementModule, :another_fun_1, 2}
      )

      replace_calls(
        {CallerModule, :my_fun_1, 1},
        {CalledModule, :some_fun_1, 2},
        fn a, b -> a + b end
      )
  """
  @spec replace_calls(mfa(), mfa(), callback()) :: :ok
  defdelegate replace_calls(caller_mfa, called_mfa, callback), to: Replacer

  @doc """
  Reset all modules back to their original unhooked state.

  Returns the list of reset modules.
  """
  @spec reset() :: [module()]
  defdelegate reset, to: Replacer

  @doc """
  Reset a module or list of modules back to the original unhooked state.

  Returns the list of reset modules.
  """
  @spec reset(modules :: list(module()) | module()) :: [module()]
  defdelegate reset(modules), to: Replacer

  @doc """
  Call the real (i.e. original) version of a function.
  """
  @spec apply_r(module(), atom(), list(any())) :: any()
  def apply_r(module, function, args) do
    {m, f, _} = Replacer.original_function_mfa(module, function, Enum.count(args))
    apply(m, f, args)
  end
end
