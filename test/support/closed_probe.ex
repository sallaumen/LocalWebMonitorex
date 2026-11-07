defmodule LocalWebMonitorex.Test.ClosedProbe do
  @moduledoc "A port probe that reports every port as closed."

  @behaviour LocalWebMonitorex.PortProbe

  @impl true
  def probe(_port), do: :closed
end
