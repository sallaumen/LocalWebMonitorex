defmodule LocalWebMonitorex.ProcessInspector.LsofTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.ProcessInspector.Lsof

  test "maps listening ports to their processes with CPU and resident memory" do
    runner = fn
      "lsof", _args ->
        {"p42\ncbeam.smp\nf8\nn127.0.0.1:4005\nf9\nn127.0.0.1:4999\np72\ncnode\nf10\nn*:4006\n",
         0}

      "ps", ["-p", "42,72" | _args] ->
        {" 42  12.5  204800 /usr/local/bin/beam.smp\n 72   0.4   51200 node\n", 0}
    end

    processes = Lsof.snapshot([4005, 4006], runner)

    assert processes[4005].pid == 42
    assert processes[4005].name == "beam.smp"
    assert processes[4005].cpu_percent == 12.5
    assert processes[4005].memory_bytes == 209_715_200
    assert processes[4006].pid == 72
    assert processes[4006].memory_bytes == 52_428_800
    refute Map.has_key?(processes, 4999)
  end

  test "returns no metrics when process tools are unavailable" do
    runner = fn _command, _args -> raise ErlangError, original: :enoent end

    assert Lsof.snapshot([4005], runner) == %{}
    assert Lsof.snapshot([], runner) == %{}
  end
end
