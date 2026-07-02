defmodule Cerebelum.API do
  @moduledoc """
  REST API layer for Cerebelum workflow engine.

  Provides controllers, router, and middleware for the HTTP API.
  Only loaded when `http_enabled: true` in config.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
