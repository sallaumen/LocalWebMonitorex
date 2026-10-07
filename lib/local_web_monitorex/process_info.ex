defmodule LocalWebMonitorex.ProcessInfo do
  @moduledoc "A snapshot of one process listening on a discovered web port."

  @enforce_keys [:pid, :name, :cpu_percent, :memory_bytes]
  defstruct [:pid, :name, :cpu_percent, :memory_bytes]

  @type t :: %__MODULE__{
          pid: pos_integer(),
          name: String.t(),
          cpu_percent: float() | nil,
          memory_bytes: non_neg_integer()
        }
end
