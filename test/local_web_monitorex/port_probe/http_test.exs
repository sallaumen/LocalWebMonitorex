defmodule LocalWebMonitorex.PortProbe.HttpTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.PortProbe.Http

  test "recognizes a local HTTP service and extracts its title" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 1_000)
        body = "<html><head><title>Meu app</title></head><body>ok</body></html>"

        response =
          "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"

        :ok = :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
      end)

    assert {:ok, service} = Http.probe(port)
    assert service.title == "Meu app"
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
end
