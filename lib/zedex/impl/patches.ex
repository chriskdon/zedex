defmodule Zedex.Impl.Patches do
  @moduledoc false

  alias Zedex.Impl.Store

  def patch_call(caller_mfa, called_mfa, args) do
    case Store.get_call_patch_callback(caller_mfa, called_mfa) do
      nil ->
        # FIXME
        raise """
        [#{__MODULE__}] No patched callback found.
          Caller: #{inspect(caller_mfa)}
          Called: #{inspect(called_mfa)}
        """

      callback ->
        callback.(args)
    end
  end
end
