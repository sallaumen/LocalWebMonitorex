defmodule LocalWebMonitorex.MonitorTest do
  use ExUnit.Case, async: false

  alias LocalWebMonitorex.Monitor
  alias LocalWebMonitorex.Service

  setup do
    previous = Application.get_env(:local_web_monitorex, :dashboard_port)
    Application.put_env(:local_web_monitorex, :dashboard_port, 4100)
    on_exit(fn -> Application.put_env(:local_web_monitorex, :dashboard_port, previous) end)
  end

  defmodule Probe do
    @behaviour LocalWebMonitorex.PortProbe

    @impl true
    def probe(4000) do
      case :persistent_term.get({LocalWebMonitorex.MonitorTest, :probe}) do
        :open -> {:ok, %Service{port: 4000, status: 200, scheme: "http", title: "Example"}}
        :closed -> :closed
      end
    end

    def probe(4100), do: raise("dashboard port was scanned")
  end

  defmodule Inspector do
    @behaviour LocalWebMonitorex.ProcessInspector

    @impl true
    def snapshot([4000]) do
      cpu = :persistent_term.get({LocalWebMonitorex.MonitorTest, :cpu}, 1.5)

      %{
        4000 => %LocalWebMonitorex.ProcessInfo{
          pid: 42,
          name: "node",
          cpu_percent: cpu,
          memory_bytes: 52_428_800
        }
      }
    end
  end

  test "excludes the dashboard port from discovery" do
    :ok = Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, "services")
    monitor = start_supervised!({Monitor, name: :excluded_monitor, ports: [4100], probe: Probe})

    assert_receive {:services_updated, %{services: [], scanning: false, checked_at: %DateTime{}}},
                   2_000

    assert GenServer.call(monitor, :snapshot).services == []
  end

  test "publishes appearances, metric changes, and disappearances" do
    :persistent_term.put({__MODULE__, :probe}, :open)

    on_exit(fn ->
      :persistent_term.erase({__MODULE__, :probe})
      :persistent_term.erase({__MODULE__, :cpu})
    end)

    :ok = Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, "services")

    monitor =
      start_supervised!(
        {Monitor,
         name: :test_monitor, ports: [4000], probe: Probe, inspector: Inspector, interval: 60_000}
      )

    assert_receive {:services_updated, %{services: [%Service{port: 4000, process: %{pid: 42}}]}},
                   2_000

    assert Enum.map(GenServer.call(monitor, :snapshot).services, & &1.port) == [4000]

    :persistent_term.put({__MODULE__, :cpu}, 7.5)
    send(monitor, :scan)

    assert_receive {:services_updated,
                    %{services: [%Service{port: 4000, process: %{cpu_percent: 7.5}}]}},
                   2_000

    :persistent_term.put({__MODULE__, :probe}, :closed)
    send(monitor, :scan)

    assert_receive {:services_updated, %{services: [], scanning: false, checked_at: %DateTime{}}},
                   2_000

    assert GenServer.call(monitor, :snapshot).services == []
  end
end
