defmodule LocalWebMonitorex.ProcessControl.System do
  @moduledoc "Selects the process controller for the current operating system."

  @behaviour LocalWebMonitorex.ProcessControl

  alias LocalWebMonitorex.ProcessControl

  @impl true
  def terminate(pid), do: adapter().terminate(pid)

  @spec adapter(tuple()) :: module()
  def adapter(os \\ :os.type())
  def adapter({:unix, :darwin}), do: ProcessControl.Unix
  def adapter({:unix, :linux}), do: ProcessControl.Unix
  def adapter({:win32, _name}), do: ProcessControl.Windows
  def adapter(_os), do: ProcessControl.Unsupported
end
