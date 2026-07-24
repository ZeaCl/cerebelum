defmodule Cerebelum.Infrastructure.BlueprintRegistryTest do
  use ExUnit.Case, async: false

  alias Cerebelum.Infrastructure.BlueprintRegistry

  @sample_code """
  from cerebelum import step, workflow

  @workflow
  def my_workflow(inputs):
      return inputs

  @step
  def validate_data(inputs, **kwargs):
      return {"ok": True}

  @step
  def create_fund(inputs, **kwargs):
      amount = inputs.get("amount", 0)
      return {"ok": {"fund_id": 42, "amount": amount}}
  """

  @workflow_name "test_step_crud"

  setup do
    # Clean up any leftover blueprint
    BlueprintRegistry.delete_blueprint(@workflow_name)

    :ok
  end

  describe "store_blueprint/2 and get_blueprint/1 (existing)" do
    test "stores and retrieves a blueprint" do
      blueprint = %{
        id: @workflow_name,
        name: @workflow_name,
        code: @sample_code,
        language: "python",
        steps: ["validate_data", "create_fund"]
      }

      :ok = BlueprintRegistry.store_blueprint(@workflow_name, blueprint)

      assert {:ok, stored} = BlueprintRegistry.get_blueprint(@workflow_name)
      assert stored.code == @sample_code
      assert stored.steps == ["validate_data", "create_fund"]
    end
  end

  describe "get_step/2" do
    setup do
      blueprint = %{
        id: @workflow_name,
        name: @workflow_name,
        code: @sample_code,
        language: "python",
        steps: ["validate_data", "create_fund"]
      }

      BlueprintRegistry.store_blueprint(@workflow_name, blueprint)
      :ok
    end

    test "returns step source code when step exists" do
      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "validate_data")

      assert code =~ "@step"
      assert code =~ "def validate_data"
      assert code =~ "{\"ok\": True}"
    end

    test "returns source code for second step" do
      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "create_fund")

      assert code =~ "@step"
      assert code =~ "def create_fund"
      assert code =~ "fund_id"
      assert code =~ "amount"
    end

    test "returns error when workflow does not exist" do
      assert {:error, :not_found} = BlueprintRegistry.get_step("nonexistent", "step_a")
    end

    test "returns error when step does not exist in workflow" do
      assert {:error, :step_not_found} = BlueprintRegistry.get_step(@workflow_name, "nonexistent_step")
    end
  end

  describe "update_step/3" do
    setup do
      blueprint = %{
        id: @workflow_name,
        name: @workflow_name,
        code: @sample_code,
        language: "python",
        steps: ["validate_data", "create_fund"]
      }

      BlueprintRegistry.store_blueprint(@workflow_name, blueprint)
      :ok
    end

    test "replaces an existing step" do
      new_code = """
      @step
      def validate_data(inputs, **kwargs):
          # Enhanced validation
          assert inputs.get("amount") > 0
          return {"ok": True}
      """

      assert :ok = BlueprintRegistry.update_step(@workflow_name, "validate_data", new_code)

      # Verify the step code was updated
      assert {:ok, updated_code} = BlueprintRegistry.get_step(@workflow_name, "validate_data")
      assert updated_code =~ "Enhanced validation"
      assert updated_code =~ "assert inputs"

      # Verify the other step is untouched
      assert {:ok, create_code} = BlueprintRegistry.get_step(@workflow_name, "create_fund")
      assert create_code =~ "fund_id"
      assert create_code =~ "42"

      # Verify the full blueprint is updated
      assert {:ok, bp} = BlueprintRegistry.get_blueprint(@workflow_name)
      assert bp.code =~ "Enhanced validation"
      assert bp.code =~ "fund_id"
      assert bp.steps == ["validate_data", "create_fund"]
    end

    test "appends a new step when step does not exist" do
      new_code = """
      @step
      def approve_fund(inputs, **kwargs):
          return {"ok": True}
      """

      assert :ok = BlueprintRegistry.update_step(@workflow_name, "approve_fund", new_code)

      # Verify the new step exists
      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "approve_fund")
      assert code =~ "def approve_fund"

      # Verify blueprint steps list is updated
      assert {:ok, bp} = BlueprintRegistry.get_blueprint(@workflow_name)
      assert "approve_fund" in bp.steps
      assert length(bp.steps) == 3
    end

    test "returns error when workflow does not exist" do
      assert {:error, :not_found} = BlueprintRegistry.update_step("nonexistent", "step_a", "@step\ndef step_a(inputs):\n    pass")
    end

    test "returns error when code has no def function" do
      assert {:error, :invalid_step_code} =
        BlueprintRegistry.update_step(@workflow_name, "step_a", "just some text")
    end

    test "works with async def (Python async functions)" do
      async_code = """
      @step
      async def fetch_data(inputs, **kwargs):
          return {"ok": True}
      """

      assert :ok = BlueprintRegistry.update_step(@workflow_name, "fetch_data", async_code)

      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "fetch_data")
      assert code =~ "async def fetch_data"
    end

    test "updates with @step decorator with parentheses" do
      step_with_parens = """
      @step()
      def process(inputs, **kwargs):
          return {"ok": True}
      """

      assert :ok = BlueprintRegistry.update_step(@workflow_name, "process", step_with_parens)
      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "process")
      assert code =~ "def process"
    end
  end

  describe "delete_step/2" do
    setup do
      blueprint = %{
        id: @workflow_name,
        name: @workflow_name,
        code: @sample_code,
        language: "python",
        steps: ["validate_data", "create_fund"]
      }

      BlueprintRegistry.store_blueprint(@workflow_name, blueprint)
      :ok
    end

    test "removes an existing step" do
      assert :ok = BlueprintRegistry.delete_step(@workflow_name, "validate_data")

      # Verify the step is gone
      assert {:error, :step_not_found} = BlueprintRegistry.get_step(@workflow_name, "validate_data")

      # Verify the other step remains
      assert {:ok, code} = BlueprintRegistry.get_step(@workflow_name, "create_fund")
      assert code =~ "def create_fund"

      # Verify blueprint metadata is updated
      assert {:ok, bp} = BlueprintRegistry.get_blueprint(@workflow_name)
      assert bp.steps == ["create_fund"]
      refute bp.code =~ "def validate_data"
    end

    test "returns error when workflow does not exist" do
      assert {:error, :not_found} = BlueprintRegistry.delete_step("nonexistent", "step_a")
    end

    test "returns error when step does not exist" do
      assert {:error, :step_not_found} = BlueprintRegistry.delete_step(@workflow_name, "nonexistent_step")
    end

    test "allows deleting the last step (empty workflow)" do
      # Delete first step
      BlueprintRegistry.delete_step(@workflow_name, "validate_data")
      # Delete last step
      assert :ok = BlueprintRegistry.delete_step(@workflow_name, "create_fund")

      assert {:ok, bp} = BlueprintRegistry.get_blueprint(@workflow_name)
      assert bp.steps == []
    end
  end

  describe "split_steps edge cases (via public API)" do
    test "handles code with only a workflow definition (no steps)" do
      code_no_steps = """
      from cerebelum import step, workflow

      @workflow
      def simple_workflow(inputs):
          return inputs
      """

      blueprint = %{
        id: "empty_workflow",
        name: "empty_workflow",
        code: code_no_steps,
        language: "python",
        steps: []
      }

      BlueprintRegistry.store_blueprint("empty_workflow", blueprint)

      # get_step should return step_not_found
      assert {:error, :step_not_found} = BlueprintRegistry.get_step("empty_workflow", "any_step")

      # Adding a step should work
      new_step = "@step\ndef first_step(inputs, **kwargs):\n    return {\"ok\": True}"

      assert :ok = BlueprintRegistry.update_step("empty_workflow", "first_step", new_step)
      assert {:ok, code} = BlueprintRegistry.get_step("empty_workflow", "first_step")
      assert code =~ "def first_step"
    end

    test "handles code with @step() parentheses syntax" do
      code_with_parens = """
      from cerebelum import step, workflow

      @workflow
      def my_workflow(inputs):
          return inputs

      @step()
      def step_a(inputs, **kwargs):
          pass

      @step()
      def step_b(inputs, **kwargs):
          pass
      """

      blueprint = %{
        id: "parens_workflow",
        name: "parens_workflow",
        code: code_with_parens,
        language: "python",
        steps: ["step_a", "step_b"]
      }

      BlueprintRegistry.store_blueprint("parens_workflow", blueprint)

      assert {:ok, code} = BlueprintRegistry.get_step("parens_workflow", "step_a")
      assert code =~ "@step()"
      assert code =~ "def step_a"

      assert {:ok, code} = BlueprintRegistry.get_step("parens_workflow", "step_b")
      assert code =~ "def step_b"
    end
  end
end
