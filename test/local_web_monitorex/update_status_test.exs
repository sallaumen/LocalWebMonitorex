defmodule LocalWebMonitorex.UpdateStatusTest do
  use ExUnit.Case, async: true

  alias LocalWebMonitorex.UpdateStatus

  @installed "1111111111111111111111111111111111111111"
  @latest "2222222222222222222222222222222222222222"

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "localwebmonitorex-update-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      status_path: Path.join(directory, "status"),
      revision_path: Path.join(directory, "REVISION")
    }
  end

  test "reports unconfigured updates when no status file is set", %{revision_path: revision} do
    File.write!(revision, @installed <> "\n")

    assert %UpdateStatus{state: :unconfigured, installed: @installed, checked_at: nil} =
             UpdateStatus.read(nil, revision)
  end

  test "reports an unknown installed commit without a revision file", %{revision_path: revision} do
    assert %UpdateStatus{installed: nil, state: :unconfigured} = UpdateStatus.read(nil, revision)
  end

  test "waits for the first check when the status file is missing", paths do
    File.write!(paths.revision_path, @installed)

    assert %UpdateStatus{state: :pending} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "reads an up-to-date check with its time", paths do
    write_status(paths, phase: "up_to_date", behind: "0", checked_at: "1762430400")

    assert %UpdateStatus{state: :up_to_date, checked_at: ~U[2025-11-06 12:00:00Z]} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "reads how many commits the installation is behind", paths do
    write_status(paths, phase: "behind", behind: "3", available_sha: @latest)

    assert %UpdateStatus{state: {:behind, 3}, available: @latest} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "reads a failed update with a known reason", paths do
    write_status(paths, phase: "failed", behind: "2", reason: "smoke_failed")

    assert %UpdateStatus{state: {:failed, :smoke_failed}} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "keeps unexpected failure reasons generic", paths do
    write_status(paths, phase: "failed", reason: "rm -rf /")

    assert %UpdateStatus{state: {:failed, :unknown}} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "reports an installation that is not on main", paths do
    write_status(paths, phase: "diverged", behind: "")

    assert %UpdateStatus{state: :diverged} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "treats a check of another installed commit as pending", paths do
    write_status(paths, phase: "behind", behind: "4", installed_sha: @latest)

    assert %UpdateStatus{state: :pending, checked_at: nil} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  test "treats a malformed status file as pending", paths do
    File.write!(paths.revision_path, @installed)
    File.write!(paths.status_path, "phase=behind\nbehind=many\n")

    assert %UpdateStatus{state: :pending} =
             UpdateStatus.read(paths.status_path, paths.revision_path)
  end

  describe "summary/1" do
    test "describes each state in plain language" do
      assert UpdateStatus.summary(status(:up_to_date)) == "Up to date with main"
      assert UpdateStatus.summary(status({:behind, 1})) == "Behind main by 1 commit"
      assert UpdateStatus.summary(status({:behind, 5})) == "Behind main by 5 commits"
      assert UpdateStatus.summary(status(:pending)) == "Waiting for the first update check"
      assert UpdateStatus.summary(status(:unconfigured)) == "Automatic updates are not set up"

      assert UpdateStatus.summary(status(:diverged)) ==
               "Installed commit is not on main; automatic updates are paused"

      assert UpdateStatus.summary(status({:failed, :build_failed})) ==
               "Update failed: the new version did not build"
    end
  end

  defp status(state), do: %UpdateStatus{state: state}

  defp write_status(paths, fields) do
    File.write!(paths.revision_path, @installed <> "\n")

    content =
      [installed_sha: @installed, checked_at: "1762430400"]
      |> Keyword.merge(fields)
      |> Enum.map_join(fn {key, value} -> "#{key}=#{value}\n" end)

    File.write!(paths.status_path, content)
  end
end
