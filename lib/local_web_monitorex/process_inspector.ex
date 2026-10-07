defmodule LocalWebMonitorex.ProcessInspector do
  @moduledoc "The boundary for optional local process metrics."

  alias LocalWebMonitorex.ProcessInfo
  alias LocalWebMonitorex.Service

  @callback snapshot([pos_integer()]) :: %{optional(pos_integer()) => ProcessInfo.t()}

  @spec enrich([Service.t()], module()) :: [Service.t()]
  def enrich([], _inspector), do: []

  def enrich(services, inspector) do
    processes = inspector.snapshot(Enum.map(services, & &1.port))
    Enum.map(services, &%{&1 | process: Map.get(processes, &1.port)})
  end
end
