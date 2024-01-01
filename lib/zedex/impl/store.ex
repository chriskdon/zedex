defmodule Zedex.Impl.Store do
  @moduledoc false

  use GenServer

  # TODO: Clean all this up

  @original_modules_table __MODULE__.OriginalModules
  @patched_modules_table __MODULE__.PatchedModules
  @callbacks_table __MODULE__.Callbacks

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    # TODO: Should these be made private?
    :ets.new(@original_modules_table, [:named_table, :set, :public])
    :ets.new(@patched_modules_table, [:named_table, :set, :public])
    :ets.new(@callbacks_table, [:named_table, :set, :public])

    {:ok, []}
  end

  def store_patched_callback({_module, _function, _arity} = mfa, callback) do
    table = callback_table(mfa)
    true = :ets.insert(table, {mfa, callback})

    {table, mfa}
  end

  def store_patched_call_callback(caller_mfa, called_mfa, callback) do
    true = :ets.insert(@callbacks_table, {{:call_patch, caller_mfa, called_mfa}, callback})
    :ok
  end

  def store_patched_module(module, beam_code, ast) do
    true =
      :ets.insert(
        @patched_modules_table,
        {module, %{beam_code: beam_code, ast: ast}}
      )

    :ok
  end

  def get_patched_module(module) do
    case :ets.lookup(@patched_modules_table, module) do
      [{_, patched_module}] -> patched_module
      _ -> nil
    end
  end

  # Get the table where callbacks for an mfa are stored.
  def callback_table({_module, _function, _arity}) do
    # For now there is only a single table
    @callbacks_table
  end

  def get_call_patch_callback(caller_mfa, called_mfa) do
    case :ets.lookup(@callbacks_table, {:call_patch, caller_mfa, called_mfa}) do
      [{_, callback}] -> callback
      _ -> nil
    end
  end

  def remove_call_patch_callback(caller_module) do
    true = :ets.match_delete(@callbacks_table, {{:call_patch, {caller_module, :_, :_}, :_}, :_})
    :ok
  end

  def remove_patched_module(module) do
    true = :ets.delete(@patched_modules_table, module)
    :ok
  end

  def get_patched_callback(mfa) do
    callback =
      case :ets.lookup(callback_table(mfa), mfa) do
        [{_, callback}] -> callback
        _ -> nil
      end

    callback
  end

  def remove_module_callbacks(module) do
    true = :ets.match_delete(@callbacks_table, {{module, :_, :_}, :_})
    :ok
  end

  def store_original_module(module, filename, beam_code) do
    true =
      :ets.insert(
        @original_modules_table,
        {{:original_module, module}, {:beam_code, filename, beam_code}}
      )

    :ok
  end

  def remove_original_module(module) do
    true = :ets.delete(@original_modules_table, {:original_module, module})
    :ok
  end

  def get_original_module(module) do
    result =
      case :ets.lookup(@original_modules_table, {:original_module, module}) do
        [{_, {:beam_code, _filename, _code} = beam_code}] -> beam_code
        _ -> nil
      end

    {:ok, result}
  end

  def get_all_original_modules do
    original_modules_beam_code =
      :ets.match(@original_modules_table, {{:original_module, :"$1"}, :_})
      |> Enum.concat()

    original_modules_beam_code
  end

  @impl GenServer
  def handle_call(_request, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end
end
