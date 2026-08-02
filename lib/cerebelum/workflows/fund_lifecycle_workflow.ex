defmodule Cerebelum.FundLifecycleWorkflow do
  @moduledoc """
  Fund Lifecycle Workflow — Elixir nativo en Cerebelum.
  Cada estado del ciclo de vida es un step con HITL nativo.
  Sin Python, sin gRPC worker externo, sin race conditions.

  Timeline:
    create_fund → activate → first_close → start_harvesting → close_fund → liquidate → notify
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

  # ── HTTP Helper ──────────────────────────────────────────────────────

  defp api(method, path, body \\ nil, ctx \\ nil) do
    url = @fund_url <> path
    headers = [{'content-type', 'application/json'}]

    headers =
      case get_auth_token(ctx) do
        nil -> headers
        token -> [{'authorization', 'Bearer #{token}'} | headers]
      end

    payload = if body, do: Jason.encode!(body), else: ""

    case :httpc.request(
           String.to_atom(method),
           {String.to_charlist(url), headers, 'application/json', payload},
           [],
           []
         ) do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 ->
        Jason.decode!(body)

      {:ok, {{_, status, _}, _, body}} ->
        Logger.error("[FundWorkflow] API #{method} #{path} → #{status}: #{body}")
        raise "API error #{status}: #{body}"

      {:error, reason} ->
        Logger.error("[FundWorkflow] API #{method} #{path} → #{inspect(reason)}")
        raise "API error: #{inspect(reason)}"
    end
  end

  defp get_auth_token(%{metadata: %{auth_token: token}}) when is_binary(token), do: token
  defp get_auth_token(_), do: nil

  # ── Helpers ──────────────────────────────────────────────────────────

  defp approve_action(ctx) do
    ctx.inputs
    |> Map.get("approve_response", ctx.inputs)
    |> case do
      %{"action" => action} = data -> {action, data}
      _ -> {nil, %{}}
    end
  end

  # ── Step: Create Fund (DRAFT) ────────────────────────────────────────

  def create_fund(%{inputs: inputs} = ctx) do
    fund_data = inputs["fund_data"] || %{}
    name = fund_data["name"] || "Fondo"
    exec_id = ctx.execution_id

    Logger.info("[FundWorkflow] create_fund: #{name} (exec=#{exec_id})")

    body = %{
      execution_id: exec_id,
      name: name,
      type: fund_data["type"] || "PE",
      currency: fund_data["currency"] || "USD",
      target_size: fund_data["size"] || 5_000_000,
      management_fee: 0.02,
      carried_interest: 0.20,
      hurdle_rate: 0.08,
      fund_term_years: 10,
      investment_period_years: 5,
      fundraising_months: 12,
      investment_months: 60,
      harvesting_months: 48,
      thesis: "Creado via Cerebelum nativo"
    }

    fund = api(:post, "/funds/draft", body, ctx)
    fund_id = fund["id"]
    Logger.info("[FundWorkflow] create_fund: ✅ #{name} → #{fund_id}")

    {:ok, %{fund_id: fund_id, fund_name: name, status: "DRAFT"}}
  end

  # ── Step: Activate (DRAFT → FUNDRAISING) ────────────────────────────

  def activate(ctx, {:ok, fund}) do
    {action, data} = approve_action(ctx)

    cond do
      action == "edit" ->
        Logger.info("[FundWorkflow] activate: edit #{fund.fund_name}")
        update = %{}
        update = if name = data["name"], do: Map.put(update, :name, name), else: update

        update =
          if size = data["total_size"], do: Map.put(update, :total_size, size), else: update

        if map_size(update) > 0, do: api(:put, "/funds/#{fund.fund_id}", update, ctx)

        {:wait_for_approval, [type: :manual],
         %{
           step: "activate",
           fund_id: fund.fund_id,
           fund_name: fund.fund_name,
           fund_status: "DRAFT",
           available_actions: ["edit", "activate"]
         }}

      action == "activate" ->
        Logger.info("[FundWorkflow] activate: #{fund.fund_name} → FUNDRAISING")
        fund = api(:post, "/funds/#{fund.fund_id}/activate", nil, ctx)
        {:ok, Map.merge(fund, %{status: "FUNDRAISING"})}

      true ->
        Logger.info("[FundWorkflow] activate: waiting (DRAFT)")

        {:wait_for_approval, [type: :manual],
         %{
           step: "activate",
           fund_id: fund.fund_id,
           fund_name: fund.fund_name,
           fund_status: "DRAFT",
           available_actions: ["edit", "activate"]
         }}
    end
  end

  # ── Step: First Close (FUNDRAISING → ACTIVE) ─────────────────────────

  def first_close(ctx, {:ok, _activate}, {:ok, fund}) do
    {action, data} = approve_action(ctx)

    if action == "first_close" do
      Logger.info("[FundWorkflow] first_close: #{fund.fund_name} → ACTIVE")

      body = %{
        close_date: data["close_date"],
        final_amount: data["final_amount"],
        lp_count: data["lp_count"]
      }

      fund = api(:post, "/funds/#{fund.fund_id}/first-close", body, ctx)
      {:ok, Map.merge(fund, %{status: "ACTIVE"})}
    else
      Logger.info("[FundWorkflow] first_close: waiting (FUNDRAISING)")

      {:wait_for_approval, [type: :manual],
       %{
         step: "first_close",
         fund_id: fund.fund_id,
         fund_name: fund.fund_name,
         fund_status: "FUNDRAISING",
         available_actions: ["first_close"]
       }}
    end
  end

  # ── Step: Start Harvesting (ACTIVE → HARVESTING) ─────────────────────

  def start_harvesting(ctx, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, data} = approve_action(ctx)

    if action == "start_harvesting" do
      Logger.info("[FundWorkflow] start_harvesting: #{fund.fund_name} → HARVESTING")
      body = %{status: "HARVESTING", harvest_start: data["harvest_start"]}
      fund = api(:post, "/funds/#{fund.fund_id}/transition", body, ctx)
      {:ok, Map.merge(fund, %{status: "HARVESTING"})}
    else
      Logger.info("[FundWorkflow] start_harvesting: waiting (ACTIVE)")

      {:wait_for_approval, [type: :manual],
       %{
         step: "start_harvesting",
         fund_id: fund.fund_id,
         fund_name: fund.fund_name,
         fund_status: "ACTIVE",
         available_actions: ["start_harvesting"]
       }}
    end
  end

  # ── Step: Close Fund (HARVESTING → CLOSED) ───────────────────────────

  def close_fund(ctx, {:ok, _harvest}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, data} = approve_action(ctx)

    if action == "close_fund" do
      auditoria = data["auditoria"] || ""

      if auditoria == "" do
        {:error, :auditoria_required}
      else
        Logger.info("[FundWorkflow] close_fund: #{fund.fund_name} → CLOSED")
        fund = api(:post, "/funds/#{fund.fund_id}/close", %{auditoria: auditoria}, ctx)
        {:ok, Map.merge(fund, %{status: "CLOSED"})}
      end
    else
      Logger.info("[FundWorkflow] close_fund: waiting (HARVESTING)")

      {:wait_for_approval, [type: :manual],
       %{
         step: "close_fund",
         fund_id: fund.fund_id,
         fund_name: fund.fund_name,
         fund_status: "HARVESTING",
         available_actions: ["close_fund"]
       }}
    end
  end

  # ── Step: Liquidate (CLOSED → LIQUIDATED) ────────────────────────────

  def liquidate(ctx, {:ok, _close}, {:ok, _harvest}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {action, _data} = approve_action(ctx)

    if action == "liquidate" do
      Logger.info("[FundWorkflow] liquidate: #{fund.fund_name} → LIQUIDATED")
      fund = api(:post, "/funds/#{fund.fund_id}/transition", %{status: "LIQUIDATED"}, ctx)
      {:ok, Map.merge(fund, %{status: "LIQUIDATED", liquidated: true})}
    else
      Logger.info("[FundWorkflow] liquidate: waiting (CLOSED)")

      {:wait_for_approval, [type: :manual],
       %{
         step: "liquidate",
         fund_id: fund.fund_id,
         fund_name: fund.fund_name,
         fund_status: "CLOSED",
         available_actions: ["liquidate"]
       }}
    end
  end

  # ── Step: Notify (FIN) ────────────────────────────────────────────────

  def notify(
        _ctx,
        {:ok, _liq},
        {:ok, _close},
        {:ok, _harvest},
        {:ok, _fc},
        {:ok, _act},
        {:ok, fund}
      ) do
    Logger.info("[FundWorkflow] notify: #{fund.fund_name} — LIQUIDATED ✅")
    {:ok, Map.merge(fund, %{notified: true})}
  end
end
