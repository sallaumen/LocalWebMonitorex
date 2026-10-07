defmodule LocalWebMonitorex.PortProbe.HttpTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.PortProbe.Http

  test "recognizes a local HTTP service and extracts its title" do
    {port, task, listener} = start_server(0)

    assert {:ok, service} = Http.probe(port)
    assert service.title == "Example app"
    assert service.status == 200
    Task.await(task)
    :gen_tcp.close(listener)
  end

  test "recognizes a local HTTP service that takes 900 ms to respond" do
    {port, task, listener} = start_server(900)

    assert {:ok, service} = Http.probe(port)
    assert service.status == 200
    Task.await(task)
    :gen_tcp.close(listener)
  end

  test "does not list a closed port" do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)

    assert Http.probe(port) == :closed
  end

  defp start_server(delay_ms) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 1_000)
        Process.sleep(delay_ms)
        body = "<html><head><title>Example app</title></head><body>ok</body></html>"

        response =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
      end)

    {port, task, listener}
  end
end
