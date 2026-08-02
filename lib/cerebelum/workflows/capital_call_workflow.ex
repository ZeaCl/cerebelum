defmodule Cerebelum.CapitalCallWorkflow do
  @moduledoc "Capital Call Workflow — Elixir nativo en Cerebelum."

  use Cerebelum.Workflow
  require Logger

  @cc_url Application.compile_env(:cerebelum, :capital_calls_url, "http://fm_capital_calls:4083")

  workflow do
    timeline do
      create_capital_call() |> send_capital_call() |> pay_items() |> notify()
    end
  end

  # ── HTTP ─────────────────────────────────────────────────────

  defp api(method, path, body, ctx) do
    url = @cc_url <> path
    headers = [{~c"content-type", ~c"application/json"}]
    headers = if t = get_auth(ctx), do: [{~c"authorization", ~c"Bearer #{t}"} | headers], else: headers
    payload = if body, do: Jason.encode!(body), else: ""
    req = if method in [:get, :head], do: {String.to_charlist(url), headers}, else: {String.to_charlist(url), headers, ~c"application/json", payload}
    case :httpc.request(method, req, [], []) do
      {:ok, {{_, s, _}, _, b}} when s in 200..299 -> Jason.decode!(b)
      {:ok, {{_, s, _}, _, b}} -> raise "API #{s}: #{b}"
      {:error, r} -> raise "API error: #{inspect(r)}"
    end
  end

  defp get_auth(%{metadata: %{auth_token: t}}) when is_binary(t), do: t
  defp get_auth(_), do: nil

  defp action(ctx) do
    case ctx.inputs |> Map.get("approve_response", ctx.inputs) do
      %{"action" => a} = d -> {a, d}
      _ -> {nil, %{}}
    end
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_float(n), do: trunc(n)
  defp to_int(n) when is_binary(n) do
    case Integer.parse(n) do {i, _} -> i; :error -> nil end
  end

  # ── create_capital_call ───────────────────────────────────────

  def create_capital_call(%{inputs: inputs} = ctx) do
    fd = inputs["capital_call_data"] || %{}
    fund_id = fd["fund_id"]
    id = ctx.execution_id

    existing_id = fd["capital_call_id"]
    if existing_id && existing_id != "" do
      Logger.info("[CC] Recovery mode — capital call: #{existing_id}")
      {:ok, %{capital_call_id: existing_id, status: "DRAFT"}}
    else
      Logger.info("[CC] create for fund: #{fund_id}")
      cc = api(:post, "/capital-calls", %{
        execution_id: id, fund_id: fund_id,
        fund_name: fd["fund_name"] || "Fondo #{fund_id}",
        call_number: fd["call_number"] || "1",
        total_amount: fd["total_amount"] || "0",
        currency: fd["currency"] || "USD",
        issue_date: fd["issue_date"] || Date.utc_today() |> Date.to_string(),
        due_date: fd["due_date"] || Date.utc_today() |> Date.add(30) |> Date.to_string(),
        purpose: fd["purpose"] || "Capital call via Cerebelum"
      }, ctx)
      {:ok, %{capital_call_id: cc["id"], status: "DRAFT"}}
    end
  end

  # ── send_capital_call (DRAFT → SENT, crea items prorrateados) ─

  def send_capital_call(ctx, {:ok, cc}) do
    {a, _} = action(ctx)
    cond do
      a == "send" ->
        api(:post, "/capital-calls/#{cc.capital_call_id}/send", nil, ctx)
        {:ok, %{cc | status: "SENT"}}
      a == "edit" ->
        wfa("send_capital_call", cc, "DRAFT", ["edit", "send"])
      true ->
        wfa("send_capital_call", cc, "DRAFT", ["edit", "send"])
    end
  end

  # ── pay_items (SENT, repetible por cada LP) ───────────────────

  def pay_items(ctx, {:ok, _sc}, {:ok, cc}) do
    {a, d} = action(ctx)
    if a == "pay" do
      item_id = d["item_id"] || ""
      if item_id == "", do: raise("item_id required for pay")
      api(:post, "/capital-calls/#{cc.capital_call_id}/pay", %{
        item_id: item_id,
        amount: d["amount"] || "0",
        payment_date: d["payment_date"] || Date.utc_today() |> Date.to_string()
      }, ctx)
      # Check if all items are paid — if yes, advance; if no, stay
      items_resp = api(:get, "/capital-calls/#{cc.capital_call_id}/items", nil, ctx)
      all_paid = Enum.all?(items_resp["items"] || [], &(&1["status"] == "PAID"))
      if all_paid do
        {:ok, %{cc | status: "PAID"}}
      else
        wfa("pay_items", cc, "SENT", ["pay"])
      end
    else
      wfa("pay_items", cc, "SENT", ["pay"])
    end
  end

  # ── notify ────────────────────────────────────────────────────

  def notify(_ctx, {:ok, _pi}, {:ok, _sc}, {:ok, cc}) do
    Logger.info("[CC] notify: #{cc.capital_call_id} — PAID ✅")
    {:ok, cc}
  end

  # ── helpers ───────────────────────────────────────────────────

  defp wfa(step, cc, status, actions) do
    {:wait_for_approval, [type: :manual], %{
      step: step, capital_call_id: cc.capital_call_id, status: status, available_actions: actions}}
  end
end
