defmodule LocalWebMonitorex.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LocalWebMonitorexWeb.Telemetry,
      {Phoenix.PubSub, name: LocalWebMonitorex.PubSub},
      {Task.Supervisor, name: LocalWebMonitorex.TaskSupervisor},
      LocalWebMonitorex.Monitor,
      LocalWebMonitorex.Previews,
      LocalWebMonitorexWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: LocalWebMonitorex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LocalWebMonitorexWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
