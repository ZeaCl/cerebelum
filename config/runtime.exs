import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere.

# Runtime production configuration
if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :cerebelum, Cerebelum.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # Disable SSL for now (enable if your PostgreSQL requires it)
    ssl: false

  # gRPC server configuration
  enable_grpc = System.get_env("ENABLE_GRPC_SERVER", "true") == "true"
  grpc_port = String.to_integer(System.get_env("GRPC_PORT") || "9090")
  grpc_certs_dir = System.get_env("GRPC_CERTS_DIR") || "/app/priv/certs"

  config :cerebelum,
    enable_grpc_server: enable_grpc,
    grpc_port: grpc_port,
    grpc_certs_dir: grpc_certs_dir

  # Secret key base for signing/encryption (required if you add Phoenix later)
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :cerebelum,
    secret_key_base: secret_key_base

  # Phoenix endpoint HTTP server
  config :cerebelum, Cerebelum.API.Endpoint,
    server: true,
    http: [
      port: String.to_integer(System.get_env("PORT") || "4001")
    ],
    url: [
      host: System.get_env("PHX_HOST") || "localhost",
      port: String.to_integer(System.get_env("PORT") || "4001")
    ],
    secret_key_base: secret_key_base

  # Release configuration
  if release_node = System.get_env("RELEASE_NODE") do
    config :cerebelum,
      release_node: release_node
  end

  if release_cookie = System.get_env("RELEASE_COOKIE") do
    config :cerebelum,
      release_cookie: release_cookie
  end
end
