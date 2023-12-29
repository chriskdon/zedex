defmodule Zedex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # FIXME: Use a gen server for the ETS store
    :ok = Zedex.Replacer.setup()

    children = [
      # Starts a worker by calling: Zedex.Worker.start_link(arg)
      # {Zedex.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Zedex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end