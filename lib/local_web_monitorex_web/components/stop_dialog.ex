defmodule LocalWebMonitorexWeb.StopDialog do
  @moduledoc "Confirmation dialog for ending a discovered listener."

  use LocalWebMonitorexWeb, :html

  attr :target, :any, required: true
  attr :stopping, :boolean, default: false

  def stop_dialog(assigns) do
    ~H"""
    <dialog
      id="stop-dialog"
      class="stop-dialog"
      phx-hook="StopDialog"
      phx-update="ignore"
      data-stop-port={@target.port}
      data-stopping={@stopping}
      aria-modal="true"
      aria-labelledby="stop-title"
      aria-describedby="stop-description"
    >
      <div class="stop-dialog-mark"><.icon name="hero-stop-circle" class="icon" /></div>
      <p class="stop-dialog-kicker">PROCESS CONTROL · PORT {@target.port}</p>
      <h2 id="stop-title">Stop {@target.process.name}?</h2>
      <p id="stop-description">
        This will terminate PID {@target.process.pid}. Other ports served by this process may also stop.
      </p>
      <div class="stop-dialog-identity">
        <span>LISTENER</span><strong>{@target.process.name}</strong>
        <span>PID</span><strong>{@target.process.pid}</strong>
        <span>PORT</span><strong>{@target.port}</strong>
      </div>
      <div class="stop-dialog-actions">
        <button type="button" data-stop-cancel phx-click="cancel_stop" disabled={@stopping}>
          Cancel
        </button>
        <button type="button" data-stop-submit phx-click="stop_process" disabled={@stopping}>
          <.icon name="hero-stop-circle" class="icon" />
          <span data-stop-label>Stop process</span>
        </button>
      </div>
    </dialog>
    """
  end
end
