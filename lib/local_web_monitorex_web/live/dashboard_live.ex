defmodule LocalWebMonitorexWeb.DashboardLive do
  use LocalWebMonitorexWeb, :live_view

  import LocalWebMonitorexWeb.DashboardComponents
  import LocalWebMonitorexWeb.StopDialog

  alias LocalWebMonitorex.Monitor
  alias LocalWebMonitorex.Previews
  alias LocalWebMonitorex.ProcessTerminator
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
      range_bounds(Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4500))

    saved_range = Settings.read_range()

    if connected?(socket), do: request_previews(snapshot.services)

    {:ok,
     socket
     |> assign(:page_title, "LocalWebMonitorex · Overview")
     |> assign(:query, "")
     |> assign(:settings_open, false)
     |> assign(:selected_service, nil)
     |> assign(:stop_target, nil)
     |> assign(:stop_task, nil)
     |> assign(:notice, nil)
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
     |> assign(:preview_failures, preview_failures(snapshot.services))
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

  def handle_event("confirm_stop", %{"port" => raw_port}, socket) do
    target = find_service(socket.assigns.services, raw_port)

    if target && target.process do
      {:noreply, assign(socket, :stop_target, target)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_stop", _params, %{assigns: %{stop_task: nil}} = socket) do
    {:noreply, assign(socket, :stop_target, nil)}
  end

  def handle_event("cancel_stop", _params, socket), do: {:noreply, socket}

  def handle_event("clear_notice", _params, socket), do: {:noreply, assign(socket, :notice, nil)}

  def handle_event("stop_process", _params, %{assigns: %{stop_target: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("stop_process", _params, %{assigns: %{stop_task: task}} = socket)
      when not is_nil(task), do: {:noreply, socket}

  def handle_event("stop_process", _params, socket) do
    target = socket.assigns.stop_target
    terminator = Application.get_env(:local_web_monitorex, :process_terminator, ProcessTerminator)

    task =
      Task.Supervisor.async_nolink(LocalWebMonitorex.TaskSupervisor, fn ->
        terminator.stop(target)
      end)

    {:noreply, assign(socket, :stop_task, task.ref)}
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

  def handle_info({ref, result}, %{assigns: %{stop_task: ref}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_stop(socket, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{stop_task: ref}} = socket) do
    {:noreply, finish_stop(socket, {:error, :command_failed})}
  end

  def handle_info({:preview_ready, port, version}, socket) do
    {:noreply,
     socket
     |> update(:previews, &Map.put(&1, port, version))
     |> update(:preview_failures, &MapSet.delete(&1, port))}
  end

  def handle_info({:preview_failed, port}, socket) do
    {:noreply, update(socket, :preview_failures, &MapSet.put(&1, port))}
  end

  def handle_info(:refresh_previews, socket) do
    request_previews(socket.assigns.services)
    Process.send_after(self(), :refresh_previews, @preview_interval)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="theme-preferences" class="app-shell" phx-hook="ThemePreferences">
      <aside class="sidebar" aria-label="Main navigation">
        <a class="brand" href="/" aria-label="LocalWebMonitorex overview">
          <span class="brand-mark" aria-hidden="true"><span></span></span>
          <span class="brand-word">LocalWebMonitorex</span>
        </a>

        <nav class="rail-nav">
          <a class="rail-item active" href="/" aria-current="page">
            <.icon name="hero-squares-2x2" class="icon" /> Overview
          </a>
          <button type="button" class="rail-item rail-button" phx-click="open_settings">
            <.icon name="hero-cog-6-tooth" class="icon" /> Settings
          </button>
        </nav>

        <section class="rail-section" aria-labelledby="rail-watching">
          <p id="rail-watching" class="rail-label">Watching now</p>
          <p class="rail-range">{@range_start}–{@range_end}</p>
          <ul class="rail-facts">
            <li>{range_caption(@range_start, @range_end, @dashboard_port)}</li>
            <li>Loopback only · <strong>127.0.0.1</strong></li>
          </ul>
          <p :if={range_pending?(assigns)} class="rail-pending">
            Saved <strong>{@saved_range_start}–{@saved_range_end}</strong>. Applies on next start.
          </p>
        </section>

        <div class="rail-address">
          <p class="rail-label">This dashboard</p>
          <strong>localhost:{@dashboard_port}</strong>
          <p>Reachable only from this machine.</p>
        </div>
      </aside>

      <main class="workspace">
        <div class="mobile-bar">
          <a class="brand" href="/" aria-label="LocalWebMonitorex overview">
            <span class="brand-mark" aria-hidden="true"><span></span></span>
            <span class="brand-word">LocalWebMonitorex</span>
          </a>
          <button type="button" phx-click="open_settings" aria-label="Settings">
            <.icon name="hero-cog-6-tooth" class="icon" />
          </button>
        </div>

        <div :if={@notice} class={["app-notice", @notice.kind]} role={notice_role(@notice.kind)}>
          <.icon name={notice_icon(@notice.kind)} class="icon" />
          <span>{@notice.text}</span>
          <button type="button" phx-click="clear_notice" aria-label="Dismiss message">
            <.icon name="hero-x-mark" class="icon" />
          </button>
        </div>

        <header class="page-head">
          <div>
            <h1>Running services <span class="count">{length(@services)}</span></h1>
            <p>
              HTTP and HTTPS servers on 127.0.0.1 in range {@range_start}–{@range_end}. Updates live.
            </p>
          </div>
          <div class="head-actions">
            <button type="button" class="btn refresh" phx-click="scan" disabled={@scanning}>
              <.icon name="hero-arrow-path" class="icon" />
              {if @scanning, do: "Scanning…", else: "Scan now"}
            </button>
            <button
              type="button"
              class="btn btn-icon settings-shortcut"
              phx-click="open_settings"
              aria-label="Settings"
            ><.icon name="hero-cog-6-tooth" class="icon" /></button>
          </div>
        </header>

        <.scan_strip
          scanning={@scanning}
          checked_at={@checked_at}
          found={length(@services)}
          range_start={@range_start}
          range_end={@range_end}
          dashboard_port={@dashboard_port}
        />

        <section class="services-section" aria-labelledby="services-title">
          <div class="toolbar">
            <h2 id="services-title">
              {if @query == "", do: "All services", else: "Matches"}
              <span>{length(filtered_services(@services, @query))}</span>
            </h2>
            <div class="toolbar-right">
              <form id="service-filter" phx-change="filter" role="search" class="search-form">
                <.icon name="hero-magnifying-glass" class="icon" />
                <input
                  type="search"
                  name="query"
                  value={@query}
                  placeholder="Filter by port or title"
                  aria-label="Filter by port or title"
                  autocomplete="off"
                />
              </form>
            </div>
          </div>

          <.discovery_notes
            range_start={@range_start}
            range_end={@range_end}
            dashboard_port={@dashboard_port}
          />

          <div :if={@services == [] and is_nil(@checked_at)} class="empty-state" role="status">
            <.icon name="hero-arrow-path" class="icon" />
            <h3>Scanning ports {@range_start}–{@range_end}…</h3>
            <p>
              The first scan usually takes a few seconds. Servers appear here as soon as it finishes.
            </p>
          </div>

          <div :if={@services == [] and not is_nil(@checked_at)} class="empty-state">
            <.icon name="hero-signal-slash" class="icon" />
            <h3>No web servers found on ports {@range_start}–{@range_end}</h3>
            <p>
              Start a dev server in this range and it appears within a few seconds. To watch other ports, change the range in Settings.
            </p>
            <button type="button" class="btn" phx-click="scan" disabled={@scanning}>
              <.icon name="hero-arrow-path" class="icon" /> Scan now
            </button>
          </div>

          <div
            :if={@services != [] and filtered_services(@services, @query) == []}
            class="filter-empty"
          >
            No services match “{@query}”.
          </div>

          <div :if={@services != []} class="service-grid">
            <.service_card
              :for={service <- filtered_services(@services, @query)}
              service={service}
              preview={@previews[service.port]}
              preview_failed={MapSet.member?(@preview_failures, service.port)}
            />
          </div>
        </section>

        <footer class="page-footer">
          <span>Served on the loopback interface only. Other devices cannot open this page.</span>
          <span class="mono">127.0.0.1:{@dashboard_port}</span>
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
            <p class="preview-kicker">
              Port {@selected_service.port} · snapshot {format_clock(
                @previews[@selected_service.port]
              )}
            </p>
            <h2 id="preview-title">{@selected_service.title || "No page title"}</h2>
          </div>
          <div class="preview-actions">
            <a
              class="btn btn-primary"
              href={Service.url(@selected_service)}
              target="_blank"
              rel="noopener noreferrer"
              aria-label="Open app in a new tab"
            >
              <span class="open-label">Open app</span>
              <.icon name="hero-arrow-up-right" class="icon" />
            </a>
            <button
              type="button"
              class="btn btn-icon"
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
          <code>{Service.url(@selected_service)}</code>
          <span>Captured at 1280×720 without remote assets. Refreshes about every 30 s.</span>
        </div>
      </dialog>
      <.stop_dialog :if={@stop_target} target={@stop_target} stopping={not is_nil(@stop_task)} />
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
          <h2 id="settings-title">Settings</h2>
          <button
            type="button"
            class="btn btn-icon"
            phx-click="close_settings"
            aria-label="Close settings"
          ><.icon name="hero-x-mark" class="icon" /></button>
        </div>
        <p class="settings-intro">
          Appearance applies right away. Port and range changes are saved for the next start.
        </p>

        <div class="settings-section settings-theme">
          <h3>Appearance</h3>
          <p>Follow the system theme, or keep a choice in this browser.</p>
          <div class="theme-options" role="group" aria-label="Appearance">
            <button type="button" data-theme-choice="auto" aria-pressed="false">
              <.icon name="hero-computer-desktop" class="icon" /> System
            </button>
            <button type="button" data-theme-choice="light" aria-pressed="false">
              <.icon name="hero-sun" class="icon" /> Light
            </button>
            <button type="button" data-theme-choice="dark" aria-pressed="false">
              <.icon name="hero-moon" class="icon" /> Dark
            </button>
          </div>
          <p class="settings-warning" data-theme-storage-warning hidden role="status">
            Browser storage is unavailable. This choice will reset when you close the page.
          </p>
        </div>

        <div class="settings-section">
          <h3>Dashboard port</h3>
          <dl class="settings-facts">
            <dt>Running now</dt>
            <dd>localhost:{@dashboard_port}</dd>
            <dt>Next start</dt>
            <dd>
              localhost:{@saved_port}
              <span :if={@saved_port != @dashboard_port} class="badge badge-warn">
                Applies on next start
              </span>
            </dd>
          </dl>
          <p :if={@saved_port != @dashboard_port}>
            A <code>PORT</code> environment variable overrides the saved port.
          </p>
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
        </div>

        <div class="settings-section settings-range">
          <h3>Watched range</h3>
          <dl class="settings-facts">
            <dt>Scanning now</dt>
            <dd>{@range_start}–{@range_end}</dd>
            <dt>Next start</dt>
            <dd>
              {@saved_range_start}–{@saved_range_end}
              <span :if={range_pending?(assigns)} class="badge badge-warn">
                Applies on next start
              </span>
            </dd>
          </dl>
          <p>The dashboard port is always excluded from the scan.</p>
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
          <.icon name="hero-document-text" class="icon" /><span>Saved in local files<br /><code>{@settings_file}</code><br /><code>{@range_file}</code></span>
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
    with %Service{} = service <- find_service(socket.assigns.services, raw_port),
         version when not is_nil(version) <- socket.assigns.previews[service.port] do
      service
    else
      _ -> nil
    end
  end

  defp find_service(services, raw_port) do
    with {port, ""} <- Integer.parse(raw_port) do
      Enum.find(services, &(&1.port == port))
    else
      _ -> nil
    end
  end

  defp current_selection(nil, _services), do: nil

  defp current_selection(selected, services) do
    Enum.find(services, &(&1.port == selected.port))
  end

  defp finish_stop(socket, :ok) do
    target = socket.assigns.stop_target
    Monitor.refresh()

    socket
    |> assign(:stop_task, nil)
    |> assign(:stop_target, nil)
    |> assign(:notice, %{kind: :info, text: "Stop request sent to PID #{target.process.pid}."})
  end

  defp finish_stop(socket, {:error, :stale_process}) do
    socket
    |> assign(:stop_task, nil)
    |> assign(:stop_target, nil)
    |> assign(:notice, %{kind: :error, text: "The listener changed. Refresh and try again."})
  end

  defp finish_stop(socket, {:error, reason}) do
    socket
    |> assign(:stop_task, nil)
    |> assign(:stop_target, nil)
    |> assign(:notice, %{kind: :error, text: stop_error(reason)})
  end

  defp notice_role(:error), do: "alert"
  defp notice_role(:info), do: "status"
  defp notice_icon(:error), do: "hero-exclamation-triangle"
  defp notice_icon(:info), do: "hero-check-circle"

  defp stop_error(:protected_process), do: "LocalWebMonitorex cannot stop its own process."
  defp stop_error(:unsupported_os), do: "Stopping processes is unavailable on this system."
  defp stop_error(:timeout), do: "The operating system did not respond. Try again."
  defp stop_error(_reason), do: "Could not stop this process. Check permissions and try again."

  defp preview_failures(services) do
    services
    |> Enum.filter(&Previews.failed?(&1.port))
    |> MapSet.new(& &1.port)
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

  defp range_pending?(assigns) do
    {assigns.saved_range_start, assigns.saved_range_end} !=
      {assigns.range_start, assigns.range_end}
  end

  defp range_bounds([]), do: {4000, 4500}
  defp range_bounds(ports), do: {Enum.min(ports), Enum.max(ports)}
end
