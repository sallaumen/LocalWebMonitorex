defmodule LocalWebMonitorex.Sweeper do
  @defaults [
    ports: 1..65_535,
    batch_size: 32,
    concurrency: 4,
    batch_pause: 1_000,
    probe_timeout: 4_000,
    pass_interval: :timer.hours(1),
    start_delay: :timer.minutes(1),
    probe: LocalWebMonitorex.PortProbe.Http,
    inspector: LocalWebMonitorex.ProcessInspector.System
  ]

  @moduledoc """
  Slowly sweeps loopback ports outside the watched range.

  The sweep runs apart from `LocalWebMonitorex.Monitor`. It checks
  #{@defaults[:batch_size]} ports at a time, at most #{@defaults[:concurrency]}
  at once, and waits #{@defaults[:batch_pause]} ms between batches, so a full
  pass over 127.0.0.1 takes about 45 minutes. The next pass starts an hour
  after the previous one finishes. The watched range and the dashboard port are
  never probed here, and no screenshots are taken.
  """

  use GenServer

  alias LocalWebMonitorex.Settings
  alias LocalWebMonitorex.Sweeper.Finding

  @topic "sweep"

  @type phase :: :off | :waiting | :sweeping
  @type snapshot :: %{
          enabled: boolean(),
          phase: phase(),
          checked: non_neg_integer(),
          total: non_neg_integer(),
          findings: [Finding.t()],
          last_pass_at: DateTime.t() | nil,
          next_pass_at: DateTime.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @spec snapshot(GenServer.server()) :: snapshot()
  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  @doc "Saves the switch, then starts or stops sweeping right away."
  @spec set_enabled(boolean(), GenServer.server()) ::
          :ok | {:error, :invalid_sweep | File.posix()}
  def set_enabled(enabled, server \\ __MODULE__) when is_boolean(enabled) do
    with :ok <- Settings.save_sweep(enabled) do
      GenServer.call(server, {:set_enabled, enabled})
    end
  end

  @doc "Subscribes to `{:sweep_updated, snapshot}` messages."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, @topic)

  @doc "Returns the next ports to probe from `cursor`, skipping excluded ones."
  @spec take_batch(pos_integer(), Range.t(), pos_integer(), MapSet.t()) ::
          {[pos_integer()], pos_integer()}
  def take_batch(cursor, %Range{last: last}, size, excluded) do
    ports =
      cursor..last//1
      |> Stream.reject(&MapSet.member?(excluded, &1))
      |> Enum.take(size)

    {ports, next_cursor(ports, last)}
  end

  defp next_cursor([], last), do: last + 1
  defp next_cursor(ports, _last), do: List.last(ports) + 1

  @impl true
  def init(opts) do
    # Trapping exits makes the supervisor's shutdown run terminate/2, which ends a running batch.
    Process.flag(:trap_exit, true)
    config = @defaults |> Keyword.merge(opts) |> Map.new()
    excluded = excluded_ports(opts)
    enabled = Keyword.get_lazy(opts, :enabled, &Settings.read_sweep/0)

    state = %{
      config: config,
      excluded: excluded,
      total: Enum.count(config.ports, &(not MapSet.member?(excluded, &1))),
      enabled: enabled,
      phase: :off,
      generation: 0,
      cursor: config.ports.first,
      checked: 0,
      batch: [],
      task: nil,
      findings: %{},
      last_pass_at: nil,
      next_pass_at: nil
    }

    {:ok, if(enabled, do: schedule_pass(state, config.start_delay), else: state)}
  end

  defp excluded_ports(opts) do
    watched = Keyword.get_lazy(opts, :watched_ports, fn -> app_env(:monitor_ports, []) end)
    dashboard = Keyword.get_lazy(opts, :dashboard_port, fn -> app_env(:dashboard_port, 4100) end)

    watched
    |> MapSet.new()
    |> MapSet.put(dashboard)
  end

  defp app_env(key, default), do: Application.get_env(:local_web_monitorex, key, default)

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, snapshot_of(state), state}

  def handle_call({:set_enabled, enabled}, _from, %{enabled: enabled} = state),
    do: {:reply, :ok, state}

  def handle_call({:set_enabled, true}, _from, state) do
    updated = schedule_pass(%{state | enabled: true}, 0)
    publish(updated)
    {:reply, :ok, updated}
  end

  def handle_call({:set_enabled, false}, _from, state) do
    updated = stop(state)
    publish(updated)
    {:reply, :ok, updated}
  end

  @impl true
  def handle_info({:start_pass, generation}, %{generation: generation, phase: :waiting} = state) do
    state
    |> Map.merge(%{phase: :sweeping, cursor: state.config.ports.first, checked: 0})
    |> Map.put(:next_pass_at, nil)
    |> run_batch()
  end

  def handle_info({:next_batch, generation}, %{generation: generation, task: nil} = state)
      when state.phase == :sweeping,
      do: run_batch(state)

  def handle_info({ref, findings}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_batch(state, findings)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %Task{ref: ref}} = state),
    do: {:noreply, finish_batch(state, [])}

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: shutdown_task(state.task)

  defp run_batch(state) do
    {ports, cursor} =
      take_batch(state.cursor, state.config.ports, batch_size(state), state.excluded)

    case ports do
      [] ->
        {:noreply, finish_pass(state)}

      ports ->
        {:noreply, %{state | batch: ports, cursor: cursor, task: start_probe(ports, state)}}
    end
  end

  defp batch_size(state), do: state.config.batch_size

  defp start_probe(ports, %{config: config}) do
    Task.Supervisor.async_nolink(LocalWebMonitorex.TaskSupervisor, fn ->
      ports
      |> probe_ports(config)
      |> with_process_names(config.inspector)
    end)
  end

  defp probe_ports(ports, %{probe: probe} = config) do
    ports
    |> Task.async_stream(&probe.probe/1,
      max_concurrency: config.concurrency,
      timeout: config.probe_timeout,
      on_timeout: :kill_task
    )
    |> Enum.zip(ports)
    |> Enum.flat_map(fn
      {{:ok, result}, port} -> List.wrap(Finding.from_probe(port, result))
      {{:exit, _reason}, _port} -> []
    end)
  end

  defp with_process_names([], _inspector), do: []

  defp with_process_names(findings, inspector) do
    processes = inspector.snapshot(Enum.map(findings, & &1.port))
    Enum.map(findings, &%{&1 | process_name: process_name(processes[&1.port])})
  end

  defp process_name(nil), do: nil
  defp process_name(process), do: process.name

  defp finish_batch(state, findings) do
    found = Map.new(findings, &{&1.port, &1})

    updated = %{
      state
      | task: nil,
        checked: state.checked + length(state.batch),
        findings: state.findings |> Map.drop(state.batch) |> Map.merge(found),
        batch: []
    }

    publish(updated)
    Process.send_after(self(), {:next_batch, updated.generation}, state.config.batch_pause)
    updated
  end

  defp finish_pass(state) do
    updated = schedule_pass(%{state | last_pass_at: now()}, state.config.pass_interval)
    publish(updated)
    updated
  end

  defp schedule_pass(state, delay) do
    Process.send_after(self(), {:start_pass, state.generation}, delay)
    %{state | phase: :waiting, next_pass_at: DateTime.add(now(), delay, :millisecond)}
  end

  defp shutdown_task(nil), do: :ok

  defp shutdown_task(task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp stop(state) do
    shutdown_task(state.task)

    %{
      state
      | enabled: false,
        phase: :off,
        generation: state.generation + 1,
        task: nil,
        batch: [],
        checked: 0,
        findings: %{},
        next_pass_at: nil
    }
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp snapshot_of(state) do
    state
    |> Map.take([:enabled, :phase, :checked, :total, :last_pass_at, :next_pass_at])
    |> Map.put(:findings, state.findings |> Map.values() |> Enum.sort_by(& &1.port))
  end

  defp publish(state),
    do:
      Phoenix.PubSub.broadcast(
        LocalWebMonitorex.PubSub,
        @topic,
        {:sweep_updated, snapshot_of(state)}
      )
end
