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
    def probe(_port), do: :closed
  end

  test "keeps responding web services and sorts them by port" do
    assert Enum.map(Scanner.scan(4002..4000//-1, Probe), & &1.port) == [4000, 4002]
  end

  test "reports how many ports it has checked, finishing at the range size" do
    test_pid = self()

    Scanner.scan(1..1_000, Probe, on_progress: &send(test_pid, {:checked, &1}))

    counts = collect_progress([])

    assert counts == Enum.sort(counts)
    assert List.last(counts) == 1_000
    assert length(counts) in 2..101
  end

  test "reports every checked port when the range is small" do
    test_pid = self()

    Scanner.scan(4000..4002, Probe, on_progress: &send(test_pid, {:checked, &1}))

    assert collect_progress([]) == [1, 2, 3]
  end

  test "scans the full port space with bounded work" do
    {elapsed, services} = :timer.tc(fn -> Scanner.scan(1..65_535, Probe) end)

    assert Enum.map(services, & &1.port) == [4000, 4002]
    assert elapsed < 10_000_000
  end

  defp collect_progress(counts) do
    receive do
      {:checked, count} -> collect_progress([count | counts])
    after
      0 -> Enum.reverse(counts)
    end
  end
end
