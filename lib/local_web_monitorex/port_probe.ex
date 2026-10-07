defmodule LocalWebMonitorex.PortProbe do
  @moduledoc "Contract for checking whether a local port serves HTTP."

  @callback probe(pos_integer()) :: {:ok, LocalWebMonitorex.Service.t()} | :closed
end
