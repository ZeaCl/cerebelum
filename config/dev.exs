import Config

# Development database config
config :cerebelum, Cerebelum.Repo,
  database: "cerebelum_core_dev",
  username: "dev",
  hostname: "localhost",
  # Add password if needed
  password: "",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# gRPC server configuration (enabled for Python SDK testing)
# Set to true if you need to test multi-language SDK workers
config :cerebelum,
  enable_grpc_server: true,
  # Using 9090 instead of 50051 for testing
  grpc_port: 9090
