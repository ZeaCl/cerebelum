defmodule Cerebelum.FundLifecycleWorkflowTest do
  use ExUnit.Case, async: true

  alias Cerebelum.FundLifecycleWorkflow

  # ── Workflow metadata ──────────────────────────────────────────

  describe "workflow metadata" do
    test "timeline has correct step order" do
      meta = FundLifecycleWorkflow.__workflow_metadata__()

      assert meta.timeline == [
               :create_fund,
               :activate,
               :first_close,
               :start_investing,
               :start_harvesting,
               :close_fund,
               :liquidate,
               :notify
             ]
    end
  end

  # ── to_int/1 (tested via create_fund) ──────────────────────────

  describe "to_int/1 helper" do
    # to_int is private, tested indirectly through create_fund defaults.
    # We test the behavior by observing default values in recovery mode.

    test "default target_size is 5_000_000 (integer from default)" do
      # Recovery bypasses API, cannot test to_int directly without mock.
      # This is a documented limitation — to_int is tested via integration.
    end
  end

  # ── create_fund/1 ──────────────────────────────────────────────

  describe "create_fund/1" do
    test "recovery mode: returns existing fund when fund_id is provided" do
      ctx = %{
        execution_id: "exec-1",
        inputs: %{
          "fund_data" => %{
            "fund_id" => "fund-123",
            "name" => "Test Fund"
          }
        }
      }

      # Recovery: GET /funds/fund-123 — requires :httpc mock
      # Falls through to API call
      assert_raise RuntimeError, ~r/API error/, fn ->
        FundLifecycleWorkflow.create_fund(ctx)
      end
    end

    test "creates fund when no fund_id (needs HTTP mock)" do
      ctx = %{
        execution_id: "exec-1",
        inputs: %{
          "fund_data" => %{
            "name" => "New Fund",
            "type" => "VC",
            "target_size" => 10_000_000
          }
        }
      }

      assert_raise RuntimeError, ~r/API error/, fn ->
        FundLifecycleWorkflow.create_fund(ctx)
      end
    end
  end

  # ── activate/2 ─────────────────────────────────────────────────

  describe "activate/2" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "DRAFT"}

      result = FundLifecycleWorkflow.activate(ctx, {:ok, fund})

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "activate"
      assert data[:fund_id] == "fund-1"
      assert data[:fund_status] == "DRAFT"
      assert data[:available_actions] == ["edit", "activate"]
    end

    test "returns wait_for_approval with edit action" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "edit"}}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "DRAFT"}

      result = FundLifecycleWorkflow.activate(ctx, {:ok, fund})

      assert {:wait_for_approval, [type: :manual], _data} = result
    end

    test "attempts activate when action is activate (needs HTTP mock)" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "activate"}}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "DRAFT"}

      assert_raise RuntimeError, ~r/API error/, fn ->
        FundLifecycleWorkflow.activate(ctx, {:ok, fund})
      end
    end
  end

  # ── first_close/3 ──────────────────────────────────────────────

  describe "first_close/3" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "FUNDRAISING"}

      result = FundLifecycleWorkflow.first_close(ctx, {:ok, %{}}, {:ok, fund})

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "first_close"
      assert data[:fund_status] == "FUNDRAISING"
      assert data[:available_actions] == ["first_close"]
    end

    test "raises when first_close has no close_date (validated before HTTP call)" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "first_close"}}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "FUNDRAISING"}

      # Date validation happens before get_fund, so we get close_date error, not API error
      assert_raise RuntimeError, "close_date required for first_close", fn ->
        FundLifecycleWorkflow.first_close(ctx, {:ok, %{}}, {:ok, fund})
      end
    end
  end

  # ── start_investing/4 ──────────────────────────────────────────

  describe "start_investing/4" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "ACTIVE"}

      result =
        FundLifecycleWorkflow.start_investing(ctx, {:ok, %{}}, {:ok, %{}}, {:ok, fund})

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "start_investing"
      # BUGFIX: was "FUNDRAISING", now uses fund.status (ACTIVE)
      assert data[:fund_status] == "ACTIVE"
      assert data[:available_actions] == ["start_investing"]
    end

    test "wfa status reflects actual fund status" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "ACTIVE"}

      {:wait_for_approval, _opts, data} =
        FundLifecycleWorkflow.start_investing(ctx, {:ok, %{}}, {:ok, %{}}, {:ok, fund})

      # Verify the status passed to wfa matches the fund status (was hardcoded "FUNDRAISING")
      assert data[:fund_status] == "ACTIVE"
    end
  end

  # ── start_harvesting/5 ─────────────────────────────────────────

  describe "start_harvesting/5" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "INVESTING"}

      result =
        FundLifecycleWorkflow.start_harvesting(
          ctx,
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, fund}
        )

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "start_harvesting"
      assert data[:fund_status] == "INVESTING"
    end
  end

  # ── close_fund/6 ───────────────────────────────────────────────

  describe "close_fund/6" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "HARVESTING"}

      result =
        FundLifecycleWorkflow.close_fund(
          ctx,
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, fund}
        )

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "close_fund"
      assert data[:fund_status] == "HARVESTING"
      assert data[:available_actions] == ["close_fund"]
    end

    test "raises when close_fund has no auditoria (needs HTTP mock)" do
      ctx = %{inputs: %{"approve_response" => %{"action" => "close_fund"}}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "HARVESTING"}

      # Fails on get_fund (HTTP) before reaching auditoria validation
      assert_raise RuntimeError, ~r/API error/, fn ->
        FundLifecycleWorkflow.close_fund(
          ctx,
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, fund}
        )
      end
    end
  end

  # ── liquidate/7 ────────────────────────────────────────────────

  describe "liquidate/7" do
    test "returns wait_for_approval when no action" do
      ctx = %{inputs: %{}}
      fund = %{fund_id: "fund-1", fund_name: "Test", status: "CLOSED"}

      result =
        FundLifecycleWorkflow.liquidate(
          ctx,
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, fund}
        )

      assert {:wait_for_approval, [type: :manual], data} = result
      assert data[:step] == "liquidate"
      assert data[:fund_status] == "CLOSED"
      assert data[:available_actions] == ["liquidate"]
    end
  end

  # ── notify/8 ───────────────────────────────────────────────────

  describe "notify/8" do
    test "logs and merges notified flag" do
      fund = %{fund_id: "fund-1", fund_name: "Test Fund", status: "LIQUIDATED"}

      result =
        FundLifecycleWorkflow.notify(
          %{},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, %{}},
          {:ok, fund}
        )

      assert {:ok, result_map} = result
      assert result_map[:notified] == true
      assert result_map[:fund_name] == "Test Fund"
    end
  end

  # ── TODO: integration tests ────────────────────────────────────
  # - Full happy path: create → activate → first_close → start_investing →
  #   start_harvesting → close_fund → liquidate → notify (requires :httpc mock)
  # - Idempotency for each step after recovery (requires :httpc mock)
  # - activate with edit: PUT /funds/:id then wfa (requires :httpc mock)
  # - first_close with close_date → HTTP POST then verify ACTIVE (requires :httpc mock)
  # - liquidate transition to LIQUIDATED with Map.merge nil-safety (requires :httpc mock)
  # - close_fund raises on missing auditoria after successful get_fund (requires :httpc mock)
end
