defmodule LocalWebMonitorex.ProcessInspector.Unsupported do
  @moduledoc "Keeps service discovery working on hosts without a process metrics adapter."

  @behaviour LocalWebMonitorex.ProcessInspector

  @impl true
  def snapshot(_ports), do: %{}
end
