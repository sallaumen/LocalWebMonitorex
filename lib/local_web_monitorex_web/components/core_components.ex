defmodule LocalWebMonitorexWeb.CoreComponents do
  @moduledoc "Shared icon component for the dashboard."

  use Phoenix.Component

  attr :name, :string, required: true
  attr :class, :string, default: "icon"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} aria-hidden="true" />
    """
  end
end
