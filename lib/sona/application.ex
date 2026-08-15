defmodule Sona.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SonaWeb.Telemetry,
      Sona.Repo,
      {DNSCluster, query: Application.get_env(:sona, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sona.PubSub},
      # Background translation of user-entered content (Sona.Translation)
      {Task.Supervisor, name: Sona.TaskSupervisor},
      # Start a worker by calling: Sona.Worker.start_link(arg)
      # {Sona.Worker, arg},
      # Start to serve requests, typically the last entry
      SonaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sona.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SonaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
