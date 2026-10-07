defmodule LocalWebMonitorex.ProcessInspector.MacOS do
  @moduledoc "Collects process metrics for local TCP listeners on macOS."

  @behaviour LocalWebMonitorex.ProcessInspector

  @impl true
  def snapshot(ports), do: LocalWebMonitorex.ProcessInspector.Lsof.snapshot(ports)
end
