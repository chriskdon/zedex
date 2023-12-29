defmodule Zedex do
  @type replacement :: {original :: mfa(), replacement :: mfa()}

  @doc """
  Replace module functions with functions from another module.

  Example:
    `replace([
      {{SomeModule, :some_func, 1}, {ReplacementModule, :another_func, 1}}
     ])`
  """
  defdelegate replace(replacements), to: Zedex.Replacer

  @doc """
  Reset all modules back to their original unhooked state.
  """
  @spec reset() :: :ok
  defdelegate reset, to: Zedex.Replacer

  @doc """
  Reset the module back to its original unhooked state.
  """
  @spec reset(modules :: list(module()) | module()) :: :ok
  defdelegate reset(modules), to: Zedex.Replacer

  @doc """
  Call the original version of a function.
  """
  @spec apply_original(module(), atom(), list(any())) :: any()
  def apply_original(module, function, args) do
    hook_original_fun = String.to_atom("__hook_original__#{function}")

    case :erlang.function_exported(module, hook_original_fun, Enum.count(args)) do
      true -> apply(module, hook_original_fun, args)
      _ -> apply(module, function, args)
    end
  end
end
