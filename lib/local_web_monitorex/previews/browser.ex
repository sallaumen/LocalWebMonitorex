defmodule LocalWebMonitorex.Previews.Browser do
  @moduledoc "Captures one local page with the bundled headless browser script."

  alias LocalWebMonitorex.CaptureRuntime
  alias LocalWebMonitorex.Service

  @spec capture(Service.t(), Path.t()) :: :ok | {:error, String.t()}
  def capture(service, path) do
    {node, script} = CaptureRuntime.paths()
    url = "#{service.scheme}://127.0.0.1:#{service.port}/"

    case System.cmd(node, [script, url, path], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, String.slice(String.trim(output), 0, 200)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
