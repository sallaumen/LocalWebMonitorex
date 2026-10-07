defmodule LocalWebMonitorex.SettingsTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.Settings

  test "uses port 4020 when no local preference exists" do
    path = Path.join(System.tmp_dir!(), "missing-port-#{System.unique_integer([:positive])}")

    assert Settings.read_port(path) == 4020
  end

  test "saves a valid port for the next startup" do
    path = temporary_path()
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    assert :ok = Settings.save_port("4321", path)
    assert Settings.read_port(path) == 4321
    assert File.read!(path) == "4321\n"
  end

  test "rejects an invalid port without replacing the saved value" do
    path = temporary_path()
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)
    :ok = Settings.save_port("4020", path)

    assert {:error, :invalid_port} = Settings.save_port("70000", path)
    assert Settings.read_port(path) == 4020
  end

  defp temporary_path do
    Path.join(
      System.tmp_dir!(),
      "localwebmonitorex-test-#{System.unique_integer([:positive])}/port"
    )
  end
end
