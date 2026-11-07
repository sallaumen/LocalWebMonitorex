defmodule LocalWebMonitorex.Sweeper.Finding do
  @moduledoc "A loopback port outside the watched range that accepted a TCP connection."

  alias LocalWebMonitorex.Service

  @enforce_keys [:port, :http]
  defstruct [:port, :http, :scheme, :status, :title, :process_name]

  @type t :: %__MODULE__{
          port: pos_integer(),
          http: boolean(),
          scheme: String.t() | nil,
          status: pos_integer() | nil,
          title: String.t() | nil,
          process_name: String.t() | nil
        }

  @doc "Builds a finding from a probe result, or returns nil for a closed port."
  @spec from_probe(pos_integer(), LocalWebMonitorex.PortProbe.result()) :: t() | nil
  def from_probe(port, {:ok, %Service{} = service}) do
    %__MODULE__{
      port: port,
      http: true,
      scheme: service.scheme,
      status: service.status,
      title: service.title
    }
  end

  def from_probe(port, :tcp_only), do: %__MODULE__{port: port, http: false}
  def from_probe(_port, _result), do: nil

  @spec url(t()) :: String.t() | nil
  def url(%__MODULE__{http: true, scheme: scheme, port: port}),
    do: "#{scheme}://localhost:#{port}"

  def url(%__MODULE__{}), do: nil
end
