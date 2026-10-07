defmodule LocalWebMonitorex.ProcessTerminatorTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.ProcessInfo
  alias LocalWebMonitorex.ProcessTerminator
  alias LocalWebMonitorex.Service

  defmodule Inspector do
    def snapshot(_ports), do: Process.get(:current_processes, %{})
  end

  defmodule Controller do
    def terminate(pid) do
      send(self(), {:terminate, pid})
      Process.get(:termination_result, :ok)
    end
  end

  test "terminates only the process still listening on the confirmed port" do
    service = service(4055, 42)
    Process.put(:current_processes, %{4055 => service.process})

    assert :ok = ProcessTerminator.stop(service, Inspector, Controller)
    assert_receive {:terminate, 42}
  end

  test "refuses a stale PID and never signals its replacement" do
    service = service(4055, 42)
    Process.put(:current_processes, %{4055 => process(84)})

    assert {:error, :stale_process} = ProcessTerminator.stop(service, Inspector, Controller)
    refute_receive {:terminate, _pid}
  end

  test "refuses a process that no longer listens on the port" do
    assert {:error, :stale_process} =
             ProcessTerminator.stop(service(4055, 42), Inspector, Controller)

    refute_receive {:terminate, _pid}
  end

  test "refuses the dashboard port and its own OS process" do
    own_pid = :os.getpid() |> to_string() |> String.to_integer()

    assert {:error, :protected_process} =
             ProcessTerminator.stop(service(4100, 42), Inspector, Controller)

    assert {:error, :protected_process} =
             ProcessTerminator.stop(service(4055, own_pid), Inspector, Controller)

    refute_receive {:terminate, _pid}
  end

  test "reports missing metrics and command failures" do
    assert {:error, :process_unavailable} =
             ProcessTerminator.stop(
               %Service{port: 4055, scheme: "http", status: 200},
               Inspector,
               Controller
             )

    service = service(4055, 42)
    Process.put(:current_processes, %{4055 => service.process})
    Process.put(:termination_result, {:error, :permission_denied})

    assert {:error, :permission_denied} =
             ProcessTerminator.stop(service, Inspector, Controller)
  end

  defp service(port, pid) do
    %Service{port: port, scheme: "http", status: 200, process: process(pid)}
  end

  defp process(pid) do
    %ProcessInfo{pid: pid, name: "beam.smp", cpu_percent: 0.0, memory_bytes: 1024}
  end
end
