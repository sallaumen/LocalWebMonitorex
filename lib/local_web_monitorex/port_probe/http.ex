defmodule LocalWebMonitorex.PortProbe.Http do
  @moduledoc "Probes loopback HTTP endpoints without following redirects."

  @behaviour LocalWebMonitorex.PortProbe

  alias LocalWebMonitorex.Service

  @impl true
  def probe(port) when is_integer(port) and port > 0 and port < 65_536 do
    case accepts_tcp?(port) do
      true -> probe_http(port)
      false -> :closed
    end
  end

  # A loopback connection to a free port in the ephemeral range can connect to
  # itself when the kernel picks that same port as the source. That is not a
  # listener, so it counts as closed.
  defp accepts_tcp?(port) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 200) do
      {:ok, socket} ->
        self_connected = match?({:ok, {_address, ^port}}, :inet.sockname(socket))
        :ok = :gen_tcp.close(socket)
        not self_connected

      {:error, _reason} ->
        false
    end
  end

  defp probe_http(port) do
    case request(port, "http") do
      {:ok, response, elapsed} -> {:ok, service(port, "http", response, elapsed)}
      {:error, _reason} -> probe_https(port)
    end
  end

  defp probe_https(port) do
    case request(port, "https") do
      {:ok, response, elapsed} -> {:ok, service(port, "https", response, elapsed)}
      {:error, _reason} -> :tcp_only
    end
  end

  defp request(port, scheme) do
    started = System.monotonic_time(:millisecond)
    url = "#{scheme}://127.0.0.1:#{port}/"

    case Req.get(url,
           receive_timeout: 1_500,
           connect_options: [timeout: 250],
           retry: false,
           redirect: false
         ) do
      {:ok, response} -> {:ok, response, System.monotonic_time(:millisecond) - started}
      error -> error
    end
  end

  defp service(port, scheme, response, elapsed) do
    [content_type | _] = Req.Response.get_header(response, "content-type") ++ [nil]

    %Service{
      port: port,
      scheme: scheme,
      status: response.status,
      title: title(response.body, content_type),
      content_type: content_type,
      response_ms: elapsed
    }
  end

  defp title(body, content_type) when is_binary(body) and is_binary(content_type) do
    if String.contains?(content_type, "text/html") do
      case Regex.run(~r/<title[^>]*>(.*?)<\/title>/is, body, capture: :all_but_first) do
        [name] -> name |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 80)
        nil -> nil
      end
    end
  end

  defp title(_body, _content_type), do: nil
end
