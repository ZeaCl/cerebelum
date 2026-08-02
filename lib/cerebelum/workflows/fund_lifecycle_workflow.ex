defmodule Cerebelum.FundLifecycleWorkflow do
  @moduledoc "Fund Lifecycle Workflow — Elixir nativo en Cerebelum."

  use Cerebelum.Workflow
  require Logger

  @fund_url Application.compile_env(:cerebelum, :fund_service_url, "http://fm_funds:4082")

  workflow do
    timeline do
      create_fund()
      |> activate()
      |> first_close()
      |> start_investing()
      |> start_harvesting()
      |> close_fund()
      |> liquidate()
      |> notify()
    end
  end

  # ── HTTP ─────────────────────────────────────────────────────

  defp api(method, path, body, ctx) do
    url = @fund_url <> path
    headers = [{~c"content-type", ~c"application/json"}]

    headers =
      if t = get_auth(ctx), do: [{~c"authorization", ~c"Bearer #{t}"} | headers], else: headers

    payload = if body, do: Jason.encode!(body), else: ""

    req =
      if method in [:get, :head] do
        {String.to_charlist(url), headers}
      else
        {String.to_charlist(url), headers, ~c"application/json", payload}
      end

    case :httpc.request(method, req, [], []) do
      {:ok, {{_, s, _}, _, b}} when s in 200..299 -> Jason.decode!(b)
      {:ok, {{_, s, _}, _, b}} -> raise "API #{s}: #{b}"
      {:error, r} -> raise "API error: #{inspect(r)}"
    end
  end

  defp get_fund(id, ctx), do: api(:get, "/funds/#{id}", nil, ctx)

  defp get_auth(%{metadata: %{auth_token: t}}) when is_binary(t), do: t
  defp get_auth(_), do: nil

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

    # Recovery mode: fund already exists, skip creation
    existing_fund_id = fd["fund_id"]
    if existing_fund_id && existing_fund_id != "" do
      Logger.info("[FundWorkflow] Recovery mode — fund already exists: #{existing_fund_id}")
      fund = get_fund(existing_fund_id, ctx)
      {:ok, %{fund_id: existing_fund_id, fund_name: fund["name"] || name, status: fund["status"] || "DRAFT"}}
    else
      fund =
        api(
          :post,
          "/funds/draft",
        %{
          execution_id: id,
          name: name,
          type: fd["type"] || "PE",
          currency: fd["currency"] || "USD",
          target_size: to_int(fd["target_size"] || fd["total_size"] || 5_000_000),
          management_fee_bps: to_int(fd["management_fee_bps"] || fd["management_fee"] || 200),
          carried_interest_bps:
            to_int(fd["carried_interest_bps"] || fd["carried_interest"] || 2000),
          hurdle_rate_bps: to_int(fd["hurdle_rate_bps"] || fd["hurdle_rate"] || 800),
          fund_term_years: to_int(fd["fund_term_years"] || 10),
          investment_period_years: to_int(fd["investment_period_years"] || 5),
          fundraising_months: to_int(fd["fundraising_months"] || 12),
          investment_months: to_int(fd["investment_months"] || 60),
          harvesting_months: to_int(fd["harvesting_months"] || 48),
          thesis: fd["thesis"] || "Creado via Cerebelum nativo",
          vintage_year: to_int(fd["vintage_year"]),
          hard_cap: to_int(fd["hard_cap"])
        },
        ctx
      )

      fid = fund["id"]
      verify!(ctx, fid, "DRAFT")
      {:ok, %{fund_id: fid, fund_name: name, status: "DRAFT"}}
    end
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
        # Idempotent: if already FUNDRAISING or beyond, skip
        fund_data = get_fund(fund.fund_id, ctx)
        if fund_data["status"] in ["FUNDRAISING", "ACTIVE", "INVESTING", "HARVESTING", "CLOSED", "LIQUIDATED"] do
          Logger.info("[FundWorkflow] activate skipped — already #{fund_data["status"]}")
          {:ok, %{fund | status: fund_data["status"]}}
        else
          api(:post, "/funds/#{fund.fund_id}/activate", nil, ctx)
          verify!(ctx, fund.fund_id, "FUNDRAISING")
          {:ok, %{fund | status: "FUNDRAISING"}}
        end

      true ->
        wfa("activate", fund, "DRAFT", ["edit", "activate"])
    end
  end

  # ── first_close (FUNDRAISING) ─────────────────────────────────

  def first_close(ctx, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)

    cond do
      a == "first_close" ->
        date = d["close_date"] || d["date"] || ""
        if date == "", do: raise("close_date required for first_close")

        api(
          :post,
          "/funds/#{fund.fund_id}/first-close",
          %{
            close_date: date,
            final_amount: to_int(d["final_amount"] || d["amount"] || 0),
            lp_count: to_int(d["lp_count"] || d["lps"] || 0)
          },
          ctx
        )

        verify!(ctx, fund.fund_id, "ACTIVE")
        {:ok, %{fund | status: "ACTIVE"}}

      true ->
        wfa("first_close", fund, "FUNDRAISING", ["first_close"])
    end
  end

  # ── start_investing (FUNDRAISING → INVESTING) ─────────────────

  def start_investing(ctx, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)

    if a == "start_investing" do
      date = d["investment_start"] || d["date"] || ""
      body = %{status: "INVESTING"}
      body = if date != "", do: Map.put(body, :investment_start, date), else: body
      api(:post, "/funds/#{fund.fund_id}/transition", body, ctx)
      verify!(ctx, fund.fund_id, "INVESTING")
      {:ok, %{fund | status: "INVESTING"}}
    else
      wfa("start_investing", fund, "FUNDRAISING", ["start_investing"])
    end
  end

  # ── start_harvesting (INVESTING → HARVESTING) ─────────────────

  def start_harvesting(ctx, {:ok, _si}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)

    if a == "start_harvesting" do
      date = d["harvest_start"] || d["date"] || ""
      body = %{status: "HARVESTING"}
      body = if date != "", do: Map.put(body, :harvest_start, date), else: body
      api(:post, "/funds/#{fund.fund_id}/transition", body, ctx)
      verify!(ctx, fund.fund_id, "HARVESTING")
      {:ok, %{fund | status: "HARVESTING"}}
    else
      wfa("start_harvesting", fund, "INVESTING", ["start_harvesting"])
    end
  end

  # ── close_fund (HARVESTING → CLOSED) ──────────────────────────

  def close_fund(ctx, {:ok, _sh}, {:ok, _si}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
    {a, d} = action(ctx)

    if a == "close_fund" do
      aud = d["auditoria"] || ""
      if aud == "", do: raise("auditoria required")
      api(:post, "/funds/#{fund.fund_id}/close", %{auditoria: aud}, ctx)
      verify!(ctx, fund.fund_id, "CLOSED")
      {:ok, %{fund | status: "CLOSED"}}
    else
      wfa("close_fund", fund, "HARVESTING", ["close_fund"])
    end
  end

  # ── liquidate (CLOSED → LIQUIDATED) ───────────────────────────

  def liquidate(ctx, {:ok, _cf}, {:ok, _sh}, {:ok, _si}, {:ok, _fc}, {:ok, _act}, {:ok, fund}) do
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

  def notify(
        _ctx,
        {:ok, _lq},
        {:ok, _cf},
        {:ok, _sh},
        {:ok, _si},
        {:ok, _fc},
        {:ok, _act},
        {:ok, fund}
      ) do
    Logger.info("[FundWorkflow] notify: #{fund.fund_name} — LIQUIDATED ✅")
    {:ok, Map.merge(fund, %{notified: true})}
  end

  # ── helpers ───────────────────────────────────────────────────

  defp wfa(step, fund, status, actions) do
    {:wait_for_approval, [type: :manual],
     %{
       step: step,
       fund_id: fund.fund_id,
       fund_name: fund.fund_name,
       fund_status: status,
       available_actions: actions
     }}
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: trunc(n)

  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> nil
    end
  end
end
