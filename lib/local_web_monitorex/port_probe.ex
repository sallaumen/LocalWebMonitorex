defmodule LocalWebMonitorex.PortProbe do
  @moduledoc """
  Contract for checking a local port.

  A probe returns the HTTP(S) service on the port, `:tcp_only` when the port
  accepts TCP connections but answers neither HTTP nor HTTPS, or `:closed`.
  """

  @type result :: {:ok, LocalWebMonitorex.Service.t()} | :tcp_only | :closed

  @callback probe(pos_integer()) :: result()
end
