defmodule LocalWebMonitorex.Settings do
  @moduledoc "Stores the dashboard port as a small local preference file."

  @default_port 4020

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:local_web_monitorex, :settings_file)

  @spec read_port(String.t()) :: pos_integer()
  def read_port(path \\ path()) do
    case File.read(path) do
      {:ok, value} -> parse_port(value) |> port_or_default()
      {:error, _reason} -> @default_port
    end
  end

  @spec save_port(String.t() | integer(), String.t()) :: :ok | {:error, atom()}
  def save_port(value, path \\ path()) do
    with {:ok, port} <- parse_port(value),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write_atomically(path, "#{port}\n") do
      :ok
    end
  end

  @spec default_port() :: pos_integer()
  def default_port, do: @default_port

  defp parse_port(value) when is_integer(value) and value in 1024..65_535, do: {:ok, value}

  defp parse_port(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port in 1024..65_535 -> {:ok, port}
      _ -> {:error, :invalid_port}
    end
  end

  defp parse_port(_value), do: {:error, :invalid_port}

  defp port_or_default({:ok, port}), do: port
  defp port_or_default({:error, _reason}), do: @default_port

  defp write_atomically(path, content) do
    temporary = "#{path}.tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temporary, content),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary)
        {:error, reason}
    end
  end
end
