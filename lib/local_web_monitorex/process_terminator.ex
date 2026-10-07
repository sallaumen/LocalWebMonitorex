defmodule LocalWebMonitorex.ProcessTerminator do
  @moduledoc "Stops a confirmed listener only after checking its current port and identity."

  alias LocalWebMonitorex.ProcessControl
  alias LocalWebMonitorex.ProcessInspector
  alias LocalWebMonitorex.Service

  @spec stop(Service.t(), module(), module()) :: :ok | {:error, atom()}
  def stop(service, inspector \\ ProcessInspector.System, controller \\ ProcessControl.System)

  def stop(%Service{process: nil}, _inspector, _controller),
    do: {:error, :process_unavailable}

  def stop(%Service{port: port, process: process}, inspector, controller) do
    dashboard_port = Application.get_env(:local_web_monitorex, :dashboard_port, 4100)

    cond do
      port == dashboard_port or protected_pid?(process.pid) ->
        {:error, :protected_process}

      current_process?(inspector.snapshot([port])[port], process) ->
        controller.terminate(process.pid)

      true ->
        {:error, :stale_process}
    end
  end

  defp protected_pid?(pid) do
    own_pid = :os.getpid() |> to_string() |> String.to_integer()
    pid <= 4 or pid == own_pid
  end

  defp current_process?(nil, _process), do: false

  defp current_process?(current, process) do
    current.pid == process.pid and current.name == process.name
  end
end
