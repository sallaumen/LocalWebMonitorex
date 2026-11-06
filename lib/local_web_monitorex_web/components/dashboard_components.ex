defmodule LocalWebMonitorexWeb.DashboardComponents do
  @moduledoc "Overview building blocks: scan status, discovery notes and service cards."

  use LocalWebMonitorexWeb, :html

  alias LocalWebMonitorex.Service

  attr :scanning, :boolean, required: true
  attr :checked_at, :any, required: true
  attr :found, :integer, required: true
  attr :range_start, :integer, required: true
  attr :range_end, :integer, required: true
  attr :dashboard_port, :integer, required: true
  slot :inner_block, doc: "scan progress shown under the scanner state"

  def scan_strip(assigns) do
    ~H"""
    <dl class="scan-strip" aria-label="Scan status">
      <div class="scan-cell">
        <dt>Scanner</dt>
        <dd aria-live="polite">
          <span class="scan-state">
            <span class={["scan-dot", @scanning && "scanning"]} aria-hidden="true"></span>
            {if @scanning, do: "Scanning ports…", else: "Watching"}
          </span>
          {render_slot(@inner_block)}
          <small>Rescans 5 s after each scan finishes</small>
        </dd>
      </div>
      <div class="scan-cell">
        <dt>Last scan</dt>
        <dd>
          {if @checked_at, do: format_clock(@checked_at), else: "Not finished yet"}
          <small>{found_label(@checked_at, @found)}</small>
        </dd>
      </div>
      <div class="scan-cell">
        <dt>Watched ports</dt>
        <dd>
          <span class="mono">{@range_start}–{@range_end}</span>
          <small>{range_caption(@range_start, @range_end, @dashboard_port)}</small>
        </dd>
      </div>
      <div class="scan-cell">
        <dt>Snapshots</dt>
        <dd>
          At most every 30 s <small>Headless WebKit, one page at a time</small>
        </dd>
      </div>
    </dl>
    """
  end

  attr :range_start, :integer, required: true
  attr :range_end, :integer, required: true
  attr :dashboard_port, :integer, required: true

  def discovery_notes(assigns) do
    ~H"""
    <details class="notes" id="discovery-notes">
      <summary>
        <.icon name="hero-information-circle" class="icon" />
        How discovery works and what it cannot see
        <.icon name="hero-chevron-down" class="icon chevron" />
      </summary>
      <dl class="notes-list">
        <div>
          <dt><.icon name="hero-signal" class="icon" /> What appears</dt>
          <dd>
            Ports {@range_start}–{@range_end} that answer an HTTP or HTTPS request on 127.0.0.1 within about 1.5 s. Databases, raw sockets and other protocols are not listed.
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-eye-slash" class="icon" /> Never listed</dt>
          <dd>
            This dashboard's own port (<code>:{@dashboard_port}</code>) and anything outside the watched range. Redirects are reported, not followed.
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-photo" class="icon" /> Snapshots</dt>
          <dd>
            A headless browser loads each page locally and blocks remote assets. Pages that do not load within a few seconds show “Snapshot unavailable”. Signed-in views may look different.
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-cpu-chip" class="icon" /> Process details</dt>
          <dd>
            PID, CPU and memory come from the operating system (<code>lsof</code>
            and <code>ps</code>, or PowerShell on Windows). They can be missing for other users' processes, containers and VMs.
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-stop-circle" class="icon" /> Stopping</dt>
          <dd>
            After confirmation, Stop asks the OS to end that PID (SIGTERM, or <code>taskkill</code>
            on Windows). Other ports served by the same process stop too.
          </dd>
        </div>
        <div>
          <dt><.icon name="hero-arrow-path-rounded-square" class="icon" /> Settings</dt>
          <dd>
            The dashboard port and watched range are saved to local files and take effect the next time LocalWebMonitorex starts.
          </dd>
        </div>
      </dl>
    </details>
    """
  end

  attr :service, Service, required: true
  attr :preview, :any, required: true
  attr :preview_failed, :boolean, required: true

  def service_card(assigns) do
    ~H"""
    <article class="service-card">
      <button
        type="button"
        class="thumb"
        phx-click="open_preview"
        phx-value-port={@service.port}
        disabled={is_nil(@preview)}
        aria-label={"Inspect preview of #{Service.url(@service)}"}
      >
        <img
          :if={@preview}
          src={~p"/previews/#{@service.port}?v=#{@preview}"}
          alt=""
          loading="lazy"
        />
        <.thumb_state preview={@preview} failed={@preview_failed} />
      </button>
      <div class="card-body">
        <div class="card-title">
          <h3 class={is_nil(@service.title) && "untitled"} title={@service.title}>
            {@service.title || "No page title"}
          </h3>
          <span class="port-tag">:{@service.port}</span>
        </div>
        <div class="card-meta">
          <span class={["badge", status_tone(@service.status)]} title="HTTP status of the root page">
            {status_text(@service.status)}
          </span>
          <span :if={@service.response_ms} title="Time to answer the last probe">
            answered in {@service.response_ms} ms
          </span>
        </div>
        <.process_details service={@service} />
        <div class="card-foot">
          <a href={Service.url(@service)} target="_blank" rel="noopener noreferrer">
            {Service.url(@service)} <.icon name="hero-arrow-up-right" class="icon" />
          </a>
          <button
            :if={@service.process}
            type="button"
            class="btn btn-danger-quiet"
            phx-click="confirm_stop"
            phx-value-port={@service.port}
            aria-label={"Stop process #{@service.process.name}, PID #{@service.process.pid}, on port #{@service.port}"}
          >
            <.icon name="hero-stop-circle" class="icon" /> Stop
          </button>
        </div>
      </div>
    </article>
    """
  end

  attr :preview, :any, required: true
  attr :failed, :boolean, required: true

  defp thumb_state(%{preview: nil, failed: true} = assigns) do
    ~H"""
    <span class="thumb-empty">
      <.icon name="hero-eye-slash" class="icon" />
      <strong>Snapshot unavailable</strong>
      <span>The page did not load in the headless browser. The app may still work.</span>
    </span>
    """
  end

  defp thumb_state(%{preview: nil} = assigns) do
    ~H"""
    <span class="thumb-empty capturing">
      <.icon name="hero-camera" class="icon" />
      <strong>Capturing snapshot…</strong>
      <span>Snapshots are taken one at a time.</span>
    </span>
    """
  end

  defp thumb_state(assigns) do
    ~H"""
    <span class="thumb-chip">
      <.icon name="hero-camera" class="icon" /> Snapshot {format_clock(@preview)}
    </span>
    <span class="thumb-expand" aria-hidden="true">
      <.icon name="hero-arrows-pointing-out" class="icon" />
    </span>
    """
  end

  attr :service, Service, required: true

  defp process_details(%{service: %{process: nil}} = assigns) do
    ~H"""
    <p class="process-missing">
      <.icon name="hero-question-mark-circle" class="icon" />
      <span>
        <strong>Process details unavailable.</strong>
        The OS did not report who owns this port, so it cannot be stopped from here.
      </span>
    </p>
    """
  end

  defp process_details(assigns) do
    ~H"""
    <dl class="process" aria-label={"Process #{@service.process.pid} metrics"}>
      <div>
        <dt>Process</dt>
        <dd title={@service.process.name}>
          {@service.process.name}<small>PID {@service.process.pid}</small>
        </dd>
      </div>
      <div>
        <dt>CPU</dt>
        <dd>{format_cpu(@service.process.cpu_percent)}</dd>
      </div>
      <div>
        <dt>Memory</dt>
        <dd>{format_memory(@service.process.memory_bytes)} MiB</dd>
      </div>
    </dl>
    """
  end

  @doc "Formats a UTC `DateTime` or a millisecond Unix timestamp as local wall-clock time."
  @spec format_clock(DateTime.t() | integer()) :: String.t()
  def format_clock(milliseconds) when is_integer(milliseconds) do
    milliseconds
    |> DateTime.from_unix!(:millisecond)
    |> format_clock()
  end

  def format_clock(%DateTime{} = moment) do
    {_date, {hour, minute, second}} =
      moment
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()
      |> :calendar.universal_time_to_local_time()

    IO.iodata_to_binary(:io_lib.format("~2..0B:~2..0B:~2..0B", [hour, minute, second]))
  end

  @doc "Describes the watched range size and whether the dashboard port is excluded from it."
  @spec range_caption(integer(), integer(), integer()) :: String.t()
  def range_caption(first, last, dashboard_port) when dashboard_port in first..last//1,
    do: "#{port_count(first, last)} · excludes :#{dashboard_port} (this dashboard)"

  def range_caption(first, last, _dashboard_port), do: port_count(first, last)

  defp port_count(first, last), do: "#{last - first + 1} ports"

  defp found_label(nil, _found), do: "First scan in progress"
  defp found_label(_checked_at, 1), do: "1 server answered"
  defp found_label(_checked_at, found), do: "#{found} servers answered"

  defp status_text(status) do
    "#{status} #{Plug.Conn.Status.reason_phrase(status)}"
  rescue
    ArgumentError -> "HTTP #{status}"
  end

  defp status_tone(status) when status < 300, do: "badge-ok"
  defp status_tone(status) when status < 400, do: "badge-info"
  defp status_tone(_status), do: "badge-warn"

  defp format_cpu(nil), do: "—"
  defp format_cpu(value), do: "#{format_decimal(value)}%"

  defp format_decimal(value), do: :erlang.float_to_binary(value, decimals: 1)

  defp format_memory(bytes) do
    value = Float.round(bytes / 1_048_576, 1)
    if value == trunc(value), do: Integer.to_string(trunc(value)), else: format_decimal(value)
  end
end
