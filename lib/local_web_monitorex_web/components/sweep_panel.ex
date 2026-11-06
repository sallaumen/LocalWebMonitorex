defmodule LocalWebMonitorexWeb.SweepPanel do
  @moduledoc "Collapsible bottom-left panel for the slow sweep outside the watched range."

  use LocalWebMonitorexWeb, :html

  import LocalWebMonitorexWeb.ScanProgress, only: [format_count: 1]

  alias LocalWebMonitorex.Sweeper.Finding

  attr :sweep, :map, required: true, doc: "a `LocalWebMonitorex.Sweeper` snapshot"
  attr :open, :boolean, required: true
  attr :range, :string, required: true, doc: "the watched range, such as 4000–4500"
  attr :error, :string, default: nil

  def sweep_panel(assigns) do
    ~H"""
    <aside
      id="sweep-panel"
      class={["sweep-panel", "sweep-#{@sweep.phase}", @open && "open"]}
      aria-label="Ports outside the watched range"
      phx-window-keydown={@open && "close_sweep_panel"}
      phx-key="Escape"
    >
      <button
        type="button"
        class="sweep-summary"
        phx-click="toggle_sweep_panel"
        aria-expanded={to_string(@open)}
        aria-controls="sweep-body"
      >
        <span class="sweep-dot" aria-hidden="true"></span>
        <span class="sweep-summary-label">Other ports</span>
        <span :if={@sweep.findings != []} class="badge sweep-count">{length(@sweep.findings)}</span>
        <span class="sweep-summary-state">{short_state(@sweep)}</span>
        <.icon name={if @open, do: "hero-chevron-down", else: "hero-chevron-up"} class="icon" />
      </button>
      <div :if={@open} id="sweep-body" class="sweep-body">
        <p class="sweep-status">{status(@sweep, @range)}</p>
        <progress
          :if={@sweep.phase == :sweeping}
          class="sweep-progress"
          aria-label="Wide sweep progress"
          max={max(@sweep.total, 1)}
          value={@sweep.checked}
        >
          {format_count(@sweep.checked)} of {format_count(@sweep.total)}
        </progress>
        <ul
          :if={@sweep.findings != []}
          class="sweep-list"
          aria-label="Open ports outside the watched range"
        >
          <li :for={finding <- @sweep.findings}>
            <span class="sweep-port">{finding.port}</span>
            <span class="sweep-name" title={label(finding)}>{label(finding)}</span>
            <span class={["badge", kind_class(finding)]}>{kind(finding)}</span>
            <a
              :if={Finding.url(finding)}
              href={Finding.url(finding)}
              target="_blank"
              rel="noopener noreferrer"
              aria-label={"Open #{Finding.url(finding)}"}
            ><.icon name="hero-arrow-up-right" class="icon" /></a>
            <button
              type="button"
              phx-click="watch_port"
              phx-value-port={finding.port}
              aria-label={"Add port #{finding.port} to the watched range"}
            ><.icon name="hero-plus" class="icon" /></button>
          </li>
        </ul>
        <p :if={@sweep.findings == [] and @sweep.enabled} class="sweep-empty">
          {empty_text(@sweep, @range)}
        </p>
        <p :if={@error} class="sweep-error" role="alert">{@error}</p>
        <div class="sweep-footer">
          <span>127.0.0.1 only · hourly</span>
          <button
            type="button"
            role="switch"
            class="sweep-switch"
            aria-checked={to_string(@sweep.enabled)}
            phx-click="set_sweep"
            phx-value-enabled={to_string(not @sweep.enabled)}
          >
            <span class="sweep-switch-track" aria-hidden="true"><span></span></span> Wide sweep
          </button>
        </div>
      </div>
    </aside>
    """
  end

  defp short_state(%{phase: :off}), do: "Sweep off"
  defp short_state(%{phase: :sweeping} = sweep), do: "Sweeping · #{percent(sweep)}%"
  defp short_state(%{next_pass_at: %DateTime{} = at}), do: "Next pass #{clock(at)}"
  defp short_state(_sweep), do: "Waiting"

  defp status(%{phase: :off}, range),
    do: "Wide sweep is off. Only ports #{range} are checked."

  defp status(%{phase: :sweeping} = sweep, _range),
    do: "Sweeping slowly · #{format_count(sweep.checked)} of #{format_count(sweep.total)} ports"

  defp status(%{last_pass_at: nil, next_pass_at: %DateTime{} = at}, _range),
    do: "First pass starts at #{clock(at)}."

  defp status(%{last_pass_at: %DateTime{} = last, next_pass_at: %DateTime{} = next}, _range),
    do: "Last pass finished at #{clock(last)}. Next pass at #{clock(next)}."

  defp status(_sweep, _range), do: "Waiting for the next pass."

  defp empty_text(%{last_pass_at: nil}, _range),
    do: "Nothing found outside the watched range yet."

  defp empty_text(_sweep, range), do: "No other listeners outside #{range}."

  defp percent(%{total: 0}), do: 100
  defp percent(%{checked: checked, total: total}), do: div(checked * 100, total)

  defp label(%Finding{process_name: name}) when is_binary(name), do: name
  defp label(%Finding{title: title}) when is_binary(title), do: title
  defp label(%Finding{}), do: "Unknown process"

  defp kind(%Finding{http: true, status: status}), do: "HTTP #{status}"
  defp kind(%Finding{}), do: "TCP"

  defp kind_class(%Finding{http: true, status: status}) when status >= 400, do: "badge-warn"
  defp kind_class(%Finding{http: true}), do: "badge-ok"
  defp kind_class(%Finding{}), do: "badge-muted"

  defp clock(datetime) do
    {_date, {hour, minute, _second}} =
      datetime
      |> DateTime.to_unix()
      |> :calendar.system_time_to_local_time(:second)

    :io_lib.format("~2..0B:~2..0B", [hour, minute])
    |> IO.iodata_to_binary()
  end
end
