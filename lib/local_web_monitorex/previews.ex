defmodule LocalWebMonitorex.Previews do
  @moduledoc "Caches bounded, on-demand screenshots of discovered services."

  use GenServer

  require Logger

  alias LocalWebMonitorex.Service

  @topic "previews"
  @refresh_ms 30_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec request(Service.t()) :: :ok
  def request(service), do: GenServer.cast(__MODULE__, {:request, service})

  @spec image(pos_integer()) :: {:ok, String.t(), integer()} | :missing
  def image(port), do: GenServer.call(__MODULE__, {:image, port})

  @spec version(pos_integer()) :: integer() | nil
  def version(port), do: GenServer.call(__MODULE__, {:version, port})

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(LocalWebMonitorex.PubSub, @topic)

  @impl true
  def init(opts) do
    dir =
      Keyword.get(
        opts,
        :dir,
        Path.join(System.tmp_dir!(), "local_web_monitorex-previews-#{:os.getpid()}")
      )

    File.mkdir_p!(dir)
    {:ok, %{dir: dir, queue: :queue.new(), pending: MapSet.new(), active: nil, cache: %{}}}
  end

  @impl true
  def handle_call({:image, port}, _from, state) do
    reply =
      case Map.get(state.cache, port) do
        {version, _checked} -> {:ok, image_path(state.dir, port), version}
        nil -> :missing
      end

    {:reply, reply, state}
  end

  def handle_call({:version, port}, _from, state) do
    version =
      case Map.get(state.cache, port) do
        {value, _checked} -> value
        nil -> nil
      end

    {:reply, version, state}
  end

  @impl true
  def handle_cast({:request, %Service{port: port} = service}, state) do
    if allowed?(port) and stale?(state, port) and not MapSet.member?(state.pending, port) do
      updated = %{
        state
        | queue: :queue.in(service, state.queue),
          pending: MapSet.put(state.pending, port)
      }

      {:noreply, start_next(updated)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, result}, %{active: {ref, port}} = state) do
    Process.demonitor(ref, [:flush])
    updated = finish_capture(state, port, result)
    {:noreply, start_next(%{updated | active: nil})}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{active: {ref, port}} = state) do
    Logger.warning("Preview worker stopped", port: port, reason: inspect(reason))
    updated = %{state | active: nil, pending: MapSet.delete(state.pending, port)}
    {:noreply, start_next(updated)}
  end

  defp allowed?(port) when is_integer(port) do
    port in Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4099) and
      port != Application.get_env(:local_web_monitorex, :dashboard_port, 4100)
  end

  defp allowed?(_port), do: false

  defp stale?(state, port) do
    case Map.get(state.cache, port) do
      nil -> true
      {_version, checked} -> System.monotonic_time(:millisecond) - checked >= @refresh_ms
    end
  end

  defp start_next(%{active: {_ref, _port}} = state), do: state

  defp start_next(state) do
    case :queue.out(state.queue) do
      {{:value, service}, queue} ->
        path = image_path(state.dir, service.port)

        task =
          Task.Supervisor.async_nolink(LocalWebMonitorex.TaskSupervisor, fn ->
            capture(service, path)
          end)

        %{state | queue: queue, active: {task.ref, service.port}}

      {:empty, _queue} ->
        state
    end
  end

  defp finish_capture(state, port, :ok) do
    version = System.system_time(:millisecond)
    checked = System.monotonic_time(:millisecond)
    Phoenix.PubSub.broadcast(LocalWebMonitorex.PubSub, @topic, {:preview_ready, port, version})

    %{
      state
      | cache: Map.put(state.cache, port, {version, checked}),
        pending: MapSet.delete(state.pending, port)
    }
  end

  defp finish_capture(state, port, {:error, reason}) do
    Logger.warning("Preview capture failed", port: port, reason: reason)
    %{state | pending: MapSet.delete(state.pending, port)}
  end

  defp capture(service, path) do
    script = Path.expand("../../assets/capture.mjs", __DIR__)
    url = "#{service.scheme}://127.0.0.1:#{service.port}/"

    case System.cmd("node", [script, url, path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, String.slice(String.trim(output), 0, 200)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp image_path(dir, port), do: Path.join(dir, "#{port}.png")
end
