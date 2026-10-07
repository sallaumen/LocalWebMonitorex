defmodule LocalWebMonitorex.SettingsTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.Settings

  test "uses port 4100 when no local preference exists" do
    path = Path.join(System.tmp_dir!(), "missing-port-#{System.unique_integer([:positive])}")

    assert Settings.read_port(path) == 4100
  end

  test "saves a valid port for the next startup" do
    path = temporary_path()
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    assert :ok = Settings.save_port("4321", path)
    assert Settings.read_port(path) == 4321
    assert File.read!(path) == "4321\n"
    assert :ok = Settings.save_port("4322", path)
    assert Settings.read_port(path) == 4322
  end

  test "rejects an invalid port without replacing the saved value" do
    path = temporary_path()
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)
    :ok = Settings.save_port("4100", path)

    assert {:error, :invalid_port} = Settings.save_port("70000", path)
    assert Settings.read_port(path) == 4100
  end

  test "uses ports 4000 through 4099 when no range preference exists" do
    assert Settings.read_range(temporary_path("range")) == 4000..4099
  end

  test "saves a valid watched range for the next startup" do
    path = temporary_path("range")
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)

    assert :ok = Settings.save_range("4050", "4080", path)
    assert Settings.read_range(path) == 4050..4080
    assert File.read!(path) == "4050-4080\n"
    assert :ok = Settings.save_range(4051, 4081, path)
    assert Settings.read_range(path) == 4051..4081
  end

  test "rejects invalid or excessive ranges without changing the saved value" do
    path = temporary_path("range")
    on_exit(fn -> File.rm_rf!(Path.dirname(path)) end)
    :ok = Settings.save_range(4000, 4099, path)

    assert {:error, :invalid_range} = Settings.save_range("4100", "4000", path)
    assert {:error, :invalid_range} = Settings.save_range("1", "1001", path)
    assert {:error, :invalid_range} = Settings.save_range("0", "10", path)
    assert {:error, :invalid_range} = Settings.save_range("abc", "4099", path)
    assert Settings.read_range(path) == 4000..4099
  end

  defp temporary_path(filename \\ "port") do
    Path.join(
      System.tmp_dir!(),
      "localwebmonitorex-test-#{System.unique_integer([:positive])}/#{filename}"
    )
  end
end
