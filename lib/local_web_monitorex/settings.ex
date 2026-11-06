defmodule LocalWebMonitorex.Settings do
  @moduledoc "Stores the dashboard port, watched range and wide sweep switch in local files."

  @default_port 4100
  @default_range 4000..4500
  @port_space 1..65_535
  @plain_digits ~r/\A\d+\z/
  @grouped_digits ~r/\A\d{1,3}(?:[.,_ \x{00A0}\x{202F}]\d{3})+\z/u

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:local_web_monitorex, :settings_file)

  @spec range_path() :: String.t()
  def range_path, do: Application.fetch_env!(:local_web_monitorex, :range_settings_file)

  @spec sweep_path() :: String.t()
  def sweep_path, do: Application.fetch_env!(:local_web_monitorex, :sweep_settings_file)

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

  @doc """
  Saves an inclusive range inside 1..65535. Bounds may use grouped thousands,
  such as `4.000` or `4,000`, because browsers and locales format them that way.
  """
  @spec save_range(String.t() | integer(), String.t() | integer(), String.t()) ::
          :ok | {:error, :invalid_range_bound | :reversed_range | File.posix()}
  def save_range(first, last, path \\ range_path()) do
    with {:ok, range} <- parse_range(first, last),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- write_atomically(path, "#{range.first}-#{range.last}\n") do
      :ok
    end
  end

  @doc "Reads the wide sweep switch. A missing or unreadable file means on."
  @spec read_sweep(String.t()) :: boolean()
  def read_sweep(path \\ sweep_path()) do
    with {:ok, value} <- File.read(path),
         {:ok, enabled} <- parse_sweep(String.trim(value)) do
      enabled
    else
      _ -> true
    end
  end

  @doc "Saves the wide sweep switch from a boolean, `\"on\"` or `\"off\"`."
  @spec save_sweep(boolean() | String.t(), String.t()) ::
          :ok | {:error, :invalid_sweep | File.posix()}
  def save_sweep(value, path \\ sweep_path()) do
    with {:ok, enabled} <- parse_sweep(value),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      write_atomically(path, if(enabled, do: "on\n", else: "off\n"))
    end
  end

  defp parse_sweep(value) when is_boolean(value), do: {:ok, value}
  defp parse_sweep("on"), do: {:ok, true}
  defp parse_sweep("off"), do: {:ok, false}
  defp parse_sweep(_value), do: {:error, :invalid_sweep}

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
         {:ok, end_port} <- parse_bound(last) do
      ordered_range(start_port, end_port)
    end
  end

  defp ordered_range(start_port, end_port) when start_port <= end_port,
    do: {:ok, start_port..end_port}

  defp ordered_range(_start_port, _end_port), do: {:error, :reversed_range}

  defp parse_bound(value) when is_integer(value) and value in @port_space, do: {:ok, value}

  defp parse_bound(value) when is_binary(value) do
    value
    |> String.trim()
    |> digits()
    |> port_in_space()
  end

  defp parse_bound(_value), do: {:error, :invalid_range_bound}

  defp digits(text) do
    cond do
      Regex.match?(@plain_digits, text) -> {:ok, text}
      Regex.match?(@grouped_digits, text) -> {:ok, String.replace(text, ~r/\D/u, "")}
      true -> :error
    end
  end

  defp port_in_space({:ok, text}) do
    case String.to_integer(text) do
      port when port in @port_space -> {:ok, port}
      _port -> {:error, :invalid_range_bound}
    end
  end

  defp port_in_space(:error), do: {:error, :invalid_range_bound}

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
