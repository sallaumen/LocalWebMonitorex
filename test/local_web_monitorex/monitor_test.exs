defmodule LocalWebMonitorex.MonitorTest do
  use ExUnit.Case, async: false

  alias LocalWebMonitorex.Monitor
  alias LocalWebMonitorex.Service

  defmodule Probe do
    @behaviour LocalWebMonitorex.PortProbe

    @impl true
    def probe(4000) do
      case :persistent_term.get({LocalWebMonitorex.MonitorTest, :probe}) do
        :open -> {:ok, %Service{port: 4000, status: 200, scheme: "http", title: "Example"}}
        :closed -> :closed
      end
    end

    def probe(4020), do: raise("dashboard port was scanned")
  end

  test "excludes the dashboard port from discovery" do
    :ok = Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, "services")
    monitor = start_supervised!({Monitor, name: :excluded_monitor, ports: [4020], probe: Probe})

    assert_receive {:services_updated, %{services: [], scanning: false, checked_at: %DateTime{}}},
                   2_000

    assert GenServer.call(monitor, :snapshot).services == []
  end

  test "publishes when a service appears and disappears" do
    :persistent_term.put({__MODULE__, :probe}, :open)
    on_exit(fn -> :persistent_term.erase({__MODULE__, :probe}) end)
    :ok = Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, "services")

    monitor =
      start_supervised!(
        {Monitor, name: :test_monitor, ports: [4000], probe: Probe, interval: 60_000}
      )

    assert_receive {:services_updated, %{services: [%Service{port: 4000}]}}, 2_000
    assert Enum.map(GenServer.call(monitor, :snapshot).services, & &1.port) == [4000]

    :persistent_term.put({__MODULE__, :probe}, :closed)
    send(monitor, :scan)

    assert_receive {:services_updated, %{services: [], scanning: false, checked_at: %DateTime{}}},
                   2_000

    assert GenServer.call(monitor, :snapshot).services == []
  end
end
