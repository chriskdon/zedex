defmodule Zedex.Impl.Hooks do
  @moduledoc false

  # Hooks that are called from the patched functions.

  alias Zedex.Impl.Store

  def call_hook, do: {__MODULE__, :zedex_call_hook, 3}
  def implementation_hook, do: {__MODULE__, :zedex_implementation_hook, 2}

  @doc """
  Called when a function call has been patched.
  """
  def zedex_call_hook(caller_mfa, called_mfa, args) do
    case Store.get_call_patch_callback(caller_mfa, called_mfa) do
      nil ->
        # FIXME: Make this a proper error
        raise """
        [#{__MODULE__}] No patched callback found.
          Caller: #{inspect(caller_mfa)}
          Called: #{inspect(called_mfa)}
        """

      callback ->
        callback.(args)
    end
  end

  @doc """
  Called when a function implementation has been patched.
  """
  def zedex_implementation_hook(mfa, args) do
    case Store.get_patched_callback(mfa) do
      nil ->
        # FIXME: Make this a proper error
        raise """
        [#{__MODULE__}] No patched callback found.
          Function: #{inspect(mfa)}
        """

      callback ->
        callback.(args)
    end
  end
end
