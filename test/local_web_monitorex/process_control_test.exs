defmodule LocalWebMonitorex.ProcessControlTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.ProcessControl

  test "selects an operating-system-specific controller" do
    expected = [
      {{:unix, :darwin}, ProcessControl.Unix},
      {{:unix, :linux}, ProcessControl.Unix},
      {{:win32, :nt}, ProcessControl.Windows},
      {{:unix, :freebsd}, ProcessControl.Unsupported}
    ]

    for {os, controller} <- expected do
      assert ProcessControl.System.adapter(os) == controller
    end
  end

  test "sends TERM to one Unix PID without invoking a shell" do
    runner = fn command, args ->
      send(self(), {:command, command, args})
      {"", 0}
    end

    assert :ok = ProcessControl.Unix.terminate(42, runner)
    assert_receive {:command, "kill", ["-TERM", "42"]}
  end

  test "ends one Windows PID without including its child tree" do
    runner = fn command, args ->
      send(self(), {:command, command, args})
      {"SUCCESS", 0}
    end

    assert :ok = ProcessControl.Windows.terminate(42, runner)
    assert_receive {:command, "taskkill", ["/F", "/PID", "42"]}
  end

  test "returns a useful error when an OS command fails" do
    runner = fn _command, _args -> {"Access is denied", 1} end

    assert {:error, :command_failed} = ProcessControl.Unix.terminate(42, runner)
    assert {:error, :command_failed} = ProcessControl.Windows.terminate(42, runner)
    assert {:error, :unsupported_os} = ProcessControl.Unsupported.terminate(42)
  end
end
