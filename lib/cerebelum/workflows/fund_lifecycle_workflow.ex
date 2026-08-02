defmodule Cerebelum.FundLifecycleWorkflow do
  @moduledoc """
  Fund Lifecycle Workflow — Elixir nativo en Cerebelum.
  Cada estado del ciclo de vida es un step con HITL nativo.
  """

  use Cerebelum.Workflow
  require Logger

  @fund_url Application.compile_env(:cerebelum, :fund_service_url, "http://fm_funds:4082")

  workflow do
    timeline do
      create_fund()
      |> activate()
      |> first_close()
      |> start_harvesting()
      |> close_fund()
      |> liquidate()
      |> notify()
    end
  end

  # ── HTTP Helper ───────────────────────────────────────────────

  defp api(method, path, body \\ nil, ctx \\ nil) do
    url = @fund_url <> path
    headers = [{'content-type', 'application/json'}]
    headers = if t = get_auth(ctx), do: [{'authorization', 'Bearer #{t}'} | headers], else: headers
    payload = if body, do: Jason.encode!(body), else: ""

    case :httpc.request(method, {String.to_charlist(url), headers, 'application/json', payload}, [], []) do
      {:ok, {{_, status, _}, _, resp_body}} when status in 200..299 -> Jason.decode!(resp_body)
      {:ok, {{_, status, _}, _, resp_body}} -> Logger.error("[FundWorkflow] #{method} #{path} → #{status}"); raise "API #{status}"
      {:error, reason} -> Logger.error("[FundWorkflow] #{method} #{path} → #{inspect(reason)}"); raise "API error"
    end
  end

  defp get_auth(%{metadata: %{auth_token: t}}) when is_binary(t), do: t
  defp get_auth(_), do: nil

  defp int(n) when is_integer(n), do: n
  defp int(s) when is_binary(s), do: String.to_integer(s)
  defp int(_), do: 0

  defp approve_action(ctx) do
    case ctx.inputs |> Map.get("approve_response", ctx.inputs) do
      %{"action" => a} = d -> {a, d}
      _ -> {nil, %{}}
    end
  end

  # ── Step: Create Fund (DRAFT) ─────────────────────────────────

  def create_fund(%{inputs: inputs} = ctx) do
    fd = inputs["fund_data"] || %{}
    name = fd["name"] || "Fondo"
    Logger.info("[FundWorkflow] create_fund: #{name} exec=#{ctx.execution_id}")

    fund = api(:post, "/funds/draft", %{
      execution_id: ctx.execution_id, name: name, type: fd["type"] || "PE",
      currency: "USD", target_size: 5_000_000, management_fee: 0.02,
      carried_interest: 0.20, hurdle_rate: 0.08, fund_term_years: 10,
      investment_period_years: 5, fundraising_months: 12,
      investment_months: 60, harvesting_months: 48,
      thesis: "Creado via Cerebelum nativo"
    }, ctx)

    {:ok, %{fund_id: fund["id"], fund_name: name, status: "DRAFT"}}
  end

  # ── Step: Activate (DRAFT → FUNDRAISING) ─────────────────────

  def activate(ctx, {:ok, fund}) do
    {action, data} = approve_action(ctx)
    cond do
      action == "edit" ->
        up = %{}
        up = if n = data["name"], do: Map.put(up, :name, n), else: up
        if map_size(up) > 0, do: api(:put, "/funds/#{fund.fund_id}", up, ctx)
        {:wait_for_approval, [type: :manual], %{step: "activate", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "DRAFT", available_actions: ["edit", "activate"]}}

      action == "activate" ->
        Logger.info("[FundWorkflow] activate → FUNDRAISING")
        api(:post, "/funds/#{fund.fund_id}/activate", nil, ctx)
        {:ok, Map.merge(fund, %{status: "FUNDRAISING"})}

      true ->
        {:wait_for_approval, [type: :manual], %{step: "activate", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "DRAFT", available_actions: ["edit", "activate"]}}
    end
  end

  # ── Step: First Close (FUNDRAISING → ACTIVE) ──────────────────

  def first_close(ctx, {:ok, _act}, {:ok, fund}) do
    {action, data} = approve_action(ctx)
    if action == "first_close" do
      Logger.info("[FundWorkflow] first_close → ACTIVE")
      api(:post, "/funds/#{fund.fund_id}/first-close", %{
        close_date: data["close_date"], final_amount: int(data["final_amount"]), lp_count: int(data["lp_count"])
      }, ctx)
      {:ok, Map.merge(fund, %{status: "ACTIVE"})}
    else
      {:wait_for_approval, [type: :manual], %{step: "first_close", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "FUNDRAISING", available_actions: ["first_close"]}}
    end
  end

  # ── Step: Start Harvesting (ACTIVE → HARVESTING) ──────────────

  def start_harvesting(ctx, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, data} = approve_action(ctx)
    if action == "start_harvesting" do
      Logger.info("[FundWorkflow] start_harvesting → HARVESTING")
      api(:post, "/funds/#{fund.fund_id}/transition", %{status: "HARVESTING", harvest_start: data["harvest_start"]}, ctx)
      {:ok, Map.merge(fund, %{status: "HARVESTING"})}
    else
      {:wait_for_approval, [type: :manual], %{step: "start_harvesting", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "ACTIVE", available_actions: ["start_harvesting"]}}
    end
  end

  # ── Step: Close Fund (HARVESTING → CLOSED) ────────────────────

  def close_fund(ctx, {:ok, _harv}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, data} = approve_action(ctx)
    if action == "close_fund" do
      aud = data["auditoria"] || ""
      if aud == "", do: throw({:error, :auditoria_required})
      Logger.info("[FundWorkflow] close_fund → CLOSED")
      api(:post, "/funds/#{fund.fund_id}/close", %{auditoria: aud}, ctx)
      {:ok, Map.merge(fund, %{status: "CLOSED"})}
    else
      {:wait_for_approval, [type: :manual], %{step: "close_fund", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "HARVESTING", available_actions: ["close_fund"]}}
    end
  end

  # ── Step: Liquidate (CLOSED → LIQUIDATED) ─────────────────────

  def liquidate(ctx, {:ok, _close}, {:ok, _harv}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, _} = approve_action(ctx)
    if action == "liquidate" do
      Logger.info("[FundWorkflow] liquidate → LIQUIDATED")
      api(:post, "/funds/#{fund.fund_id}/transition", %{status: "LIQUIDATED"}, ctx)
      {:ok, Map.merge(fund, %{status: "LIQUIDATED", liquidated: true})}
    else
      {:wait_for_approval, [type: :manual], %{step: "liquidate", fund_id: fund.fund_id, fund_name: fund.fund_name, fund_status: "CLOSED", available_actions: ["liquidate"]}}
    end
  end

  # ── Step: Notify (FIN) ────────────────────────────────────────

  def notify(_ctx, {:ok, _liq}, {:ok, _close}, {:ok, _harv}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    Logger.info("[FundWorkflow] notify: #{fund.fund_name} — LIQUIDATED ✅")
    {:ok, Map.merge(fund, %{notified: true})}
  end
end
