defmodule LocalWebMonitorex.CaptureRuntime do
  @moduledoc "Locates bundled screenshot tools, falling back to source development tools."

  @spec paths(String.t(), String.t()) :: {String.t(), String.t()}
  def paths(
        priv_dir \\ Application.app_dir(:local_web_monitorex, "priv"),
        source_script \\ Path.expand("../../assets/capture.mjs", __DIR__)
      ) do
    node = Path.join(priv_dir, "node/bin/node")
    script = Path.join(priv_dir, "capture.mjs")

    {
      if(File.regular?(node), do: node, else: "node"),
      if(File.regular?(script), do: script, else: source_script)
    }
  end
end
