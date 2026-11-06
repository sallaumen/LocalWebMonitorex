defmodule LocalWebMonitorexWeb.UpdateStatusPanel do
  @moduledoc "Compact summary of the installed commit and the latest update check."

  use LocalWebMonitorexWeb, :html

  alias LocalWebMonitorex.UpdateStatus

  attr :status, UpdateStatus, required: true

  def update_status_panel(assigns) do
    ~H"""
    <section class="settings-updates" aria-labelledby="updates-title">
      <h3 id="updates-title">Updates</h3>
      <p id="updates-summary" role="status" class={summary_class(@status.state)}>
        {UpdateStatus.summary(@status)}
      </p>
      <dl>
        <dt>Installed commit</dt>
        <dd><code title={@status.installed}>{UpdateStatus.short_sha(@status.installed)}</code></dd>
        <dt>Last check</dt>
        <dd id="updates-checked">
          <time :if={@status.checked_at} datetime={DateTime.to_iso8601(@status.checked_at)}>
            {local_time(@status.checked_at)}
          </time>
          <span :if={is_nil(@status.checked_at)}>Not checked yet</span>
        </dd>
      </dl>
    </section>
    """
  end

  defp summary_class({:failed, _reason}), do: "settings-updates-summary failed"
  defp summary_class(:diverged), do: "settings-updates-summary failed"
  defp summary_class(_state), do: "settings-updates-summary"

  defp local_time(datetime) do
    {{year, month, day}, {hour, minute, _second}} =
      datetime
      |> DateTime.to_unix()
      |> :calendar.system_time_to_local_time(:second)

    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B", [year, month, day, hour, minute])
    |> IO.iodata_to_binary()
  end
end
