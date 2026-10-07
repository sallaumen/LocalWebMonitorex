defmodule LocalWebMonitorex.ProcessControl do
  @moduledoc "The operating-system boundary for ending a local process."

  @callback terminate(pos_integer()) :: :ok | {:error, atom()}
end
