defmodule LocalWebMonitorex.PreviewsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias LocalWebMonitorex.Previews
  alias LocalWebMonitorex.Service

  defmodule FakeCapture do
    def capture(_service, path) do
      result = Application.fetch_env!(:local_web_monitorex, :fake_capture_result)
      if result == :ok, do: File.write!(path, "png")
      result
    end
  end

  setup do
    previous = %{
      monitor_ports: Application.get_env(:local_web_monitorex, :monitor_ports),
      preview_capture: Application.get_env(:local_web_monitorex, :preview_capture)
    }

    Application.put_env(:local_web_monitorex, :monitor_ports, 4900..4999)
    Application.put_env(:local_web_monitorex, :preview_capture, FakeCapture)
    Previews.subscribe()

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        Application.put_env(:local_web_monitorex, key, value)
      end)

      Application.delete_env(:local_web_monitorex, :fake_capture_result)
    end)
  end

  test "reports a failed capture and clears it once a capture succeeds" do
    port = 4900 + rem(System.unique_integer([:positive]), 100)
    service = %Service{port: port, status: 200, scheme: "http"}

    Application.put_env(:local_web_monitorex, :fake_capture_result, {:error, "page timed out"})

    capture_log(fn ->
      Previews.request(service)
      assert_receive {:preview_failed, ^port}, 1_000
    end)

    assert Previews.failed?(port)
    assert Previews.version(port) == nil

    Application.put_env(:local_web_monitorex, :fake_capture_result, :ok)
    Previews.request(service)

    assert_receive {:preview_ready, ^port, version}, 1_000
    assert Previews.version(port) == version
    refute Previews.failed?(port)
  end
end
