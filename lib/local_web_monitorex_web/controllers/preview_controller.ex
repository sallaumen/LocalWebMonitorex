defmodule LocalWebMonitorexWeb.PreviewController do
  use LocalWebMonitorexWeb, :controller

  alias LocalWebMonitorex.Previews

  def show(conn, %{"port" => value}) do
    with {port, ""} <- Integer.parse(value),
         true <- port in Application.get_env(:local_web_monitorex, :monitor_ports, 4000..4099),
         true <- port != Application.get_env(:local_web_monitorex, :dashboard_port, 4100),
         {:ok, path, _version} <- Previews.image(port),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/png")
      |> put_resp_header("cache-control", "private, max-age=30")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end
end
