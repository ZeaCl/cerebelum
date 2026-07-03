defmodule Cerebelum.API.Router do
  use Cerebelum.API, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug Cerebelum.API.Plugs.JWTAuth
    plug Cerebelum.API.Plugs.RateLimiter
  end

  # Internal API pipeline — no auth (for intra-network services)
  pipeline :internal_api do
    plug :accepts, ["json"]
  end

  # Health check (no /api prefix for compatibility)
  get "/health", Cerebelum.API.HealthController, :health

  # Public read-only API (no auth required for workflow discovery)
  scope "/api/v1", Cerebelum.API do
    pipe_through :internal_api

    # Workflows registry endpoint
    get "/workflows", WorkflowController, :index
    get "/workflows/:id", WorkflowController, :show
    get "/workflows/:id/code", WorkflowController, :code
  end

  # Authenticated API
  scope "/api/v1", Cerebelum.API do
    pipe_through :api

    # Execution endpoints
    get "/executions", ExecutionController, :index
    post "/executions", ExecutionController, :create
    get "/executions/:id", ExecutionController, :show
    get "/executions/:id/events", ExecutionController, :events
    post "/executions/:id/stop", ExecutionController, :stop
    post "/executions/:id/resume", ExecutionController, :resume
    post "/executions/:id/approve", ExecutionController, :approve

    # Workers listing (requires auth)
    get "/workers", WorkerController, :index
  end

  # Internal API for Python workers (no JWT required)
  scope "/api/internal", Cerebelum.API do
    pipe_through :internal_api

    post "/workers/register", WorkerController, :register
  end
end
