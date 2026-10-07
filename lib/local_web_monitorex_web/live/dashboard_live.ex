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
      range_bounds(Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4100))

    if connected?(socket), do: request_previews(snapshot.services)

    {:ok,
     socket
     |> assign(:page_title, "LocalWebMonitorex · Visão geral")
     |> assign(:query, "")
     |> assign(:settings_open, false)
     |> assign(:saved_port, Settings.read_port())
     |> assign(:port_error, nil)
     |> assign(:port_saved, false)
     |> assign(:settings_file, Settings.path())
     |> assign(:dashboard_port, Application.get_env(:local_web_monitorex, :dashboard_port, 4020))
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
         |> assign(:port_error, "Use uma porta entre 1024 e 65535.")
         |> assign(:port_saved, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:port_error, "Não foi possível salvar a configuração.")
         |> assign(:port_saved, false)}
    end
  end

  @impl true
  def handle_info({:services_updated, snapshot}, socket) do
    request_previews(snapshot.services)

    {:noreply,
     socket
     |> assign_snapshot(snapshot)
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
      <aside class="sidebar" aria-label="Navegação principal">
        <a class="brand" href="/" aria-label="LocalWebMonitorex, visão geral">
          <span class="brand-mark" aria-hidden="true"><span></span></span>
          <span class="brand-word">LocalWeb<span class="brand-sub">Monitorex<span class="brand-period">.</span></span></span>
        </a>

        <div class="sidebar-middle">
          <p class="rail-label">PAINEL LOCAL</p>
          <div class="rail-item active">
            <.icon name="hero-squares-2x2" class="icon" /> Visão geral
          </div>
          <button type="button" class="rail-item rail-button" phx-click="open_settings">
            <.icon name="hero-cog-6-tooth" class="icon" /> Configurações
          </button>
          <div class="rail-divider"></div>
          <p class="rail-label">FAIXA OBSERVADA</p>
          <div class="range-display">
            <span>{@range_start}</span><span class="range-line"></span><span>{@range_end}</span>
          </div>
          <p class="rail-caption">127.0.0.1 · painel excluído</p>
        </div>

        <a class="quick-link" href="http://localhost:4000" target="_blank" rel="noopener noreferrer">
          <span class="quick-link-head"><.icon name="hero-bolt" class="icon" /> ACESSO RÁPIDO</span>
          <strong>localhost:4000</strong>
          <span class="quick-link-foot">Abrir porta principal
          <.icon name="hero-arrow-up-right" class="icon" /></span>
        </a>
        <p class="rail-footer">LOCALWEBMONITOREX · 2026</p>
      </aside>

      <main class="workspace">
        <div class="mobile-brand">
          <span class="brand-mark" aria-hidden="true"><span></span></span><strong>LocalWebMonitorex<span class="brand-period">.</span></strong><button
            type="button"
            phx-click="open_settings"
            aria-label="Configurações"
          ><.icon name="hero-cog-6-tooth" class="icon" /></button>
        </div>
        <header class="page-head">
          <div>
            <div class="eyebrow"><span class="eyebrow-line"></span> SEU AMBIENTE, NUMA TELA</div>
            <h1>Visão geral</h1>
            <p>Os serviços web que estão rodando agora na sua máquina.</p>
          </div>
          <div class="head-actions">
            <div class="scan-status" aria-live="polite">
              <span class={if @scanning, do: "pulse-dot scanning", else: "pulse-dot"}></span>
              <span>{if @scanning, do: "Verificando portas", else: "Monitorando"}</span>
            </div>
            <button type="button" class="refresh-button" phx-click="scan" disabled={@scanning}>
              <.icon name="hero-arrow-path" class="icon" /> Atualizar
            </button>
            <button
              type="button"
              class="settings-shortcut"
              phx-click="open_settings"
              aria-label="Configurações"
            ><.icon name="hero-cog-6-tooth" class="icon" /></button>
          </div>
          <a
            class="mobile-quick-link"
            href="http://localhost:4000"
            target="_blank"
            rel="noopener noreferrer"
          ><.icon name="hero-bolt" class="icon" /> Abrir localhost:4000
          <.icon name="hero-arrow-up-right" class="icon" /></a>
        </header>

        <section class="overview" aria-label="Resumo">
          <div class="overview-count">
            <span class="overview-number">{length(@services)}</span>
            <span class="overview-copy"><strong>Portas ativas</strong><small>na faixa {@range_start}–{@range_end}</small></span>
          </div>
          <div class="overview-side">
            <div class="overview-rule"></div>
            <span class="overview-icon"><.icon name="hero-signal" class="icon" /></span>
            <div>
              <strong>Varredura automática</strong><small>A cada 5 segundos · prévias a cada 30 segundos</small>
            </div>
          </div>
          <span class="overview-corner" aria-hidden="true">F / 01</span>
        </section>

        <section class="services-section" aria-labelledby="services-title">
          <div class="section-head">
            <div>
              <p class="section-index">01 / PORTAS ENCONTRADAS</p>
              <h2 id="services-title">Em funcionamento <span>{length(@services)}</span></h2>
            </div>
            <form id="service-filter" phx-change="filter" role="search" class="search-form">
              <.icon name="hero-magnifying-glass" class="icon" />
              <input
                type="search"
                name="query"
                value={@query}
                placeholder="Filtrar porta ou nome"
                aria-label="Filtrar porta ou nome"
                autocomplete="off"
              />
              <span class="search-shortcut" aria-hidden="true">⌕</span>
            </form>
          </div>

          <div :if={@services == []} class="empty-state">
            <div class="empty-graphic" aria-hidden="true">
              <span class="empty-ring"></span><span class="empty-cross">+</span>
            </div>
            <p class="empty-kicker">SEM SINAL POR ENQUANTO</p>
            <h3>Nenhuma aplicação encontrada.</h3>
            <p>
              Assim que um servidor abrir entre as portas {@range_start} e {@range_end}, ele aparece aqui.
            </p>
            <button type="button" phx-click="scan" disabled={@scanning}><.icon
              name="hero-arrow-path"
              class="icon"
            /> Verificar agora</button>
          </div>

          <div
            :if={@services != [] and filtered_services(@services, @query) == []}
            class="filter-empty"
          >
            Nenhuma porta corresponde a “{@query}”.
          </div>

          <div :if={@services != []} class="service-grid">
            <article :for={service <- filtered_services(@services, @query)} class="service-card">
              <a
                class="camera"
                href={Service.url(service)}
                target="_blank"
                rel="noopener noreferrer"
                aria-label={"Abrir #{Service.url(service)}"}
              >
                <img
                  :if={@previews[service.port]}
                  src={~p"/previews/#{service.port}?v=#{@previews[service.port]}"}
                  alt={"Prévia de #{Service.url(service)}"}
                  loading="lazy"
                />
                <div :if={is_nil(@previews[service.port])} class="camera-placeholder">
                  <span class="camera-cross">+</span><span class="camera-port">{service.port}</span><span class="camera-wait">CAPTURANDO PRÉVIA</span>
                </div>
                <div class="camera-top">
                  <span><span class="camera-led"></span> PORTA {service.port}</span><span>CAPTURA</span>
                </div>
                <div class="camera-open"><.icon name="hero-arrow-up-right" class="icon" /></div>
              </a>
              <div class="card-content">
                <div class="card-title-row">
                  <h3>{service.title || "Aplicação local"}</h3><span class={
                    status_class(service.status)
                  }>{service.status}</span>
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
          <span>LOCALWEBMONITOREX · MONITOR LOCAL</span><span>Somente nesta máquina
          <span class="footer-separator">/</span>
          127.0.0.1</span>
        </footer>
      </main>
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
          <span>CONFIGURAÇÕES</span><button
            type="button"
            phx-click="close_settings"
            aria-label="Fechar configurações"
          ><.icon name="hero-x-mark" class="icon" /></button>
        </div>
        <h2 id="settings-title">Porta do painel</h2>
        <p>O painel está em <strong>localhost:{@dashboard_port}</strong>.</p>
        <form id="port-settings" phx-submit="save_port">
          <label for="dashboard-port">Usar no próximo início</label>
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
            /><button type="submit">Salvar</button>
          </div>
          <p :if={@port_error} class="settings-error" role="alert">{@port_error}</p>
          <p :if={@port_saved} class="settings-success" role="status">
            Salvo. Reinicie o LocalWebMonitorex para usar a nova porta.
          </p>
        </form>
        <div class="settings-note">
          <.icon name="hero-document-text" class="icon" /><span>Preferência local em<br /><code>{@settings_file}</code></span>
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

  defp range_bounds([]), do: {4000, 4100}
  defp range_bounds(ports), do: {Enum.min(ports), Enum.max(ports)}
end
