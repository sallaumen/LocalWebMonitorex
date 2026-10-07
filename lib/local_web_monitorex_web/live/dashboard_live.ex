defmodule LocalWebMonitorexWeb.DashboardLive do
  use LocalWebMonitorexWeb, :live_view

  alias LocalWebMonitorex.Monitor
  alias LocalWebMonitorex.Previews
  alias LocalWebMonitorex.Service
  alias LocalWebMonitorex.Settings

  @preview_interval 30_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Monitor.subscribe()
      Previews.subscribe()
      Process.send_after(self(), :refresh_previews, @preview_interval)
    end

    snapshot = Monitor.snapshot()

    {range_start, range_end} =
      range_bounds(Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4099))

    saved_range = Settings.read_range()

    if connected?(socket), do: request_previews(snapshot.services)

    {:ok,
     socket
     |> assign(:page_title, "LocalWebMonitorex · Overview")
     |> assign(:query, "")
     |> assign(:settings_open, false)
     |> assign(:selected_service, nil)
     |> assign(:saved_port, Settings.read_port())
     |> assign(:port_error, nil)
     |> assign(:port_saved, false)
     |> assign(:settings_file, Settings.path())
     |> assign(:range_file, Settings.range_path())
     |> assign(:saved_range_start, saved_range.first)
     |> assign(:saved_range_end, saved_range.last)
     |> assign(:range_error, nil)
     |> assign(:range_saved, false)
     |> assign(:dashboard_port, Application.get_env(:local_web_monitorex, :dashboard_port, 4100))
     |> assign(:range_start, range_start)
     |> assign(:range_end, range_end)
     |> assign(:previews, preview_versions(snapshot.services))
     |> assign_snapshot(snapshot)}
  end

  @impl true
  def handle_event("scan", _params, socket) do
    Monitor.refresh()
    {:noreply, assign(socket, :scanning, true)}
  end

  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, String.slice(query, 0, 80))}
  end

  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, true)}
  end

  def handle_event("close_settings", _params, socket) do
    {:noreply, assign(socket, :settings_open, false)}
  end

  def handle_event("open_preview", %{"port" => port}, socket) do
    case preview_service(socket, port) do
      nil -> {:noreply, socket}
      service -> {:noreply, assign(socket, :selected_service, service)}
    end
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :selected_service, nil)}
  end

  def handle_event("save_port", %{"port" => port}, socket) do
    case Settings.save_port(port) do
      :ok ->
        {:noreply,
         socket
         |> assign(:saved_port, Settings.read_port())
         |> assign(:port_error, nil)
         |> assign(:port_saved, true)}

      {:error, :invalid_port} ->
        {:noreply,
         socket
         |> assign(:port_error, "Choose a port between 1024 and 65535.")
         |> assign(:port_saved, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:port_error, "Could not save the setting.")
         |> assign(:port_saved, false)}
    end
  end

  def handle_event("save_range", %{"start" => first, "end" => last}, socket) do
    case Settings.save_range(first, last) do
      :ok ->
        saved_range = Settings.read_range()

        {:noreply,
         socket
         |> assign(:saved_range_start, saved_range.first)
         |> assign(:saved_range_end, saved_range.last)
         |> assign(:range_error, nil)
         |> assign(:range_saved, true)}

      {:error, :invalid_range} ->
        {:noreply,
         socket
         |> assign(:range_error, "Choose a valid range of up to 1,000 ports (1–65535).")
         |> assign(:range_saved, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:range_error, "Could not save the range.")
         |> assign(:range_saved, false)}
    end
  end

  @impl true
  def handle_info({:services_updated, snapshot}, socket) do
    request_previews(snapshot.services)

    {:noreply,
     socket
     |> assign_snapshot(snapshot)
     |> assign(
       :selected_service,
       current_selection(socket.assigns.selected_service, snapshot.services)
     )
     |> assign(:previews, Map.merge(socket.assigns.previews, preview_versions(snapshot.services)))}
  end

  def handle_info({:preview_ready, port, version}, socket) do
    {:noreply, update(socket, :previews, &Map.put(&1, port, version))}
  end

  def handle_info(:refresh_previews, socket) do
    request_previews(socket.assigns.services)
    Process.send_after(self(), :refresh_previews, @preview_interval)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-shell">
      <aside class="sidebar" aria-label="Main navigation">
        <a class="brand" href="/" aria-label="LocalWebMonitorex overview">
          <span class="brand-mark" aria-hidden="true"><span></span></span>
          <span class="brand-word">LocalWeb<span class="brand-sub">Monitorex<span class="brand-period">.</span></span></span>
        </a>

        <div class="sidebar-middle">
          <p class="rail-label">LOCAL DASHBOARD</p>
          <div class="rail-item active">
            <.icon name="hero-squares-2x2" class="icon" /> Overview
          </div>
          <button type="button" class="rail-item rail-button" phx-click="open_settings">
            <.icon name="hero-cog-6-tooth" class="icon" /> Settings
          </button>
          <div class="rail-divider"></div>
          <p class="rail-label">WATCHED PORTS</p>
          <div class="range-display">
            <span>{@range_start}</span><span class="range-line"></span><span>{@range_end}</span>
          </div>
          <p class="rail-caption">127.0.0.1 · dashboard excluded</p>
        </div>

        <div class="quick-link" aria-label="Dashboard address">
          <span class="quick-link-head"><.icon name="hero-command-line" class="icon" />
          DASHBOARD ADDRESS</span>
          <strong>localhost:{@dashboard_port}</strong>
          <span class="quick-link-foot">Running here <span class="quick-link-live">● LIVE</span></span>
        </div>
        <p class="rail-footer">LOCALWEBMONITOREX · OPEN SOURCE</p>
      </aside>

      <main class="workspace">
        <div class="mobile-brand">
          <span class="brand-mark" aria-hidden="true"><span></span></span><strong>LocalWebMonitorex<span class="brand-period">.</span></strong><button
            type="button"
            phx-click="open_settings"
            aria-label="Settings"
          ><.icon name="hero-cog-6-tooth" class="icon" /></button>
        </div>
        <header class="page-head">
          <div>
            <div class="eyebrow"><span class="eyebrow-line"></span> YOUR MACHINE, IN VIEW</div>
            <h1>Overview</h1>
            <p>Web services currently running on this machine.</p>
          </div>
          <div class="head-actions">
            <div class="scan-status" aria-live="polite">
              <span class={if @scanning, do: "pulse-dot scanning", else: "pulse-dot"}></span>
              <span>{if @scanning, do: "Scanning ports", else: "Watching"}</span>
            </div>
            <button type="button" class="refresh-button" phx-click="scan" disabled={@scanning}>
              <.icon name="hero-arrow-path" class="icon" /> Refresh
            </button>
            <button
              type="button"
              class="settings-shortcut"
              phx-click="open_settings"
              aria-label="Settings"
            ><.icon name="hero-cog-6-tooth" class="icon" /></button>
          </div>
          <div class="mobile-quick-link">
            <.icon name="hero-command-line" class="icon" /> Dashboard at localhost:{@dashboard_port}
          </div>
        </header>

        <section class="overview" aria-label="Summary">
          <div class="overview-count">
            <span class="overview-number">{length(@services)}</span>
            <span class="overview-copy"><strong>Active ports</strong><small>in range {@range_start}–{@range_end}</small></span>
          </div>
          <div class="overview-side">
            <div class="overview-rule"></div>
            <span class="overview-icon"><.icon name="hero-signal" class="icon" /></span>
            <div>
              <strong>Automatic scan</strong><small>Rescans after 5s · previews at least 30s apart</small>
            </div>
          </div>
          <span class="overview-corner" aria-hidden="true">F / 01</span>
        </section>

        <section class="services-section" aria-labelledby="services-title">
          <div class="section-head">
            <div>
              <p class="section-index">01 / DISCOVERED PORTS</p>
              <h2 id="services-title">
                {if @query == "", do: "Live now", else: "Matches"}
                <span>{length(filtered_services(@services, @query))}</span>
              </h2>
            </div>
            <form id="service-filter" phx-change="filter" role="search" class="search-form">
              <.icon name="hero-magnifying-glass" class="icon" />
              <input
                type="search"
                name="query"
                value={@query}
                placeholder="Filter by port or name"
                aria-label="Filter by port or name"
                autocomplete="off"
              />
              <span class="search-shortcut" aria-hidden="true">⌕</span>
            </form>
          </div>

          <div :if={@services == []} class="empty-state">
            <div class="empty-graphic" aria-hidden="true">
              <span class="empty-ring"></span><span class="empty-cross">+</span>
            </div>
            <p class="empty-kicker">NO SIGNAL YET</p>
            <h3>No web apps found.</h3>
            <p>
              A web server on ports {@range_start}–{@range_end} will appear here automatically.
            </p>
            <button type="button" phx-click="scan" disabled={@scanning}><.icon
              name="hero-arrow-path"
              class="icon"
            /> Scan now</button>
          </div>

          <div
            :if={@services != [] and filtered_services(@services, @query) == []}
            class="filter-empty"
          >
            No ports match “{@query}”.
          </div>

          <div :if={@services != []} class="service-grid">
            <article :for={service <- filtered_services(@services, @query)} class="service-card">
              <button
                type="button"
                class="camera"
                phx-click="open_preview"
                phx-value-port={service.port}
                disabled={is_nil(@previews[service.port])}
                aria-label={"Inspect preview of #{Service.url(service)}"}
              >
                <span class="camera-toolbar">
                  <span><span class="camera-led"></span> PORT {service.port}</span>
                  <span>{if @previews[service.port], do: "EXPAND", else: "CAPTURING"}<.icon
                    name="hero-arrows-pointing-out"
                    class="icon"
                  /></span>
                </span>
                <span class="camera-screen">
                  <img
                    :if={@previews[service.port]}
                    src={~p"/previews/#{service.port}?v=#{@previews[service.port]}"}
                    alt=""
                    loading="lazy"
                  />
                  <span :if={is_nil(@previews[service.port])} class="camera-placeholder">
                    <span class="camera-cross">+</span><span class="camera-port">{service.port}</span><span class="camera-wait">CAPTURING PREVIEW</span>
                  </span>
                </span>
              </button>
              <div class="card-content">
                <div class="card-title-row">
                  <h3>{service.title || "Local app"}</h3><span class={status_class(service.status)}>{service.status}</span>
                </div>
                <div
                  :if={service.process}
                  class="process-metrics"
                  aria-label={"Process #{service.process.pid} metrics"}
                >
                  <div class="process-identity">
                    <small>PROCESS</small>
                    <strong title={service.process.name}>{service.process.name}</strong>
                    <span>PID {service.process.pid}</span>
                  </div>
                  <div class="process-metric">
                    <small>CPU</small><strong>{format_cpu(service.process.cpu_percent)}</strong>
                  </div>
                  <div class="process-metric">
                    <small>MEMORY</small><strong>{format_memory(service.process.memory_bytes)} MiB</strong>
                  </div>
                </div>
                <div :if={is_nil(service.process)} class="process-unavailable">
                  Process metrics unavailable
                </div>
                <div class="card-bottom">
                  <a href={Service.url(service)} target="_blank" rel="noopener noreferrer">{Service.url(
                    service
                  )} <.icon name="hero-arrow-up-right" class="icon" /></a><span>{service.response_ms} ms</span>
                </div>
              </div>
            </article>
          </div>
        </section>

        <footer class="page-footer">
          <span>LOCALWEBMONITOREX · LOCAL MONITOR</span><span>Only on this machine
          <span class="footer-separator">/</span>
          127.0.0.1</span>
        </footer>
      </main>
      <dialog
        :if={@selected_service}
        id="preview-dialog"
        class="preview-dialog"
        phx-hook="PreviewDialog"
        phx-update="ignore"
        data-preview-port={@selected_service.port}
        data-preview-src={
          ~p"/previews/#{@selected_service.port}?v=#{@previews[@selected_service.port]}"
        }
        aria-modal="true"
        aria-labelledby="preview-title"
      >
        <div class="preview-head">
          <div class="preview-heading">
            <span class="preview-kicker"><span class="camera-led"></span>
            PORT {@selected_service.port} · SNAPSHOT</span>
            <h2 id="preview-title">{@selected_service.title || "Local app"}</h2>
          </div>
          <div class="preview-actions">
            <a href={Service.url(@selected_service)} target="_blank" rel="noopener noreferrer">
              Open app <.icon name="hero-arrow-up-right" class="icon" />
            </a>
            <button
              type="button"
              data-preview-close
              phx-click="close_preview"
              aria-label="Close preview"
            >
              <.icon name="hero-x-mark" class="icon" />
            </button>
          </div>
        </div>
        <div class="preview-stage">
          <div class="preview-frame">
            <img
              src={~p"/previews/#{@selected_service.port}?v=#{@previews[@selected_service.port]}"}
              alt={"Full preview of #{Service.url(@selected_service)}"}
            />
          </div>
        </div>
        <div class="preview-foot">
          <span>{Service.url(@selected_service)}</span><span>Snapshot refreshes while the dashboard is open</span>
        </div>
      </dialog>
      <div :if={@settings_open} class="settings-scrim" phx-click="close_settings"></div>
      <section
        :if={@settings_open}
        class="settings-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby="settings-title"
        phx-window-keydown="close_settings"
        phx-key="Escape"
      >
        <div class="settings-head">
          <span>SETTINGS</span><button
            type="button"
            phx-click="close_settings"
            aria-label="Close settings"
          ><.icon name="hero-x-mark" class="icon" /></button>
        </div>
        <h2 id="settings-title">Dashboard settings</h2>
        <p>This dashboard is running at <strong>localhost:{@dashboard_port}</strong>.</p>
        <form id="port-settings" phx-submit="save_port">
          <label for="dashboard-port">Dashboard port · next start</label>
          <div class="settings-input-row">
            <span>localhost:</span><input
              id="dashboard-port"
              type="number"
              name="port"
              value={@saved_port}
              min="1024"
              max="65535"
              required
              autofocus
            /><button type="submit">Save</button>
          </div>
          <p :if={@port_error} class="settings-error" role="alert">{@port_error}</p>
          <p :if={@port_saved} class="settings-success" role="status">
            Saved. Restart LocalWebMonitorex to use the new port.
          </p>
        </form>
        <div class="settings-range">
          <h3>Watched range</h3>
          <p>
            Currently scanning {@range_start}–{@range_end}. Changes apply on next start. The dashboard port is always excluded.
          </p>
          <form id="range-settings" phx-submit="save_range">
            <div class="settings-range-fields">
              <div>
                <label for="range-start">From</label>
                <input
                  id="range-start"
                  type="number"
                  name="start"
                  value={@saved_range_start}
                  min="1"
                  max="65535"
                  required
                />
              </div>
              <span aria-hidden="true">—</span>
              <div>
                <label for="range-end">To</label>
                <input
                  id="range-end"
                  type="number"
                  name="end"
                  value={@saved_range_end}
                  min="1"
                  max="65535"
                  required
                />
              </div>
            </div>
            <button type="submit" class="settings-range-save">Save range</button>
            <p :if={@range_error} class="settings-error" role="alert">{@range_error}</p>
            <p :if={@range_saved} class="settings-success" role="status">
              Saved. Restart LocalWebMonitorex to use the new range.
            </p>
          </form>
        </div>
        <div class="settings-note">
          <.icon name="hero-document-text" class="icon" /><span>Local preferences<br /><code>{@settings_file}</code><br /><code>{@range_file}</code></span>
        </div>
      </section>
    </div>
    """
  end

  defp assign_snapshot(socket, snapshot) do
    socket
    |> assign(:services, snapshot.services)
    |> assign(:checked_at, snapshot.checked_at)
    |> assign(:scanning, snapshot.scanning)
  end

  defp request_previews(services), do: Enum.each(services, &Previews.request/1)

  defp preview_service(socket, raw_port) do
    with {port, ""} <- Integer.parse(raw_port),
         version when not is_nil(version) <- socket.assigns.previews[port] do
      Enum.find(socket.assigns.services, &(&1.port == port))
    else
      _ -> nil
    end
  end

  defp current_selection(nil, _services), do: nil

  defp current_selection(selected, services) do
    Enum.find(services, &(&1.port == selected.port))
  end

  defp preview_versions(services) do
    Map.new(services, fn service -> {service.port, Previews.version(service.port)} end)
  end

  defp filtered_services(services, ""), do: services

  defp filtered_services(services, query) do
    term = String.downcase(query)

    Enum.filter(services, fn service ->
      String.contains?(Integer.to_string(service.port), term) or
        String.contains?(String.downcase(service.title || ""), term)
    end)
  end

  defp status_class(status) when status < 400, do: "status-pill ok"
  defp status_class(_status), do: "status-pill warning"

  defp format_cpu(nil), do: "—"
  defp format_cpu(value), do: "#{format_decimal(value)}%"

  defp format_decimal(value), do: :erlang.float_to_binary(value, decimals: 1)

  defp format_memory(bytes) do
    value = Float.round(bytes / 1_048_576, 1)
    if value == trunc(value), do: Integer.to_string(trunc(value)), else: format_decimal(value)
  end

  defp range_bounds([]), do: {4000, 4099}
  defp range_bounds(ports), do: {Enum.min(ports), Enum.max(ports)}
end
