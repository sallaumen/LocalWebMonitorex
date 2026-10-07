defmodule LocalWebMonitorex.CaptureRuntimeTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.CaptureRuntime

  test "uses bundled Node and capture script in a release" do
    root = Path.join(System.tmp_dir!(), "capture-runtime-#{System.unique_integer([:positive])}")
    node = Path.join(root, "node/bin/node")
    script = Path.join(root, "capture.mjs")
    File.mkdir_p!(Path.dirname(node))
    File.write!(node, "")
    File.write!(script, "")
    on_exit(fn -> File.rm_rf!(root) end)

    assert CaptureRuntime.paths(root, "/source/capture.mjs") == {node, script}
  end

  test "uses source script and system Node during development" do
    assert CaptureRuntime.paths("/missing/priv", "/source/capture.mjs") ==
             {"node", "/source/capture.mjs"}
  end
end
