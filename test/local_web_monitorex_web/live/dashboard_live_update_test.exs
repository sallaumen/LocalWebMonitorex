defmodule LocalWebMonitorexWeb.DashboardLiveUpdateTest do
  use LocalWebMonitorexWeb.ConnCase

  import Phoenix.LiveViewTest

  @installed "1111111111111111111111111111111111111111"

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-updates-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    revision = Path.join(directory, "REVISION")
    status = Path.join(directory, "status")
    File.write!(revision, @installed <> "\n")

    previous = Map.new([:revision_file, :update_status_file], &{&1, app_env(&1)})
    Application.put_env(:local_web_monitorex, :revision_file, revision)

    on_exit(fn ->
      Enum.each(previous, fn {key, value} -> restore_env(key, value) end)
      File.rm_rf!(directory)
    end)

    %{status: status}
  end

  test "identifies the served commit so the updater can verify a restart", %{conn: conn} do
    html = conn |> get("/") |> html_response(200)

    assert html =~ ~s(name="localwebmonitorex-revision" content="#{@installed}")
  end

  test "omits the revision marker when the commit is unknown", %{conn: conn} do
    Application.put_env(:local_web_monitorex, :revision_file, "/nonexistent/REVISION")

    refute conn |> get("/") |> html_response(200) =~ "localwebmonitorex-revision"
  end

  test "shows the installed commit and that updates are not set up", %{conn: conn} do
    Application.delete_env(:local_web_monitorex, :update_status_file)
    {:ok, view, _html} = live(conn, "/")

    html = render_click(element(view, "button.rail-button"))

    assert has_element?(view, "section[aria-labelledby=updates-title]")
    assert html =~ "1111111"
    assert html =~ "Automatic updates are not set up"
  end

  test "shows how far behind main the installation is and when it checked", %{
    conn: conn,
    status: status
  } do
    Application.put_env(:local_web_monitorex, :update_status_file, status)

    File.write!(status, """
    installed_sha=#{@installed}
    phase=behind
    behind=2
    checked_at=1762430400
    """)

    {:ok, view, _html} = live(conn, "/")
    html = render_click(element(view, "button.rail-button"))

    assert html =~ "Behind main by 2 commits"
    assert has_element?(view, "#updates-checked time[datetime='2025-11-06T12:00:00Z']")
  end

  test "rereads the update status each time settings open", %{conn: conn, status: status} do
    Application.put_env(:local_web_monitorex, :update_status_file, status)
    {:ok, view, _html} = live(conn, "/")

    assert render_click(element(view, "button.rail-button")) =~
             "Waiting for the first update check"

    render_click(element(view, "button[aria-label='Close settings']"))

    File.write!(status, """
    installed_sha=#{@installed}
    phase=failed
    reason=build_failed
    checked_at=1762430400
    """)

    html = render_click(element(view, "button.rail-button"))
    assert html =~ "Update failed: the new version did not build"
    assert has_element?(view, "#updates-summary[role=status]")
  end

  defp app_env(key), do: Application.fetch_env(:local_web_monitorex, key)

  defp restore_env(key, {:ok, value}), do: Application.put_env(:local_web_monitorex, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:local_web_monitorex, key)
end
