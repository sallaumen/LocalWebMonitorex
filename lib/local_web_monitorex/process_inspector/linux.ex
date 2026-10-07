defmodule LocalWebMonitorex.ProcessInspector.Linux do
  @moduledoc "Collects process metrics for local TCP listeners on Linux when lsof is installed."

  @behaviour LocalWebMonitorex.ProcessInspector

  @impl true
  def snapshot(ports), do: LocalWebMonitorex.ProcessInspector.Lsof.snapshot(ports)
end
