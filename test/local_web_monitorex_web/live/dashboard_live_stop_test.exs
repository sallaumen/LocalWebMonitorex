defmodule LocalWebMonitorexWeb.DashboardLiveStopTest do
  use LocalWebMonitorexWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LocalWebMonitorex.ProcessInfo
  alias LocalWebMonitorex.Service

  defmodule FakeStopper do
    def stop(service) do
      send(Application.fetch_env!(:local_web_monitorex, :stop_test_pid), {
        :stop_requested,
        service.port,
        service.process.pid
      })

      :ok
    end
  end

  test "requires confirmation before stopping a monitored process", %{conn: conn} do
    previous = Application.get_env(:local_web_monitorex, :process_terminator)
    Application.put_env(:local_web_monitorex, :process_terminator, FakeStopper)
    Application.put_env(:local_web_monitorex, :stop_test_pid, self())

    on_exit(fn ->
      Application.put_env(:local_web_monitorex, :process_terminator, previous)
      Application.delete_env(:local_web_monitorex, :stop_test_pid)
    end)

    {:ok, view, _html} = live(conn, "/")
    publish_service(view, service_with_process())

    assert render_click(element(view, "button[phx-click=confirm_stop]")) =~ "Stop beam.smp?"
    assert has_element?(view, "#stop-dialog[aria-modal=true]")
    refute_receive {:stop_requested, _, _}

    render_click(element(view, "button[phx-click=cancel_stop]"))
    refute has_element?(view, "#stop-dialog")
    refute_receive {:stop_requested, _, _}

    render_click(element(view, "button[phx-click=confirm_stop]"))
    render_click(element(view, "button[phx-click=stop_process]"))
    assert_receive {:stop_requested, 4055, 42}
  end

  test "never offers a stop action without a verified process", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    publish_service(view, %Service{port: 4055, status: 200, scheme: "http", title: "Example"})

    refute has_element?(view, "button[phx-click=confirm_stop]")
    refute has_element?(view, "#stop-dialog")
  end

  defp publish_service(view, service) do
    send(view.pid, {:services_updated, %{services: [service], checked_at: nil, scanning: false}})
  end

  defp service_with_process do
    %Service{
      port: 4055,
      status: 200,
      scheme: "http",
      title: "Example",
      process: %ProcessInfo{pid: 42, name: "beam.smp", cpu_percent: 0.0, memory_bytes: 1024}
    }
  end
end
