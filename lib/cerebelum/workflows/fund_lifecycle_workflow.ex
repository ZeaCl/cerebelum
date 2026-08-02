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
    fund_id = Ecto.UUID.generate()
    Logger.info("[FundWorkflow] create_fund: #{fund_data["name"]} → #{fund_id}")
    {:ok, %{fund_id: fund_id, fund_name: fund_data["name"] || "Fondo", status: "DRAFT"}}
  end

  # ── Step: Activate (DRAFT → FUNDRAISING, con edit loop) ──────────────

  def activate(ctx, {:ok, fund}) do
    {action, data} = approve_action(ctx)

    cond do
      action == "edit" ->
        Logger.info("[FundWorkflow] activate: edit #{fund.fund_name}")
        # TODO: PUT /funds/{id} with edit data
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
        # TODO: POST /funds/{id}/activate
        {:ok, Map.merge(fund, %{status: "FUNDRAISING"})}

      true ->
        # Primera entrada o re-entry sin acción clara
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
      # TODO: POST /funds/{id}/first-close
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
      # TODO: POST /funds/{id}/transition
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
        # TODO: POST /funds/{id}/close
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
      # TODO: POST /funds/{id}/transition → LIQUIDATED
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
