defmodule LocalWebMonitorexWeb.PreviewControllerTest do
  use LocalWebMonitorexWeb.ConnCase

  test "rejects ports outside the monitored range", %{conn: conn} do
    assert response(get(conn, "/previews/9999"), 404) == "Not found"
  end

  test "returns a missing response before a capture exists", %{conn: conn} do
    assert response(get(conn, "/previews/4000"), 404) == "Not found"
  end
end
