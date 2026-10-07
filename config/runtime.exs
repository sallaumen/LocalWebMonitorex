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

saved_port =
  case File.read(settings_file) do
    {:ok, value} ->
      case Integer.parse(String.trim(value)) do
        {port, ""} when port in 1024..65_535 -> port
        _ -> 4020
      end

    {:error, _reason} ->
      4020
  end

port =
  case Integer.parse(System.get_env("PORT", Integer.to_string(saved_port))) do
    {value, ""} when value in 1024..65_535 -> value
    _ -> raise "PORT must be an integer from 1024 to 65535"
  end

config :local_web_monitorex, settings_file: settings_file, dashboard_port: port

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
