defmodule LocalWebMonitorex.ProcessControl.Windows do
  @moduledoc "Ends one process by PID on Windows without ending its child tree."

  @behaviour LocalWebMonitorex.ProcessControl

  alias LocalWebMonitorex.ProcessControl.Command

  @impl true
  def terminate(pid), do: terminate(pid, &Command.run/2)

  @spec terminate(pos_integer(), (String.t(), [String.t()] -> tuple())) ::
          :ok | {:error, atom()}
  def terminate(pid, runner) when is_integer(pid) and pid > 4 do
    Command.terminate("taskkill", ["/F", "/PID", Integer.to_string(pid)], runner)
  end
end
