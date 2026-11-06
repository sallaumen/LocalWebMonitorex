defmodule LocalWebMonitorex.SweeperTest do
  use ExUnit.Case, async: false

  alias LocalWebMonitorex.ProcessInfo
  alias LocalWebMonitorex.Service
  alias LocalWebMonitorex.Settings
  alias LocalWebMonitorex.Sweeper
  alias LocalWebMonitorex.Sweeper.Finding

  defmodule Probe do
    @behaviour LocalWebMonitorex.PortProbe

    @impl true
    def probe(port) do
      record(port)
      Process.sleep(:persistent_term.get({LocalWebMonitorex.SweeperTest, :delay}, 0))

      case Map.get(:persistent_term.get({LocalWebMonitorex.SweeperTest, :open}), port) do
        :http -> {:ok, %Service{port: port, scheme: "http", status: 200, title: "Docs"}}
        :tcp -> :tcp_only
        nil -> :closed
      end
    end

    defp record(port) do
      Agent.update(:persistent_term.get({LocalWebMonitorex.SweeperTest, :calls}), &[port | &1])
    end
  end

  defmodule Inspector do
    @behaviour LocalWebMonitorex.ProcessInspector

    @impl true
    def snapshot(ports) do
      ports
      |> Enum.filter(&(&1 == 8080))
      |> Map.new(&{&1, %ProcessInfo{pid: 7, name: "python3", cpu_percent: nil, memory_bytes: 0}})
    end
  end

  setup do
    {:ok, calls} = Agent.start_link(fn -> [] end)
    :persistent_term.put({__MODULE__, :calls}, calls)
    :persistent_term.put({__MODULE__, :open}, %{})

    on_exit(fn ->
      for key <- [:calls, :open, :delay], do: :persistent_term.erase({__MODULE__, key})
    end)

    :ok = Sweeper.subscribe()
    {:ok, calls: calls}
  end

  defp start_sweeper(opts) do
    defaults = [
      name: :test_sweeper,
      enabled: true,
      probe: Probe,
      inspector: Inspector,
      start_delay: 0,
      batch_size: 4,
      batch_pause: 0,
      pass_interval: 60_000,
      watched_ports: [],
      dashboard_port: 4100
    ]

    start_supervised!({Sweeper, Keyword.merge(defaults, opts)})
  end

  defp probed(calls), do: calls |> Agent.get(& &1) |> Enum.sort()

  defp open_ports(ports), do: :persistent_term.put({__MODULE__, :open}, ports)

  test "sweeps only ports outside the watched range and the dashboard port", %{calls: calls} do
    start_sweeper(ports: 1..20, watched_ports: 5..10, dashboard_port: 15)

    assert_receive {:sweep_updated, %{phase: :waiting, checked: 13, total: 13}}, 2_000
    assert probed(calls) == [1, 2, 3, 4, 11, 12, 13, 14, 16, 17, 18, 19, 20]
  end

  test "records TCP and HTTP listeners with their process names" do
    open_ports(%{8080 => :http, 9000 => :tcp})
    sweeper = start_sweeper(ports: 8075..9005)

    assert_receive {:sweep_updated, %{phase: :waiting, findings: findings}}, 2_000

    assert [
             %Finding{port: 8080, http: true, status: 200, process_name: "python3"},
             %Finding{port: 9000, http: false, status: nil, process_name: nil}
           ] = findings

    assert %{last_pass_at: %DateTime{}, next_pass_at: %DateTime{}} = Sweeper.snapshot(sweeper)
  end

  test "waits the pass interval before sweeping again", %{calls: calls} do
    start_sweeper(ports: 1..8, pass_interval: 60_000)

    assert_receive {:sweep_updated, %{phase: :waiting}}, 2_000
    Process.sleep(300)
    assert length(probed(calls)) == 8
  end

  test "drops a port that closed by the next pass" do
    open_ports(%{3 => :tcp})
    start_sweeper(ports: 1..4, pass_interval: 50)

    assert_receive {:sweep_updated, %{phase: :waiting, findings: [%Finding{port: 3}]}}, 2_000
    open_ports(%{})
    assert_receive {:sweep_updated, %{phase: :waiting, findings: []}}, 2_000
  end

  test "pauses between batches so a pass never bursts", %{calls: calls} do
    start_sweeper(ports: 1..12, batch_size: 4, batch_pause: 200)

    assert_receive {:sweep_updated, %{phase: :sweeping, checked: 4}}, 2_000
    Process.sleep(100)
    assert length(probed(calls)) == 4
  end

  test "stops immediately when turned off and starts again when turned on", %{calls: calls} do
    path = sweep_path()
    :persistent_term.put({__MODULE__, :delay}, 100)
    open_ports(%{2 => :tcp})
    sweeper = start_sweeper(ports: 1..400, batch_size: 2)

    assert_receive {:sweep_updated, %{phase: :sweeping, checked: 2}}, 2_000
    assert :ok = Sweeper.set_enabled(false, sweeper)
    assert %{enabled: false, phase: :off, findings: []} = Sweeper.snapshot(sweeper)
    assert Settings.read_sweep(path) == false

    count = length(probed(calls))
    Process.sleep(300)
    assert length(probed(calls)) == count

    assert :ok = Sweeper.set_enabled(true, sweeper)
    assert Settings.read_sweep(path) == true
    assert_receive {:sweep_updated, %{enabled: true, phase: :sweeping, checked: 2}}, 2_000
  end

  test "does not sweep when the switch is off at start", %{calls: calls} do
    sweeper = start_sweeper(ports: 1..4, enabled: false)

    assert %{enabled: false, phase: :off, total: 4} = Sweeper.snapshot(sweeper)
    Process.sleep(100)
    assert probed(calls) == []
  end

  defp sweep_path do
    path =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-sweeper-#{System.unique_integer([:positive])}/sweep"
      )

    previous = Application.get_env(:local_web_monitorex, :sweep_settings_file)
    Application.put_env(:local_web_monitorex, :sweep_settings_file, path)

    on_exit(fn ->
      Application.put_env(:local_web_monitorex, :sweep_settings_file, previous)
      File.rm_rf!(Path.dirname(path))
    end)

    path
  end
end
