defmodule Zedex.Impl.Store do
  @moduledoc false

  use GenServer

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init([]) do
    table = :ets.new(__MODULE__, [:named_table, :set, :private])

    {:ok, %{table: table}}
  end

  def store_original_module(module, beam_code) do
    GenServer.call(__MODULE__, {:store_original_module, module, beam_code})
  end

  def get_original_module(module) do
    GenServer.call(__MODULE__, {:get_original_module, module})
  end

  def get_all_original_modules do
    GenServer.call(__MODULE__, :get_all_original_modules)
  end

  @impl GenServer
  def handle_call({:store_original_module, module, beam_code}, _from, state) do
    true = :ets.insert(__MODULE__, {{:original_module, module}, {:beam_code, beam_code}})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get_original_module, module}, _from, state) do
    [{_, {:beam_code, _} = beam_code}] = :ets.lookup(__MODULE__, {:original_module, module})
    {:reply, {:ok, beam_code}, state}
  end

  @impl GenServer
  def handle_call(:get_all_original_modules, _from, state) do
    original_modules_beam_code =
      :ets.match(__MODULE__, {{:original_module, :"$1"}, :_})
      |> Enum.concat()

    {:reply, original_modules_beam_code, state}
  end

  @impl GenServer
  def handle_cast(_request, state) do
    {:noreply, state}
  end
end
