defmodule LocalWebMonitorex.ProcessInspector.WindowsTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.ProcessInspector.Windows

  test "maps Windows listeners to PID and working set without claiming a CPU percentage" do
    runner = fn "powershell.exe", _args ->
      {~s([{"port":4005,"pid":42,"name":"node","memory_bytes":52428800},{"port":4999,"pid":72,"name":"other","memory_bytes":1024}]),
       0}
    end

    assert %{4005 => process} = Windows.snapshot([4005], runner)
    assert process.pid == 42
    assert process.name == "node"
    assert process.memory_bytes == 52_428_800
    assert process.cpu_percent == nil
    refute Map.has_key?(Windows.snapshot([4005], runner), 4999)
  end

  test "accepts PowerShell's single-object JSON output and tolerates unavailable commands" do
    one = fn "powershell.exe", _args ->
      {~s({"port":4005,"pid":42,"name":"node","memory_bytes":1024}), 0}
    end

    missing = fn _command, _args -> raise ErlangError, original: :enoent end

    assert Windows.snapshot([4005], one)[4005].pid == 42
    assert Windows.snapshot([4005], missing) == %{}
    assert Windows.snapshot([], missing) == %{}
  end

  if match?({:win32, _}, :os.type()) do
    test "reads a real loopback listener on Windows" do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      on_exit(fn -> :gen_tcp.close(socket) end)
      {:ok, {_address, port}} = :inet.sockname(socket)

      assert %{^port => process} = Windows.snapshot([port])
      assert process.pid > 0
      assert process.memory_bytes > 0
    end
  end
end
