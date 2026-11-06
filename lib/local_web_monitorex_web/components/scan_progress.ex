defmodule LocalWebMonitorexWeb.ScanProgress do
  @moduledoc "Shows how many watched ports the current or latest scan has checked."

  use LocalWebMonitorexWeb, :html

  attr :progress, :map, required: true, doc: "a map with :checked, :total and :scanning"

  def scan_progress(assigns) do
    assigns =
      assigns
      |> assign(:checked, format_count(assigns.progress.checked))
      |> assign(:total, format_count(assigns.progress.total))

    ~H"""
    <div class={["scan-progress", @progress.scanning && "scanning"]}>
      <span id="scan-progress-label" class="scan-progress-label">
        {if @progress.scanning, do: "Current scan", else: "Last scan"}
      </span>
      <strong class="scan-progress-count">Scanned {@checked} / {@total}</strong>
      <progress
        class="scan-progress-bar"
        aria-labelledby="scan-progress-label"
        aria-valuetext={"#{@checked} of #{@total} ports scanned"}
        max={max(@progress.total, 1)}
        value={@progress.checked}
      >
        {@checked} of {@total}
      </progress>
    </div>
    """
  end

  @doc "Formats a count with comma thousands separators, such as `61,535`."
  @spec format_count(non_neg_integer()) :: String.t()
  def format_count(count) when is_integer(count) and count >= 0 do
    count
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
