defmodule LocalWebMonitorex.ProcessInspector.Windows do
  @moduledoc "Reads listening processes and working sets through Windows PowerShell."

  @behaviour LocalWebMonitorex.ProcessInspector

  require Logger

  alias LocalWebMonitorex.ProcessInfo

  @impl true
  def snapshot(ports), do: snapshot(ports, &System.cmd/2)

  @spec snapshot([pos_integer()], (String.t(), [String.t()] -> {String.t(), integer()})) ::
          %{optional(pos_integer()) => ProcessInfo.t()}
  def snapshot([], _runner), do: %{}

  def snapshot(ports, runner) do
    case runner.("powershell.exe", powershell_args(ports)) do
      {output, 0} -> decode_processes(output, MapSet.new(ports))
      _ -> %{}
    end
  rescue
    error in [ErlangError, ArgumentError] ->
      Logger.debug("Windows process metrics unavailable: #{Exception.message(error)}")
      %{}
  end

  defp powershell_args(ports) do
    values = Enum.join(ports, ",")

    script = """
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $ports = @(#{values})
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
      Where-Object { $ports -contains [int]$_.LocalPort } |
      ForEach-Object {
        $ownerId = $_.OwningProcess
        $owner = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
        if ($owner) {
          [PSCustomObject]@{
            port = [int]$_.LocalPort
            pid = [int]$ownerId
            name = [string]$owner.ProcessName
            memory_bytes = [int64]$owner.WorkingSet64
          }
        }
      } | ConvertTo-Json -Compress
    """

    ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script]
  end

  defp decode_processes(output, allowed) do
    case Jason.decode(String.trim(output)) do
      {:ok, items} when is_list(items) -> process_map(items, allowed)
      {:ok, item} when is_map(item) -> process_map([item], allowed)
      _ -> %{}
    end
  end

  defp process_map(items, allowed) do
    items
    |> Enum.flat_map(&parse_process(&1, allowed))
    |> Map.new()
  end

  defp parse_process(
         %{"port" => port, "pid" => pid, "name" => name, "memory_bytes" => memory},
         allowed
       )
       when is_integer(port) and is_integer(pid) and pid > 0 and is_binary(name) and
              is_integer(memory) and memory >= 0 do
    if MapSet.member?(allowed, port) do
      [{port, %ProcessInfo{pid: pid, name: name, cpu_percent: nil, memory_bytes: memory}}]
    else
      []
    end
  end

  defp parse_process(_item, _allowed), do: []
end
