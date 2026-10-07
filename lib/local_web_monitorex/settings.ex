defmodule LocalWebMonitorex.Settings do
  @moduledoc "Stores dashboard and watched-range preferences in local files."

  @default_port 4100
  @default_range 4000..4500
  @max_range_size 1000

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:local_web_monitorex, :settings_file)

  @spec range_path() :: String.t()
  def range_path, do: Application.fetch_env!(:local_web_monitorex, :range_settings_file)

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

  @spec default_range() :: Range.t()
  def default_range, do: @default_range

  @spec read_range(String.t()) :: Range.t()
  def read_range(path \\ range_path()) do
    with {:ok, value} <- File.read(path),
         [first, last] <- String.split(String.trim(value), "-", parts: 2),
         {:ok, range} <- parse_range(first, last) do
      range
    else
      _ -> @default_range
    end
  end

  @spec save_range(String.t() | integer(), String.t() | integer(), String.t()) ::
          :ok | {:error, atom()}
  def save_range(first, last, path \\ range_path()) do
    with {:ok, range} <- parse_range(first, last),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write_atomically(path, "#{range.first}-#{range.last}\n") do
      :ok
    end
  end

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

  defp parse_range(first, last) do
    with {:ok, start_port} <- parse_bound(first),
         {:ok, end_port} <- parse_bound(last),
         true <- start_port <= end_port,
         true <- end_port - start_port + 1 <= @max_range_size do
      {:ok, start_port..end_port}
    else
      _ -> {:error, :invalid_range}
    end
  end

  defp parse_bound(value) when is_integer(value) and value in 1..65_535, do: {:ok, value}

  defp parse_bound(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {port, ""} when port in 1..65_535 -> {:ok, port}
      _ -> {:error, :invalid_range}
    end
  end

  defp parse_bound(_value), do: {:error, :invalid_range}

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
