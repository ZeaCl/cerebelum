defmodule Cerebelum.CapitalCallWorkflowTest do
  use ExUnit.Case, async: true

  alias Cerebelum.CapitalCallWorkflow

  # ── Workflow metadata ──────────────────────────────────────────

  describe "workflow metadata" do
    test "timeline has correct step order" do
      meta = CapitalCallWorkflow.__workflow_metadata__()

      assert meta.timeline == [
               :create_capital_call,
               :send_capital_call,
               :pay_items,
               :notify
             ]
    end
  end

  # ── create_capital_call/1 ──────────────────────────────────────

  describe "create_capital_call/1" do
    test "recovery mode: returns existing capital call when capital_call_id is provided" do
      ctx = %{
        execution_id: "exec-1",
        inputs: %{
          "capital_call_data" => %{
            "fund_id" => "fund-1",
            "capital_call_id" => "cc-123"
          }
        }
      }

      assert {:ok, %{capital_call_id: "cc-123", status: "DRAFT"}} =
               CapitalCallWorkflow.create_capital_call(ctx)
    end

    test "recovery mode: ignores empty string capital_call_id" do
      ctx = %{
        execution_id: "exec-1",
        inputs: %{
          "capital_call_data" => %{
            "fund_id" => "fund-1",
            "capital_call_id" => ""
          }
        }
      }

      # Falls through to API call — expects :httpc to fail
      assert_raise RuntimeError, ~r/API error/, fn ->
        CapitalCallWorkflow.create_capital_call(ctx)
      end
    end

    test "defaults for missing fields in capital_call_data" do
      ctx = %{
        execution_id: "exec-1",
        inputs: %{"capital_call_data" => %{"fund_id" => "fund-1"}}
      }

      # Falls through to API call — expects :httpc to fail
      assert_raise RuntimeError, ~r/API error/, fn ->
        CapitalCallWorkflow.create_capital_call(ctx)
      end
    end
  end

  # ── send_capital_call/2 ────────────────────────────────────────

  describe "send_capital_call/2" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      cc = %{capital_call_id: "cc-1", status: "DRAFT"}

      result = CapitalCallWorkflow.send_capital_call(ctx, {:ok, cc})

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "send_capital_call"
      assert data[:capital_call_id] == "cc-1"
      assert data[:status] == "DRAFT"
      assert data[:available_actions] == ["edit", "send"]
    end

    test "returns wait_for_approval with edit action" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "edit"}}}
      cc = %{capital_call_id: "cc-1", status: "DRAFT"}

      result = CapitalCallWorkflow.send_capital_call(ctx, {:ok, cc})

      assert {:wait_for_approval, [type: :manual], _data} = result
    end

    test "attempts send when action is send (needs HTTP mock)" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "send"}}}
      cc = %{capital_call_id: "cc-1", status: "DRAFT"}

      # Requires HTTP mock to test successfully
      assert_raise RuntimeError, ~r/API error/, fn ->
        CapitalCallWorkflow.send_capital_call(ctx, {:ok, cc})
      end
    end
  end

  # ── pay_items/3 ────────────────────────────────────────────────

  describe "pay_items/3" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      cc = %{capital_call_id: "cc-1", status: "SENT"}

      result = CapitalCallWorkflow.pay_items(ctx, {:ok, %{}}, {:ok, cc})

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "pay_items"
      assert data[:status] == "SENT"
      assert data[:available_actions] == ["pay"]
    end

    test "raises when pay action has no item_id" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "pay"}}}
      cc = %{capital_call_id: "cc-1", status: "SENT"}

      assert_raise RuntimeError, "item_id required for pay", fn ->
        CapitalCallWorkflow.pay_items(ctx, {:ok, %{}}, {:ok, cc})
      end
    end

    test "attempts pay with valid item_id (needs HTTP mock)" do
      ctx = %{
        inputs: %{
          "approve_response" => %{"action" => "pay", "item_id" => "item-1", "amount" => "5000"}
        }
      }

      cc = %{capital_call_id: "cc-1", status: "SENT"}

      # Requires HTTP mock
      assert_raise RuntimeError, ~r/API error/, fn ->
        CapitalCallWorkflow.pay_items(ctx, {:ok, %{}}, {:ok, cc})
      end
    end
  end

  # ── notify/4 ───────────────────────────────────────────────────

  describe "notify/4" do
    test "logs and passes through the capital call" do
      cc = %{capital_call_id: "cc-1", status: "PAID"}

      result = CapitalCallWorkflow.notify(%{}, {:ok, %{}}, {:ok, %{}}, {:ok, cc})
      assert {:ok, ^cc} = result
    end
  end

  # ── TODO: integration tests ────────────────────────────────────
  # - Happy path: create → send → pay_all → notify (requires :httpc mock)
  # - Recovery: re-run create after crash (requires :httpc mock)
  # - pay_items: partial pay → stay in SENT; all paid → advance to PAID (requires :httpc mock)
  # - send_capital_call with edit action → HTTP PUT then wfa (requires :httpc mock)
end
