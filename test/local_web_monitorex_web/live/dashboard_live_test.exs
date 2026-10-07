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
    refute html =~ "Main port"
    refute html =~ "Visão geral"
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
      dashboard_port: 4020,
      saved_port: 4020,
      settings_file: "/tmp/localwebmonitorex/port",
      range_start: 4000,
      range_end: 4100,
      port_error: nil,
      port_saved: false
    }

    html = render_component(&DashboardLive.render/1, assigns)

    assert html =~ "Example"
    assert html =~ "PID 42"
    assert html =~ "1.5%"
    assert html =~ "50 MiB"
  end
end
