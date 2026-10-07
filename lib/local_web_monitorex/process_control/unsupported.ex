defmodule LocalWebMonitorex.ProcessControl.Unsupported do
  @moduledoc "Reports that process termination is unavailable on this operating system."

  @behaviour LocalWebMonitorex.ProcessControl

  @impl true
  def terminate(_pid), do: {:error, :unsupported_os}
end
