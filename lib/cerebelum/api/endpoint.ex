defmodule Cerebelum.API.Endpoint do
  use Phoenix.Endpoint, otp_app: :cerebelum

  # CORS origins from CORS_ORIGINS env var (comma-separated), with dev defaults.
  # Evaluated at compile time — CORS_ORIGINS is set in Dockerfile / docker-compose.
  @cors_origins if System.get_env("CORS_ORIGINS"),
    do: System.get_env("CORS_ORIGINS") |> String.split(",") |> Enum.map(&String.trim/1),
    else: [
      "http://localhost:4000",
      "http://localhost:4001",
      "http://localhost:5173",
      "http://localhost:3000"
    ]

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(CORSPlug,
    origin: @cors_origins,
    headers: ["Authorization", "Content-Type", "Accept"],
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)

  plug(Cerebelum.API.Router)
end
