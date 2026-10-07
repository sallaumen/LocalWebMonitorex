defmodule LocalWebMonitorex.Monitor do
  @moduledoc "Publishes the current set of local web services."

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

    state = %{
      ports: Enum.reject(configured_ports, &(&1 == dashboard_port)),
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
  def handle_call(:snapshot, _from, state),
    do: {:reply, Map.take(state, [:services, :checked_at, :scanning]), state}

  @impl true
  def handle_cast(:refresh, state) do
    send(self(), :scan)
    {:noreply, state}
  end

  @impl true
  def handle_info(:scan, %{scanning: true} = state), do: {:noreply, state}

  def handle_info(:scan, state) do
    task =
      Task.Supervisor.async_nolink(LocalWebMonitorex.TaskSupervisor, fn ->
        state.ports
        |> Scanner.scan(state.probe)
        |> ProcessInspector.enrich(state.inspector)
      end)

    updated = %{state | scanning: true, task_ref: task.ref}
    publish(updated)
    {:noreply, updated}
  end

  def handle_info({ref, services}, %{task_ref: ref} = state) do
    Process.demonitor(ref, [:flush])

    updated = %{
      state
      | services: services,
        checked_at: DateTime.utc_now(),
        scanning: false,
        task_ref: nil
    }

    publish(updated)
    Process.send_after(self(), :scan, state.interval)
    {:noreply, updated}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task_ref: ref} = state) do
    updated = %{state | scanning: false, task_ref: nil}
    publish(updated)
    Process.send_after(self(), :scan, state.interval)
    {:noreply, updated}
  end

  defp publish(state) do
    snapshot = Map.take(state, [:services, :checked_at, :scanning])
    Phoenix.PubSub.broadcast(LocalWebMonitorex.PubSub, @topic, {:services_updated, snapshot})
  end
end
