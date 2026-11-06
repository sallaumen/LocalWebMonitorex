defmodule LocalWebMonitorex.Monitor do
  @moduledoc """
  Publishes the current set of local web services and the progress of each scan.

  Only one scan runs at a time. The next scan is scheduled after the current one
  finishes, so a scan that outlasts the interval never overlaps another one.
  """

  use GenServer

  alias LocalWebMonitorex.Scanner
  alias LocalWebMonitorex.ProcessInspector

  @topic "services"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @spec snapshot() :: map()
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @spec refresh() :: :ok
  def refresh, do: GenServer.cast(__MODULE__, :refresh)

  @typedoc "How many watched ports the latest scan has checked."
  @type progress :: %{
          checked: non_neg_integer(),
          total: non_neg_integer(),
          scanning: boolean()
        }

  @doc """
  Subscribes to `{:services_updated, snapshot}` and `{:scan_progress, progress}`.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, @topic)

  @impl true
  def init(opts) do
    dashboard_port = Application.get_env(:local_web_monitorex, :dashboard_port, 4100)

    configured_ports =
      Keyword.get(
        opts,
        :ports,
        Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4500)
      )

    ports = Enum.reject(configured_ports, &(&1 == dashboard_port))

    state = %{
      ports: ports,
      total: length(ports),
      checked: 0,
      scan_id: nil,
      probe: Keyword.get(opts, :probe, LocalWebMonitorex.PortProbe.Http),
      inspector: Keyword.get(opts, :inspector, LocalWebMonitorex.ProcessInspector.System),
      interval: Keyword.get(opts, :interval, 5_000),
      services: [],
      checked_at: nil,
      scanning: false,
      task_ref: nil
    }

    send(self(), :scan)
    {:ok, state}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot(state), state}

  @impl true
  def handle_cast(:refresh, state) do
    send(self(), :scan)
    {:noreply, state}
  end

  @impl true
  def handle_info(:scan, %{scanning: true} = state), do: {:noreply, state}

  def handle_info(:scan, state) do
    scan_id = make_ref()

    task =
      Task.Supervisor.async_nolink(LocalWebMonitorex.TaskSupervisor, scan_job(state, scan_id))

    updated = %{state | scanning: true, task_ref: task.ref, scan_id: scan_id, checked: 0}
    publish(updated)
    publish_progress(updated)
    {:noreply, updated}
  end

  def handle_info({:scan_progress, scan_id, checked}, %{scan_id: scan_id} = state) do
    updated = %{state | checked: checked}
    publish_progress(updated)
    {:noreply, updated}
  end

  def handle_info({:scan_progress, _stale_scan, _checked}, state), do: {:noreply, state}

  def handle_info({ref, services}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    updated = %{
      state
      | services: services,
        checked_at: DateTime.utc_now(),
        scanning: false,
        task_ref: nil,
        scan_id: nil,
        checked: state.total
    }

    publish(updated)
    publish_progress(updated)
    Process.send_after(self(), :scan, state.interval)
    {:noreply, updated}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task_ref: ref} = state) do
    updated = %{state | scanning: false, task_ref: nil, scan_id: nil}
    publish(updated)
    publish_progress(updated)
    Process.send_after(self(), :scan, state.interval)
    {:noreply, updated}
  end

  defp scan_job(state, scan_id) do
    monitor = self()
    on_progress = &send(monitor, {:scan_progress, scan_id, &1})

    fn ->
      state.ports
      |> Scanner.scan(state.probe, on_progress: on_progress)
      |> ProcessInspector.enrich(state.inspector)
    end
  end

  defp snapshot(state) do
    state
    |> Map.take([:services, :checked_at, :scanning])
    |> Map.put(:progress, progress(state))
  end

  defp progress(state),
    do: %{checked: state.checked, total: state.total, scanning: state.scanning}

  defp publish(state), do: broadcast({:services_updated, snapshot(state)})

  defp publish_progress(state), do: broadcast({:scan_progress, progress(state)})

  defp broadcast(message),
    do: Phoenix.PubSub.broadcast(LocalWebMonitorex.PubSub, @topic, message)
end
