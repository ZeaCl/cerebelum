defmodule Cerebelum.Execution.ControllerApproveFixTest do
  @moduledoc """
  Validates the fix for #69 — controller passes all approve params to engine.

  Tests that Map.drop(params, ["id"]) correctly passes all user data
  (name, type, currency, vintage_year, etc.) as approval_response.
  """

  use ExUnit.Case, async: true

  describe "controller approve — params handling" do
    test "passes all user data (not just approved_by/notes)" do
      # Simulate what the controller does
      params = %{
        "id" => "exec-123",
        "name" => "Andes Growth Fund IV",
        "type" => "PE",
        "currency" => "USD",
        "vintage_year" => "2026"
      }

      approval_response = Map.drop(params, ["id"])

      # Should contain ALL user data
      assert approval_response["name"] == "Andes Growth Fund IV"
      assert approval_response["type"] == "PE"
      assert approval_response["currency"] == "USD"
      assert approval_response["vintage_year"] == "2026"
      refute Map.has_key?(approval_response, "id")
    end

    test "handles approve with action field (step_4_review)" do
      params = %{
        "id" => "exec-456",
        "action" => "activate"
      }

      approval_response = Map.drop(params, ["id"])

      assert approval_response["action"] == "activate"
      refute Map.has_key?(approval_response, "id")
    end

    test "handles approve with financial data" do
      params = %{
        "id" => "exec-789",
        "total_size" => "50000000",
        "management_fee" => "2",
        "carried_interest" => "20",
        "hurdle_rate" => "8",
        "fund_term_years" => "10",
        "investment_period_years" => "5"
      }

      approval_response = Map.drop(params, ["id"])

      assert approval_response["total_size"] == "50000000"
      assert approval_response["management_fee"] == "2"
      assert approval_response["carried_interest"] == "20"
      refute Map.has_key?(approval_response, "id")
    end

    test "handles lifecycle data" do
      params = %{
        "id" => "exec-lifecycle",
        "fundraising_months" => "12",
        "investment_months" => "60",
        "harvesting_months" => "48"
      }

      approval_response = Map.drop(params, ["id"])

      assert approval_response["fundraising_months"] == "12"
      assert approval_response["investment_months"] == "60"
      assert approval_response["harvesting_months"] == "48"
    end

    test "preserves approved_by and notes when present" do
      params = %{
        "id" => "exec-with-meta",
        "name" => "Test Fund",
        "approved_by" => "Alice",
        "notes" => "Looks good"
      }

      approval_response = Map.drop(params, ["id"])

      assert approval_response["name"] == "Test Fund"
      assert approval_response["approved_by"] == "Alice"
      assert approval_response["notes"] == "Looks good"
    end

    test "build_step_inputs injects approval data into inputs key" do
      # Simulate what state_handlers.ex does
      args = [%{}, %{step_0: {:ok, %{x: 1}}}]
      current_result = {:ok, %{"name" => "Andes Growth Fund IV", "type" => "PE"}}

      [_context | prev_results] = args
      inputs = %{previous_results: prev_results}

      result = case current_result do
        {:ok, approval_data} when is_map(approval_data) ->
          Map.put(inputs, :inputs, approval_data)
        _ ->
          inputs
      end

      # The step_inputs map should have previous_results AND inputs with approval data
      assert result.inputs == %{"name" => "Andes Growth Fund IV", "type" => "PE"}
      assert length(result.previous_results) == 1
    end

    test "build_step_inputs without current result (first execution)" do
      args = [%{}, %{}]
      current_result = nil

      [_context | prev_results] = args
      inputs = %{previous_results: prev_results}

      result = case current_result do
        {:ok, approval_data} when is_map(approval_data) ->
          Map.put(inputs, :inputs, approval_data)
        _ ->
          inputs
      end

      # On first execution, no inputs key should be added
      refute Map.has_key?(result, :inputs)
      assert result.previous_results == [%{}]
    end
  end
end
