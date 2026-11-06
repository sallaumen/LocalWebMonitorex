defmodule LocalWebMonitorex.UpdateStatus do
  @moduledoc """
  Reads what the macOS updater last recorded about this installation.

  The updater writes `key=value` lines to a status file. The running copy's
  own commit comes from its `REVISION` file, so a check made for another
  installed commit is reported as pending instead of being trusted.
  """

  @reasons %{
    "fetch_failed" => :fetch_failed,
    "build_failed" => :build_failed,
    "smoke_failed" => :smoke_failed,
    "switch_failed" => :switch_failed,
    "restart_failed" => :restart_failed,
    "installed_revision_missing" => :installed_revision_missing
  }

  @failure_text %{
    fetch_failed: "could not reach GitHub",
    build_failed: "the new version did not build",
    smoke_failed: "the new version did not start",
    switch_failed: "could not switch to the new version",
    restart_failed: "the new version did not stay up, so the previous one was restored",
    installed_revision_missing: "the installed commit is unknown",
    unknown: "see the updater log"
  }

  @type state ::
          :unconfigured
          | :pending
          | :up_to_date
          | :diverged
          | {:behind, pos_integer()}
          | {:failed, atom()}

  @type t :: %__MODULE__{
          installed: String.t() | nil,
          available: String.t() | nil,
          checked_at: DateTime.t() | nil,
          state: state()
        }

  defstruct installed: nil, available: nil, checked_at: nil, state: :unconfigured

  @spec status_path() :: String.t() | nil
  def status_path, do: Application.get_env(:local_web_monitorex, :update_status_file)

  @spec revision_path() :: String.t()
  def revision_path do
    Application.get_env(:local_web_monitorex, :revision_file, Path.join(File.cwd!(), "REVISION"))
  end

  @spec installed_revision(String.t()) :: String.t() | nil
  def installed_revision(path \\ revision_path()) do
    with {:ok, content} <- File.read(path),
         sha when byte_size(sha) == 40 <- String.trim(content),
         true <- hex?(sha) do
      sha
    else
      _ -> nil
    end
  end

  @spec read(String.t() | nil, String.t()) :: t()
  def read(status_path \\ status_path(), revision_path \\ revision_path()) do
    installed = installed_revision(revision_path)
    status = %__MODULE__{installed: installed}

    case read_fields(status_path) do
      :unconfigured -> status
      :missing -> %{status | state: :pending}
      {:ok, fields} -> from_fields(status, fields)
    end
  end

  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{state: :up_to_date}), do: "Up to date with main"
  def summary(%__MODULE__{state: {:behind, 1}}), do: "Behind main by 1 commit"
  def summary(%__MODULE__{state: {:behind, count}}), do: "Behind main by #{count} commits"
  def summary(%__MODULE__{state: :pending}), do: "Waiting for the first update check"
  def summary(%__MODULE__{state: :unconfigured}), do: "Automatic updates are not set up"

  def summary(%__MODULE__{state: :diverged}),
    do: "Installed commit is not on main; automatic updates are paused"

  def summary(%__MODULE__{state: {:failed, reason}}),
    do: "Update failed: #{Map.fetch!(@failure_text, reason)}"

  @spec short_sha(String.t() | nil) :: String.t()
  def short_sha(nil), do: "unknown"
  def short_sha(sha), do: String.slice(sha, 0, 7)

  defp read_fields(nil), do: :unconfigured

  defp read_fields(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, parse_fields(content)}
      {:error, _reason} -> :missing
    end
  end

  defp parse_fields(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_line/1)
    |> Map.new()
  end

  defp parse_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> [{key, String.trim(value)}]
      _ -> []
    end
  end

  defp from_fields(%{installed: installed} = status, %{"installed_sha" => installed} = fields)
       when is_binary(installed) do
    case state(fields) do
      {:ok, state} ->
        %{
          status
          | state: state,
            available: fields["available_sha"],
            checked_at: checked_at(fields)
        }

      :error ->
        %{status | state: :pending}
    end
  end

  defp from_fields(status, _fields), do: %{status | state: :pending}

  defp state(%{"phase" => "up_to_date"}), do: {:ok, :up_to_date}
  defp state(%{"phase" => "diverged"}), do: {:ok, :diverged}
  defp state(%{"phase" => "failed"} = fields), do: {:ok, {:failed, reason(fields["reason"])}}

  defp state(%{"phase" => "behind", "behind" => behind}) do
    case Integer.parse(behind) do
      {count, ""} when count > 0 -> {:ok, {:behind, count}}
      _ -> :error
    end
  end

  defp state(_fields), do: :error

  defp reason(value), do: Map.get(@reasons, value, :unknown)

  defp checked_at(%{"checked_at" => value}) do
    with {seconds, ""} <- Integer.parse(value),
         {:ok, datetime} <- DateTime.from_unix(seconds) do
      datetime
    else
      _ -> nil
    end
  end

  defp checked_at(_fields), do: nil

  defp hex?(value), do: String.match?(value, ~r/\A[0-9a-f]+\z/)
end
