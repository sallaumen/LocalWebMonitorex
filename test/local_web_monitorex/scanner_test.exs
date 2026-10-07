defmodule LocalWebMonitorex.ScannerTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.Scanner
  alias LocalWebMonitorex.Service

  defmodule Probe do
    @behaviour LocalWebMonitorex.PortProbe

    @impl true
    def probe(4000), do: {:ok, %Service{port: 4000, status: 200, scheme: "http", title: "Web"}}
    def probe(4001), do: :closed
    def probe(4002), do: {:ok, %Service{port: 4002, status: 404, scheme: "http", title: nil}}
  end

  test "keeps responding web services and sorts them by port" do
    assert Enum.map(Scanner.scan(4002..4000//-1, Probe), & &1.port) == [4000, 4002]
  end
end
