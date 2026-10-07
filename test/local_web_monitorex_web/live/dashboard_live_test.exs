defmodule LocalWebMonitorexWeb.DashboardLiveTest do
  use LocalWebMonitorexWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LocalWebMonitorex.Service
  alias LocalWebMonitorexWeb.DashboardLive

  test "shows the dashboard address and English interface", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")

    assert html =~ "LocalWebMonitorex"
    assert html =~ "localhost:#{Application.fetch_env!(:local_web_monitorex, :dashboard_port)}"
    assert html =~ "Active ports"
    assert html =~ "4000–4099"
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

    assigns = %{
      services: [service],
      previews: %{},
      query: "",
      scanning: false,
      settings_open: false,
      selected_service: nil,
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
    }

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

    assigns = %{
      services: [service],
      previews: %{},
      query: "",
      scanning: false,
      settings_open: false,
      selected_service: nil,
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
    }

    html = render_component(&DashboardLive.render/1, assigns)

    assert html =~ "PID 42"
    assert html =~ "50 MiB"
    assert html =~ "CPU"
    assert html =~ "—"
  end
end
