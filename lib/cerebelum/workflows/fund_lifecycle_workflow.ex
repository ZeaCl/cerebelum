defmodule Cerebelum.FundLifecycleWorkflow do
  @moduledoc "Fund Lifecycle Workflow — Elixir nativo en Cerebelum."

  use Cerebelum.Workflow
  require Logger

  @fund_url Application.compile_env(:cerebelum, :fund_service_url, "http://fm_funds:4082")

  workflow do
    timeline do
      create_fund() |> activate() |> to_active() |>
        start_harvesting() |> close_fund() |> liquidate() |> notify()
    end
  end

  # ── HTTP ─────────────────────────────────────────────────────

  defp api(method, path, body \\ nil, ctx \\ nil) do
    url = @fund_url <> path
    headers = [{'content-type', 'application/json'}]
    headers = if t = get_auth(ctx), do: [{'authorization', 'Bearer #{t}'} | headers], else: headers
    payload = if body, do: Jason.encode!(body), else: ""
    case :httpc.request(method, {String.to_charlist(url), headers, 'application/json', payload}, [], []) do
      {:ok, {{_, s, _}, _, b}} when s in 200..299 -> Jason.decode!(b)
      {:ok, {{_, s, _}, _, b}} -> raise "API #{s}: #{b}"
      {:error, r} -> raise "API error: #{inspect(r)}"
    end
  end

  defp get_fund(id, ctx), do: api(:get, "/funds/#{id}", nil, ctx)

  defp get_auth(%{metadata: %{auth_token: t}}) when is_binary(t), do: t
  defp get_auth(_), do: nil

  defp int(n) when is_integer(n), do: n
  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(_), do: 0

  defp action(ctx) do
    case ctx.inputs |> Map.get("approve_response", ctx.inputs) do
      %{"action" => a} = d -> {a, d}
      _ -> {nil, %{}}
    end
  end

  defp verify!(ctx, id, expected) do
    fund = get_fund(id, ctx)
    actual = fund["status"] || ""
    if actual != expected do
      raise "Status mismatch: expected #{expected}, got #{actual}"
    end
    fund
  end

  # ── create_fund ───────────────────────────────────────────────

  def create_fund(%{inputs: inputs} = ctx) do
    fd = inputs["fund_data"] || %{}
    name = fd["name"] || "Fondo"
    id = ctx.execution_id
    Logger.info("[FundWorkflow] create_fund: #{name}")

    fund = api(:post, "/funds/draft", %{
      execution_id: id, name: name, type: "PE", currency: "USD",
      target_size: 5_000_000, management_fee: 0.02, carried_interest: 0.20,
      hurdle_rate: 0.08, fund_term_years: 10, investment_period_years: 5,
      fundraising_months: 12, investment_months: 60, harvesting_months: 48,
      thesis: "Creado via Cerebelum nativo"
    }, ctx)

    fid = fund["id"]
    verify!(ctx, fid, "DRAFT")
    {:ok, %{fund_id: fid, fund_name: name, status: "DRAFT"}}
  end

  # ── activate (DRAFT → FUNDRAISING) ────────────────────────────

  def activate(ctx, {:ok, fund}) do
    {a, d} = action(ctx)
    cond do
      a == "edit" ->
        up = %{}
        up = if n = d["name"], do: Map.put(up, :name, n), else: up
        if map_size(up) > 0, do: api(:put, "/funds/#{fund.fund_id}", up, ctx)
        wfa("activate", fund, "DRAFT", ["edit", "activate"])

      a == "activate" ->
        api(:post, "/funds/#{fund.fund_id}/activate", nil, ctx)
        verify!(ctx, fund.fund_id, "FUNDRAISING")
        {:ok, %{fund | status: "FUNDRAISING"}}

      true -> wfa("activate", fund, "DRAFT", ["edit", "activate"])
    end
  end

  # ── to_active (FUNDRAISING → ACTIVE) ──────────────────────────

  def to_active(ctx, {:ok, _act}, {:ok, fund}) do
    {a, _} = action(ctx)
    if a == "start_harvesting" do
      api(:post, "/funds/#{fund.fund_id}/transition", %{status: "ACTIVE"}, ctx)
      verify!(ctx, fund.fund_id, "ACTIVE")
      {:ok, %{fund | status: "ACTIVE"}}
    else
      wfa("to_active", fund, "FUNDRAISING", ["start_harvesting"])
    end
  end

  # ── start_harvesting (ACTIVE → HARVESTING) ────────────────────

  def start_harvesting(ctx, {:ok, _ta}, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)
    if a == "start_harvesting" do
      api(:post, "/funds/#{fund.fund_id}/transition", %{status: "HARVESTING", harvest_start: d["harvest_start"]}, ctx)
      verify!(ctx, fund.fund_id, "HARVESTING")
      {:ok, %{fund | status: "HARVESTING"}}
    else
      wfa("start_harvesting", fund, "ACTIVE", ["start_harvesting"])
    end
  end

  # ── close_fund (HARVESTING → CLOSED) ──────────────────────────

  def close_fund(ctx, {:ok, _sh}, {:ok, _ta}, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)
    if a == "close_fund" do
      aud = d["auditoria"] || ""
      if aud == "", do: raise "auditoria required"
      api(:post, "/funds/#{fund.fund_id}/close", %{auditoria: aud}, ctx)
      verify!(ctx, fund.fund_id, "CLOSED")
      {:ok, %{fund | status: "CLOSED"}}
    else
      wfa("close_fund", fund, "HARVESTING", ["close_fund"])
    end
  end

  # ── liquidate (CLOSED → LIQUIDATED) ───────────────────────────

  def liquidate(ctx, {:ok, _cf}, {:ok, _sh}, {:ok, _ta}, {:ok, _act}, {:ok, fund}) do
    {a, _} = action(ctx)
    if a == "liquidate" do
      api(:post, "/funds/#{fund.fund_id}/transition", %{status: "LIQUIDATED"}, ctx)
      verify!(ctx, fund.fund_id, "LIQUIDATED")
      {:ok, %{fund | status: "LIQUIDATED", liquidated: true}}
    else
      wfa("liquidate", fund, "CLOSED", ["liquidate"])
    end
  end

  # ── notify ────────────────────────────────────────────────────

  def notify(_ctx, {:ok, _lq}, {:ok, _cf}, {:ok, _sh}, {:ok, _ta}, {:ok, _act}, {:ok, fund}) do
    Logger.info("[FundWorkflow] notify: #{fund.fund_name} — LIQUIDATED ✅")
    {:ok, Map.merge(fund, %{notified: true})}
  end

  # ── wait_for_approval helper ──────────────────────────────────

  defp wfa(step, fund, status, actions) do
    {:wait_for_approval, [type: :manual], %{
      step: step, fund_id: fund.fund_id, fund_name: fund.fund_name,
      fund_status: status, available_actions: actions}}
  end
end
