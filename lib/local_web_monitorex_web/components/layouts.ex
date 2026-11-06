defmodule LocalWebMonitorexWeb.Layouts do
  @moduledoc "Root layout for the local dashboard."

  use LocalWebMonitorexWeb, :html

  alias LocalWebMonitorex.UpdateStatus

  embed_templates "layouts/*"

  @doc "Names the served commit so the updater can confirm which version answered."
  def revision_meta(assigns) do
    assigns = assign(assigns, :revision, UpdateStatus.installed_revision())

    ~H"""
    <meta :if={@revision} name="localwebmonitorex-revision" content={@revision} />
    """
  end
end
