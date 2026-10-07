defmodule LocalWebMonitorex.ProcessInspector.Lsof do
  @moduledoc "Reads local TCP listeners with lsof and samples their CPU and RSS with ps."

  @behaviour LocalWebMonitorex.ProcessInspector

  require Logger

  alias LocalWebMonitorex.ProcessInfo

  @impl true
  def snapshot(ports), do: snapshot(ports, &System.cmd/2)

  @spec snapshot([pos_integer()], (String.t(), [String.t()] -> {String.t(), integer()})) ::
          %{optional(pos_integer()) => ProcessInfo.t()}
  def snapshot([], _runner), do: %{}

  def snapshot(ports, runner) do
    with {listeners, 0} <- runner.("lsof", lsof_args(ports)),
         port_pids when map_size(port_pids) > 0 <- listener_pids(listeners, ports),
         {processes, 0} <- runner.("ps", ps_args(port_pids)) do
      details = process_details(processes)

      Map.new(port_pids, fn {port, pid} -> {port, Map.get(details, pid)} end)
      |> Enum.reject(fn {_port, process} -> is_nil(process) end)
      |> Map.new()
    else
      _ -> %{}
    end
  rescue
    error in [ErlangError, ArgumentError] ->
      Logger.debug("Process metrics unavailable: #{Exception.message(error)}")
      %{}
  end

  defp lsof_args(ports) do
    ["-nP", "-iTCP:#{Enum.min(ports)}-#{Enum.max(ports)}", "-sTCP:LISTEN", "-Fpcn"]
  end

  defp ps_args(port_pids) do
    pids = port_pids |> Map.values() |> Enum.uniq() |> Enum.sort() |> Enum.join(",")
    ["-p", pids, "-o", "pid=", "-o", "%cpu=", "-o", "rss=", "-o", "comm="]
  end

  defp listener_pids(output, ports) do
    allowed = MapSet.new(ports)

    output
    |> String.split("\n", trim: true)
    |> Enum.reduce({nil, %{}}, fn line, {pid, found} ->
      listener_field(line, pid, found, allowed)
    end)
    |> elem(1)
  end

  defp listener_field("p" <> value, _pid, found, _allowed) do
    case Integer.parse(value) do
      {pid, ""} -> {pid, found}
      _ -> {nil, found}
    end
  end

  defp listener_field("n" <> address, pid, found, allowed) when is_integer(pid) do
    case Regex.run(~r/:(\d+)$/, address) do
      [_, value] ->
        port = String.to_integer(value)

        if MapSet.member?(allowed, port),
          do: {pid, Map.put_new(found, port, pid)},
          else: {pid, found}

      _ ->
        {pid, found}
    end
  end

  defp listener_field(_line, pid, found, _allowed), do: {pid, found}

  defp process_details(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_process/1)
    |> Map.new()
  end

  defp parse_process(line) do
    case Regex.run(~r/^\s*(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/, line) do
      [_, pid, cpu, rss, name] ->
        process = %ProcessInfo{
          pid: String.to_integer(pid),
          name: Path.basename(String.trim(name)),
          cpu_percent: String.to_float(cpu),
          memory_bytes: String.to_integer(rss) * 1024
        }

        [{process.pid, process}]

      _ ->
        []
    end
  end
end
