defmodule LocalWebMonitorex.ProcessInspector.SystemTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.ProcessInspector.System

  test "selects one process adapter for each supported operating system" do
    assert System.adapter({:unix, :darwin}) == LocalWebMonitorex.ProcessInspector.MacOS
    assert System.adapter({:unix, :linux}) == LocalWebMonitorex.ProcessInspector.Linux
    assert System.adapter({:win32, :nt}) == LocalWebMonitorex.ProcessInspector.Windows
    assert System.adapter({:unix, :freebsd}) == LocalWebMonitorex.ProcessInspector.Unsupported
  end
end
