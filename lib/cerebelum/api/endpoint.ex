defmodule Cerebelum.API.Endpoint do
  use Phoenix.Endpoint, otp_app: :cerebelum

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug CORSPlug,
    origin: [
      "http://localhost:4000",
      "http://localhost:4001",
      "http://localhost:5173",
      "http://localhost:3000"
    ],
    headers: ["Authorization", "Content-Type", "Accept"],
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  plug Cerebelum.API.Router
end
