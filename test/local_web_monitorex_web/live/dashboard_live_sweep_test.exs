defmodule LocalWebMonitorexWeb.DashboardLiveSweepTest do
  use LocalWebMonitorexWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias LocalWebMonitorex.Settings
  alias LocalWebMonitorex.Sweeper
  alias LocalWebMonitorex.Sweeper.Finding

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-sweep-#{System.unique_integer([:positive])}"
      )

    keys = [:sweep_settings_file, :range_settings_file]
    previous = Map.new(keys, &{&1, Application.get_env(:local_web_monitorex, &1)})
    Application.put_env(:local_web_monitorex, :sweep_settings_file, Path.join(directory, "sweep"))
    Application.put_env(:local_web_monitorex, :range_settings_file, Path.join(directory, "range"))

    on_exit(fn ->
      :ok = GenServer.call(Sweeper, {:set_enabled, false})

      Enum.each(previous, fn {key, value} ->
        Application.put_env(:local_web_monitorex, key, value)
      end)

      File.rm_rf!(directory)
    end)

    %{directory: directory}
  end

  defp sweep(overrides) do
    Map.merge(
      %{
        enabled: true,
        phase: :waiting,
        checked: 0,
        total: 65_034,
        findings: [],
        last_pass_at: nil,
        next_pass_at: nil
      },
      Map.new(overrides)
    )
  end

  test "keeps the sweep panel collapsed until it is opened", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    findings = [%Finding{port: 8080, http: true, scheme: "http", status: 200, title: "Docs"}]
    send(view.pid, {:sweep_updated, sweep(phase: :sweeping, checked: 16_259, findings: findings)})

    assert has_element?(view, "#sweep-panel button[aria-expanded=false]", "Other ports")
    assert has_element?(view, "#sweep-panel .sweep-count", "1")
    refute has_element?(view, "#sweep-body")

    view |> element("#sweep-panel button[aria-expanded]") |> render_click()

    assert has_element?(view, "#sweep-panel button[aria-expanded=true]")
    assert has_element?(view, "#sweep-body", "16,259 of 65,034 ports")
    assert has_element?(view, "#sweep-body li", "8080")
    assert has_element?(view, "#sweep-body li", "HTTP 200")
    assert has_element?(view, ~s(#sweep-body a[href="http://localhost:8080"]))
  end

  test "closes the open sweep panel with Escape", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    view |> element("#sweep-panel button[aria-expanded]") |> render_click()

    view |> element("#sweep-panel") |> render_keydown(%{"key" => "Escape"})

    refute has_element?(view, "#sweep-body")
  end

  test "lists listeners that answer only TCP with their process name", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    findings = [%Finding{port: 64_120, http: false, process_name: "rapportd"}]
    now = DateTime.utc_now()
    snapshot = sweep(findings: findings, last_pass_at: now, next_pass_at: DateTime.add(now, 3600))
    send(view.pid, {:sweep_updated, snapshot})
    view |> element("#sweep-panel button[aria-expanded]") |> render_click()

    assert has_element?(view, "#sweep-body li", "64120")
    assert has_element?(view, "#sweep-body li", "rapportd")
    assert has_element?(view, "#sweep-body li", "TCP")
    refute has_element?(view, "#sweep-body li a")
    assert has_element?(view, "#sweep-body", "Next pass")
  end

  test "turns the wide sweep on and off from the panel and saves the choice", %{
    conn: conn,
    directory: directory
  } do
    {:ok, view, _html} = live(conn, "/")
    view |> element("#sweep-panel button[aria-expanded]") |> render_click()

    assert has_element?(view, "#sweep-body", "Wide sweep is off")
    view |> element("#sweep-body button[role=switch][aria-checked=false]") |> render_click()

    assert Sweeper.snapshot().enabled
    assert File.read!(Path.join(directory, "sweep")) == "on\n"
    assert has_element?(view, "#sweep-body button[role=switch][aria-checked=true]")

    view |> element("#sweep-body button[role=switch]") |> render_click()

    assert %{enabled: false, phase: :off} = Sweeper.snapshot()
    assert Settings.read_sweep() == false
    assert has_element?(view, "#sweep-body", "Wide sweep is off")
  end

  test "suggests a wider watched range without saving it", %{conn: conn, directory: directory} do
    {:ok, view, _html} = live(conn, "/")
    findings = [%Finding{port: 8080, http: false}]
    send(view.pid, {:sweep_updated, sweep(findings: findings)})
    view |> element("#sweep-panel button[aria-expanded]") |> render_click()

    view
    |> element(~s(#sweep-body button[aria-label="Add port 8080 to the watched range"]))
    |> render_click()

    assert has_element?(view, ~s(#range-start[value="4000"]))
    assert has_element?(view, ~s(#range-end[value="8080"]))
    assert has_element?(view, "#range-settings", "Save to watch port 8080")
    refute File.exists?(Path.join(directory, "range"))
  end
end
