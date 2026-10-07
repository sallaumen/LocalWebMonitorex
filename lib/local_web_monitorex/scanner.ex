defmodule LocalWebMonitorex.Scanner do
  @moduledoc "Checks a configured port range with bounded concurrency."

  alias LocalWebMonitorex.Service

  @spec scan(Enumerable.t(), module()) :: [Service.t()]
  def scan(ports, probe \\ LocalWebMonitorex.PortProbe.Http) do
    ports
    |> Task.async_stream(&probe.probe/1,
      max_concurrency: 16,
      timeout: 3_500,
      on_timeout: :kill_task
    )
    |> Enum.flat_map(&service_result/1)
    |> Enum.sort_by(& &1.port)
  end

  defp service_result({:ok, {:ok, service}}), do: [service]
  defp service_result(_result), do: []
end
