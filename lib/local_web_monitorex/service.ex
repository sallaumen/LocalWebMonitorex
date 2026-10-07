defmodule LocalWebMonitorex.Service do
  @moduledoc "A web service discovered on a local port."

  @enforce_keys [:port, :scheme, :status]
  defstruct [:port, :scheme, :status, :title, :content_type, :response_ms]

  @type t :: %__MODULE__{
          port: pos_integer(),
          scheme: String.t(),
          status: pos_integer(),
          title: String.t() | nil,
          content_type: String.t() | nil,
          response_ms: non_neg_integer() | nil
        }

  @spec url(t()) :: String.t()
  def url(%__MODULE__{port: port, scheme: scheme}), do: "#{scheme}://localhost:#{port}"
end
