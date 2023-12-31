defmodule Zedex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Zedex.Impl.Store, []},
      {Zedex.Impl.Replacer, []}
    ]

    opts = [strategy: :one_for_one, name: Zedex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
