defmodule LocalWebMonitorex.Scanner do
  @max_concurrency 16
  @probe_timeout 3_500
  @progress_updates 100

  @moduledoc """
  Checks a configured port range with bounded concurrency.

  At most #{@max_concurrency} probes run at once and each one is killed after
  #{@probe_timeout} ms, so even the full port space keeps a fixed amount of
  work in flight.
  """

  alias LocalWebMonitorex.Service

  @type option :: {:on_progress, (non_neg_integer() -> any())}

  @doc """
  Probes every port and returns the responding services sorted by port.

  `:on_progress` receives the cumulative number of checked ports about
  #{@progress_updates} times per scan, always ending with the range size.
  """
  @spec scan(Enumerable.t(), module(), [option()]) :: [Service.t()]
  def scan(ports, probe \\ LocalWebMonitorex.PortProbe.Http, opts \\ []) do
    total = Enum.count(ports)
    report = progress_reporter(total, Keyword.get(opts, :on_progress))

    ports
    |> Task.async_stream(&probe.probe/1,
      max_concurrency: @max_concurrency,
      timeout: @probe_timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.with_index(1)
    |> Stream.each(report)
    |> Enum.flat_map(fn {result, _checked} -> service_result(result) end)
    |> Enum.sort_by(& &1.port)
  end

  @doc "Returns how many checked ports pass between progress reports."
  @spec progress_step(non_neg_integer()) :: pos_integer()
  def progress_step(total), do: max(div(total, @progress_updates), 1)

  defp progress_reporter(_total, nil), do: fn _result -> :ok end

  defp progress_reporter(total, on_progress) do
    step = progress_step(total)

    fn {_result, checked} ->
      if rem(checked, step) == 0 or checked == total, do: on_progress.(checked)
    end
  end

  defp service_result({:ok, {:ok, service}}), do: [service]
  defp service_result(_result), do: []
end
