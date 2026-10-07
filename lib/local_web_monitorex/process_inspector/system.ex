defmodule LocalWebMonitorex.ProcessInspector.System do
  @moduledoc "Selects the process inspector for the current operating system."

  @behaviour LocalWebMonitorex.ProcessInspector

  alias LocalWebMonitorex.ProcessInspector

  @impl true
  def snapshot(ports), do: adapter().snapshot(ports)

  @spec adapter(tuple()) :: module()
  def adapter(os \\ :os.type())
  def adapter({:unix, :darwin}), do: ProcessInspector.MacOS
  def adapter({:unix, :linux}), do: ProcessInspector.Linux
  def adapter({:win32, _name}), do: ProcessInspector.Windows
  def adapter(_os), do: ProcessInspector.Unsupported
end
