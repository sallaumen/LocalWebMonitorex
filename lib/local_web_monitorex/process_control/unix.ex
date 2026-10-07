defmodule LocalWebMonitorex.ProcessControl.Unix do
  @moduledoc "Sends SIGTERM to one process on macOS or Linux."

  @behaviour LocalWebMonitorex.ProcessControl

  alias LocalWebMonitorex.ProcessControl.Command

  @impl true
  def terminate(pid), do: terminate(pid, &Command.run/2)

  @spec terminate(pos_integer(), (String.t(), [String.t()] -> tuple())) ::
          :ok | {:error, atom()}
  def terminate(pid, runner) when is_integer(pid) and pid > 1 do
    Command.terminate("kill", ["-TERM", Integer.to_string(pid)], runner)
  end
end
