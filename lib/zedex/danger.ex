defmodule Zedex.Danger do
  @moduledoc """
  Functions that are extremely dangerous to use and should generally be avoided.

  > #### Warning {: .warning}
  > These functions should be avoided at all costs and should not be used in
  > anything that runs live in production.
  >
  > They exist to get around certain edge cases where the normal Zedex functions
  > will not work (e.g. replacing NIFs and BIFs). Please carefully read the docs
  > for each function before using them.
  """

  alias Zedex
  alias Zedex.Impl.Replacer

  @doc """
  Replace calls to one module function with calls to another in a specific MFA.

  # ⚠ Replacing calls is generally not recommended as any changes to the underlying
  # code being replaced could break the intended behaviour. It mainly exists to
  # replace NIFs and BIFs (e.g. send) that can't normally be hooked into by
  # replacing the function directly.

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
  @spec replace_calls(mfa(), mfa(), Zedex.callback()) :: :ok
  defdelegate replace_calls(caller_mfa, called_mfa, callback), to: Replacer
end
