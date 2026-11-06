defmodule LocalWebMonitorexWeb.DashboardLiveTest do
  use LocalWebMonitorexWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LocalWebMonitorex.Service
  alias LocalWebMonitorexWeb.DashboardLive

  test "shows the dashboard address and English interface", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "LocalWebMonitorex"
    assert html =~ "localhost:#{Application.fetch_env!(:local_web_monitorex, :dashboard_port)}"
    assert html =~ "Running services"
    assert html =~ "4000–4500"
    refute html =~ "Main port"
    refute html =~ "Visão geral"
  end

  test "opens a larger preview without leaving the dashboard and closes it when the service stops",
       %{
         conn: conn
       } do
    service = %Service{port: 4055, status: 200, scheme: "http", title: "Example"}
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:services_updated, %{services: [service], checked_at: nil, scanning: false}})
    send(view.pid, {:preview_ready, 4055, 123})

    assert render(view) =~ "Example"
    assert has_element?(view, "button[phx-click=open_preview][phx-value-port='4055']")

    assert render_click(element(view, "button[phx-click=open_preview]")) =~
             "Full preview of http://localhost:4055"

    assert has_element?(view, "dialog[aria-modal=true]")
    assert has_element?(view, "dialog a[href='http://localhost:4055']")

    send(view.pid, {:services_updated, %{services: [], checked_at: nil, scanning: false}})
    refute render(view) =~ "Full preview of http://localhost:4055"
    refute has_element?(view, "dialog[aria-modal=true]")
  end

  test "labels filtered results separately from all active ports", %{conn: conn} do
    services = [
      %Service{port: 4055, status: 200, scheme: "http", title: "Demo"},
      %Service{port: 4013, status: 200, scheme: "http", title: "Other"}
    ]

    {:ok, view, _html} = live(conn, "/")
    send(view.pid, {:services_updated, %{services: services, checked_at: nil, scanning: false}})

    assert render_change(element(view, "#service-filter"), %{"query" => "405"}) =~
             "Matches"

    assert has_element?(view, ".service-card", "Demo")
    refute has_element?(view, ".service-card", "Other")
  end

  test "saves the next dashboard port from settings", %{conn: conn} do
    path =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-live-#{System.unique_integer([:positive])}/port"
      )

    previous = Application.get_env(:local_web_monitorex, :settings_file)
    Application.put_env(:local_web_monitorex, :settings_file, path)

    on_exit(fn ->
      Application.put_env(:local_web_monitorex, :settings_file, previous)
      File.rm_rf!(Path.dirname(path))
    end)

    {:ok, view, _html} = live(conn, "/")
    assert render_click(element(view, "button.rail-button")) =~ "Dashboard port"

    assert render_submit(element(view, "form[phx-submit=save_port]"), %{"port" => "4321"}) =~
             "Saved. Restart"

    assert File.read!(path) == "4321\n"
  end

  test "offers system, light, and dark appearance choices", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    render_click(element(view, "button.rail-button"))

    for choice <- ~w(auto light dark) do
      assert has_element?(view, "button[data-theme-choice=#{choice}]")
    end
  end

  test "saves the next watched range from settings", %{conn: conn} do
    path =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-range-#{System.unique_integer([:positive])}/range"
      )

    previous = Application.get_env(:local_web_monitorex, :range_settings_file)
    Application.put_env(:local_web_monitorex, :range_settings_file, path)

    on_exit(fn ->
      Application.put_env(:local_web_monitorex, :range_settings_file, previous)
      File.rm_rf!(Path.dirname(path))
    end)

    {:ok, view, _html} = live(conn, "/")
    assert render_click(element(view, "button.rail-button")) =~ "Watched range"

    assert render_submit(element(view, "form[phx-submit=save_range]"), %{
             "start" => "4050",
             "end" => "4080"
           }) =~ "Saved. Restart"

    assert File.read!(path) == "4050-4080\n"

    assert render_submit(element(view, "form[phx-submit=save_range]"), %{
             "start" => "4080",
             "end" => "4050"
           }) =~ "Choose a valid range"

    assert File.read!(path) == "4050-4080\n"
  end

  test "renders a discovered service before its preview is ready" do
    service = %Service{
      port: 4005,
      status: 200,
      scheme: "http",
      title: "Example",
      response_ms: 12,
      process: %LocalWebMonitorex.ProcessInfo{
        pid: 42,
        name: "node",
        cpu_percent: 1.5,
        memory_bytes: 52_428_800
      }
    }

    assigns = render_assigns(services: [service])

    html = render_component(&DashboardLive.render/1, assigns)

    assert html =~ "Example"
    assert html =~ "PID 42"
    assert html =~ "1.5%"
    assert html =~ "50 MiB"
  end

  test "shows unavailable CPU data without losing Windows process details" do
    service = %Service{
      port: 4005,
      status: 200,
      scheme: "http",
      process: %LocalWebMonitorex.ProcessInfo{
        pid: 42,
        name: "node",
        cpu_percent: nil,
        memory_bytes: 52_428_800
      }
    }

    assigns = render_assigns(services: [service])

    html = render_component(&DashboardLive.render/1, assigns)

    assert html =~ "PID 42"
    assert html =~ "50 MiB"
    assert html =~ "CPU"
    assert html =~ "—"
  end

  test "says a snapshot is unavailable after a failed capture", %{conn: conn} do
    service = %Service{port: 4055, status: 200, scheme: "http", title: "Example"}
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:services_updated, %{services: [service], checked_at: nil, scanning: false}})
    assert has_element?(view, ".service-card", "Capturing snapshot")

    send(view.pid, {:preview_failed, 4055})
    assert has_element?(view, ".service-card", "Snapshot unavailable")
    refute has_element?(view, ".service-card", "Capturing snapshot")

    send(view.pid, {:preview_ready, 4055, 1_700_000_000_000})
    refute has_element?(view, ".service-card", "Snapshot unavailable")

    assert has_element?(
             view,
             "button[phx-click=open_preview][phx-value-port='4055']:not([disabled])"
           )
  end

  test "reports the first scan as in progress instead of finding nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    send(view.pid, {:services_updated, %{services: [], checked_at: nil, scanning: true}})
    assert has_element?(view, ".empty-state", "Scanning ports")
    refute has_element?(view, ".empty-state", "No web servers found")

    send(
      view.pid,
      {:services_updated, %{services: [], checked_at: DateTime.utc_now(), scanning: false}}
    )

    assert has_element?(view, ".empty-state", "No web servers found")
  end

  test "shows when the last scan finished and which ports are watched" do
    html =
      render_component(
        &DashboardLive.render/1,
        render_assigns(checked_at: ~U[2026-11-06 14:02:11Z], dashboard_port: 4050)
      )

    assert html =~ "Last scan"
    assert html =~ ~r/\d{2}:\d{2}:\d{2}/
    assert html =~ "100 ports"
    assert html =~ "excludes :4050"
  end

  test "explains HTTP status, response time, and missing process details" do
    service = %Service{port: 4005, status: 500, scheme: "http", response_ms: 18}
    html = render_component(&DashboardLive.render/1, render_assigns(services: [service]))

    assert html =~ "500 Internal Server Error"
    assert html =~ "18 ms"
    assert html =~ "No page title"
    assert html =~ "Process details unavailable"
  end

  test "flags saved settings that only apply on the next start" do
    html =
      render_component(
        &DashboardLive.render/1,
        render_assigns(
          settings_open: true,
          saved_range_start: 5000,
          saved_range_end: 5100,
          saved_port: 4200
        )
      )

    assert html =~ "5000–5100"
    assert html =~ "Applies on next start"
    assert html =~ "4200"
  end

  defp render_assigns(overrides) do
    Map.merge(
      %{
        services: [],
        previews: %{},
        preview_failures: MapSet.new(),
        checked_at: nil,
        query: "",
        scanning: false,
        settings_open: false,
        selected_service: nil,
        stop_target: nil,
        stop_task: nil,
        notice: nil,
        dashboard_port: 4100,
        saved_port: 4100,
        settings_file: "/tmp/localwebmonitorex/port",
        range_start: 4000,
        range_end: 4099,
        saved_range_start: 4000,
        saved_range_end: 4099,
        range_file: "/tmp/localwebmonitorex/range",
        range_error: nil,
        range_saved: false,
        port_error: nil,
        port_saved: false
      },
      Map.new(overrides)
    )
  end
end
