defmodule Shiftline.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ShiftlineWeb.Telemetry,
      Shiftline.Repo,
      {DNSCluster, query: Application.get_env(:shiftline, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Shiftline.PubSub},
      # Background translation of user-entered content (Shiftline.Translation)
      {Task.Supervisor, name: Shiftline.TaskSupervisor},
      # Start a worker by calling: Shiftline.Worker.start_link(arg)
      # {Shiftline.Worker, arg},
      # Start to serve requests, typically the last entry
      ShiftlineWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Shiftline.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ShiftlineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
