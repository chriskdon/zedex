defmodule Zedex.Impl.Store do
  @moduledoc false

  use GenServer

  @original_modules_table __MODULE__.OriginalModules
  @callbacks_table __MODULE__.Callbacks

  def callbacks_table, do: @callbacks_table

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    original_modules_table = :ets.new(@original_modules_table, [:named_table, :set, :protected])
    callbacks_table = :ets.new(@callbacks_table, [:named_table, :set, :protected])

    state = %{
      original_modules_table: original_modules_table,
      callbacks_table: callbacks_table
    }

    {:ok, state}
  end

  def store_patched_callback({_module, _function, _arity} = mfa, callback) do
    GenServer.call(__MODULE__, {:store_patched_callback, mfa, callback})
  end

  def get_patched_callback(mfa) do
    GenServer.call(__MODULE__, {:get_patched_callback, mfa})
  end

  def remove_module_callbacks(module) do
    GenServer.call(__MODULE__, {:remove_module_callbacks, module})
  end

  def store_original_module(module, beam_code) do
    GenServer.call(__MODULE__, {:store_original_module, module, beam_code})
  end

  def remove_original_module(module) do
    GenServer.call(__MODULE__, {:remove_original_module, module})
  end

  def get_original_module(module) do
    GenServer.call(__MODULE__, {:get_original_module, module})
  end

  def get_all_original_modules do
    GenServer.call(__MODULE__, :get_all_original_modules)
  end

  @impl GenServer
  def handle_call({:store_patched_callback, mfa, callback}, _from, state) do
    true = :ets.insert(@callbacks_table, {mfa, callback})
    {:reply, {@callbacks_table, mfa}, state}
  end

  @impl GenServer
  def handle_call({:remove_module_callbacks, module}, _from, state) do
    true = :ets.match_delete(@callbacks_table, {{module, :_, :_}, :_})

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get_patched_callback, mfa}, _from, state) do
    # FIXME: Does this need to be sync in the process?
    callback =
      case :ets.lookup(@callbacks_table, mfa) do
        [{_, callback}] -> callback
        _ -> nil
      end

    {:reply, callback, state}
  end

  @impl GenServer
  def handle_call({:store_original_module, module, beam_code}, _from, state) do
    true =
      :ets.insert(@original_modules_table, {{:original_module, module}, {:beam_code, beam_code}})

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:remove_original_module, module}, _from, state) do
    true = :ets.delete(@original_modules_table, {:original_module, module})

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get_original_module, module}, _from, state) do
    [{_, {:beam_code, _} = beam_code}] =
      :ets.lookup(@original_modules_table, {:original_module, module})

    {:reply, {:ok, beam_code}, state}
  end

  @impl GenServer
  def handle_call(:get_all_original_modules, _from, state) do
    original_modules_beam_code =
      :ets.match(@original_modules_table, {{:original_module, :"$1"}, :_})
      |> Enum.concat()

    {:reply, original_modules_beam_code, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end
end
