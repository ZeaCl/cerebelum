defmodule Cerebelum.API.Plugs.RateLimiter do
  @moduledoc """
  Simple rate limiter per organization_id.

  Default: 1000 requests per minute per org.
  Uses ETS for counters (resets on restart, OK for now).
  """
  import Plug.Conn
  require Logger

  @table :cerebelum_rate_limits
  @default_limit 1000
  @window_ms 60_000

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    org_id = conn.assigns[:organization_id] || "anonymous"
    limit = Application.get_env(:cerebelum, :rate_limit_per_minute, @default_limit)

    count = increment_counter(org_id)

    if count > limit do
      conn
      |> put_resp_header("x-ratelimit-remaining", "0")
      |> put_resp_header("retry-after", "#{ceil(@window_ms / 1000)}")
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "rate_limit_exceeded", limit: limit}))
      |> halt()
    else
      conn
      |> put_resp_header("x-ratelimit-remaining", "#{limit - count}")
    end
  end

  # ETS-based counter (lightweight, resets on restart)
  defp increment_counter(org_id) do
    table = ensure_table()
    key = {org_id, current_window()}
    try do
      :ets.update_counter(table, key, {2, 1}, {key, 0})
    rescue
      _ -> 1
    end
  end

  defp current_window, do: div(System.system_time(:millisecond), @window_ms)

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end
    @table
  end
end
