import Config

windows? = match?({:win32, _}, :os.type())

config_home =
  if windows? do
    System.get_env("APPDATA") || Path.join(System.user_home!(), "AppData/Roaming")
  else
    System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
  end

settings_directory = if windows?, do: "LocalWebMonitorex", else: "localwebmonitorex"

settings_file =
  System.get_env("LOCALWEBMONITOREX_CONFIG") ||
    Path.join([config_home, settings_directory, "port"])

range_settings_file =
  System.get_env("LOCALWEBMONITOREX_RANGE_CONFIG") ||
    Path.join(Path.dirname(settings_file), "range")

saved_port =
  case File.read(settings_file) do
    {:ok, value} ->
      case Integer.parse(String.trim(value)) do
        {port, ""} when port in 1024..65_535 -> port
        _ -> 4100
      end

    {:error, _reason} ->
      4100
  end

if config_env() != :test do
  watched_ports =
    with {:ok, value} <- File.read(range_settings_file),
         [first, last] <- String.split(String.trim(value), "-", parts: 2),
         {start_port, ""} <- Integer.parse(first),
         {end_port, ""} <- Integer.parse(last),
         true <- start_port in 1..65_535,
         true <- end_port in 1..65_535,
         true <- start_port <= end_port,
         true <- end_port - start_port + 1 <= 1000 do
      start_port..end_port
    else
      _ -> 4000..4500
    end

  config :local_web_monitorex, monitor_ports: watched_ports
end

port =
  case Integer.parse(System.get_env("PORT", Integer.to_string(saved_port))) do
    {value, ""} when value in 1024..65_535 -> value
    _ -> raise "PORT must be an integer from 1024 to 65535"
  end

config :local_web_monitorex,
  settings_file: settings_file,
  range_settings_file: range_settings_file,
  dashboard_port: port

config :local_web_monitorex, LocalWebMonitorexWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: port],
  url: [host: "localhost", port: port, scheme: "http"]

if System.get_env("PHX_SERVER") == "true" do
  config :local_web_monitorex, LocalWebMonitorexWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)

  config :local_web_monitorex, LocalWebMonitorexWeb.Endpoint, secret_key_base: secret_key_base
end
