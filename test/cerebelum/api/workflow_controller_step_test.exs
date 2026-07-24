defmodule Cerebelum.API.WorkflowControllerStepTest do
  use ExUnit.Case, async: false

  alias Cerebelum.API.WorkflowController
  alias Cerebelum.Infrastructure.BlueprintRegistry
  import Plug.Conn
  import Phoenix.ConnTest

  @workflow_name "test_step_crud_api"
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

  setup do
    # Clean up
    BlueprintRegistry.delete_blueprint(@workflow_name)

    # Deploy a test blueprint
    blueprint = %{
      id: @workflow_name,
      name: @workflow_name,
      code: @sample_code,
      language: "python",
      steps: ["validate_data", "create_fund"]
    }

    BlueprintRegistry.store_blueprint(@workflow_name, blueprint)

    conn =
      build_conn()
      |> put_private(:phoenix_endpoint, Cerebelum.API.Endpoint)

    {:ok, conn: conn}
  end

  describe "GET /api/v1/workflows/:id/steps" do
    test "lists all steps with metadata", %{conn: conn} do
      conn = WorkflowController.steps(conn, %{"id" => @workflow_name})

      assert json_response(conn, 200)["data"] == %{
               "workflow" => @workflow_name,
               "total" => 2,
               "steps" => [
                 %{"name" => "validate_data", "position" => 0, "has_code" => true},
                 %{"name" => "create_fund", "position" => 1, "has_code" => true}
               ]
             }
    end

    test "returns 404 for non-existent workflow", %{conn: conn} do
      conn = WorkflowController.steps(conn, %{"id" => "nonexistent"})

      assert json_response(conn, 404)["error"] == "Workflow not found"
    end
  end

  describe "GET /api/v1/workflows/:id/steps/:name" do
    test "returns step source code", %{conn: conn} do
      conn =
        WorkflowController.show_step(conn, %{
          "id" => @workflow_name,
          "name" => "validate_data"
        })

      response = json_response(conn, 200)
      data = response["data"]

      assert data["name"] == "validate_data"
      assert data["workflow"] == @workflow_name
      assert data["code"] =~ "@step"
      assert data["code"] =~ "def validate_data"
    end

    test "returns 404 for non-existent workflow", %{conn: conn} do
      conn =
        WorkflowController.show_step(conn, %{
          "id" => "nonexistent",
          "name" => "step_a"
        })

      assert json_response(conn, 404)["error"] == "Workflow not found"
    end

    test "returns 404 for non-existent step", %{conn: conn} do
      conn =
        WorkflowController.show_step(conn, %{
          "id" => @workflow_name,
          "name" => "nonexistent_step"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end

  describe "PUT /api/v1/workflows/:id/steps/:name" do
    test "updates an existing step", %{conn: conn} do
      new_code = """
      @step
      def validate_data(inputs, **kwargs):
          # Enhanced validation
          assert inputs.get("amount") > 0
          return {"ok": True}
      """

      conn =
        WorkflowController.update_step(conn, %{
          "id" => @workflow_name,
          "name" => "validate_data",
          "code" => new_code
        })

      response = json_response(conn, 200)
      assert response["data"]["updated"] == true
      assert response["data"]["name"] == "validate_data"
    end

    test "creates a new step when it does not exist", %{conn: conn} do
      new_code = """
      @step
      def approve_fund(inputs, **kwargs):
          return {"ok": True}
      """

      conn =
        WorkflowController.update_step(conn, %{
          "id" => @workflow_name,
          "name" => "approve_fund",
          "code" => new_code
        })

      assert json_response(conn, 200)["data"]["updated"] == true

      # Verify it was added — need fresh conn since previous one is already sent
      fresh_conn =
        build_conn()
        |> put_private(:phoenix_endpoint, Cerebelum.API.Endpoint)

      conn2 = WorkflowController.steps(fresh_conn, %{"id" => @workflow_name})
      assert json_response(conn2, 200)["data"]["total"] == 3
    end

    test "returns 400 when code field is missing", %{conn: conn} do
      conn =
        WorkflowController.update_step(conn, %{
          "id" => @workflow_name,
          "name" => "validate_data"
        })

      assert json_response(conn, 400)["error"] =~ "Missing 'code' field"
    end

    test "returns 422 when code has no function definition", %{conn: conn} do
      conn =
        WorkflowController.update_step(conn, %{
          "id" => @workflow_name,
          "name" => "validate_data",
          "code" => "just some text without a function"
        })

      assert json_response(conn, 422)["error"] =~ "Invalid step code"
    end

    test "returns 404 for non-existent workflow", %{conn: conn} do
      conn =
        WorkflowController.update_step(conn, %{
          "id" => "nonexistent",
          "name" => "step_a",
          "code" => "@step\ndef step_a(inputs, **kwargs):\n    pass"
        })

      assert json_response(conn, 404)["error"] == "Workflow not found"
    end
  end

  describe "DELETE /api/v1/workflows/:id/steps/:name" do
    test "deletes an existing step", %{conn: conn} do
      conn =
        WorkflowController.delete_step(conn, %{
          "id" => @workflow_name,
          "name" => "validate_data"
        })

      response = json_response(conn, 200)
      assert response["data"]["deleted"] == true
      assert response["data"]["name"] == "validate_data"

      # Verify it's gone — need fresh conn since previous one is already sent
      fresh_conn =
        build_conn()
        |> put_private(:phoenix_endpoint, Cerebelum.API.Endpoint)

      conn2 =
        WorkflowController.show_step(fresh_conn, %{
          "id" => @workflow_name,
          "name" => "validate_data"
        })

      assert json_response(conn2, 404)["error"] =~ "not found"
    end

    test "returns 404 for non-existent workflow", %{conn: conn} do
      conn =
        WorkflowController.delete_step(conn, %{
          "id" => "nonexistent",
          "name" => "step_a"
        })

      assert json_response(conn, 404)["error"] == "Workflow not found"
    end

    test "returns 404 for non-existent step", %{conn: conn} do
      conn =
        WorkflowController.delete_step(conn, %{
          "id" => @workflow_name,
          "name" => "nonexistent_step"
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end
  end
end
