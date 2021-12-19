defmodule NervesRc522.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: NervesRc522.Worker.start_link(arg)
      # {NervesRc522.Worker, arg}
      {NervesRc522.CardScanner, []},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesRc522.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
