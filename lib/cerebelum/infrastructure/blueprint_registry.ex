defmodule Cerebelum.Infrastructure.BlueprintRegistry do
  @moduledoc """
  In-memory registry for workflow blueprints submitted via gRPC.

  Stores blueprint definitions so they can be used during workflow execution.
  Uses ETS for fast concurrent access.
  """

  use GenServer
  require Logger

  @table_name :blueprint_registry

  # Client API

  @doc """
  Start the BlueprintRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Store a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)
  - blueprint: Blueprint definition map

  ## Returns
  - :ok
  """
  def store_blueprint(workflow_module, blueprint) do
    GenServer.call(__MODULE__, {:store, workflow_module, blueprint})
  end

  @doc """
  Get a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)

  ## Returns
  - {:ok, blueprint} if found
  - {:error, :not_found} if not found
  """
  def get_blueprint(workflow_module) do
    case :ets.lookup(@table_name, workflow_module) do
      [{^workflow_module, blueprint}] ->
        {:ok, blueprint}
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Delete a blueprint definition.

  ## Parameters
  - workflow_module: Workflow module name (string)

  ## Returns
  - :ok
  """
  def delete_blueprint(workflow_module) do
    GenServer.call(__MODULE__, {:delete, workflow_module})
  end

  @doc """
  List all stored blueprints.

  ## Returns
  - [workflow_module]
  """
  def list_blueprints do
    :ets.match(@table_name, {:"$1", :_})
    |> Enum.map(fn [module] -> module end)
  end

  @doc """
  Get the source code of a single step within a workflow blueprint.

  ## Parameters
  - workflow_module: Workflow module name (string)
  - step_name: Step name (string)

  ## Returns
  - {:ok, step_code} if found
  - {:error, :not_found} if workflow not found
  - {:error, :step_not_found} if step not found in workflow
  """
  def get_step(workflow_module, step_name) do
    GenServer.call(__MODULE__, {:get_step, workflow_module, step_name})
  end

  @doc """
  Update the source code of a single step within a workflow blueprint.

  If the step does not exist, it is appended to the workflow.

  ## Parameters
  - workflow_module: Workflow module name (string)
  - step_name: Step name (string)
  - new_code: New source code for the step (including @step decorator)

  ## Returns
  - :ok if successful
  - {:error, :not_found} if workflow not found
  - {:error, :invalid_step_code} if code has no 'def' function
  """
  def update_step(workflow_module, step_name, new_code) do
    GenServer.call(__MODULE__, {:update_step, workflow_module, step_name, new_code})
  end

  @doc """
  Delete a single step from a workflow blueprint.

  ## Parameters
  - workflow_module: Workflow module name (string)
  - step_name: Step name (string)

  ## Returns
  - :ok if successful
  - {:error, :not_found} if workflow not found
  - {:error, :step_not_found} if step not found in workflow
  """
  def delete_step(workflow_module, step_name) do
    GenServer.call(__MODULE__, {:delete_step, workflow_module, step_name})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for blueprint storage
    # If table already exists from a previous crashed instance, reuse it
    try do
      :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    rescue
      ArgumentError -> :ok
    end

    Logger.info("BlueprintRegistry started")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:store, workflow_module, blueprint}, _from, state) do
    :ets.insert(@table_name, {workflow_module, blueprint})
    Logger.debug("Blueprint stored: #{workflow_module}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, workflow_module}, _from, state) do
    :ets.delete(@table_name, workflow_module)
    Logger.debug("Blueprint deleted: #{workflow_module}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_step, workflow_module, step_name}, _from, state) do
    reply =
      case :ets.lookup(@table_name, workflow_module) do
        [{^workflow_module, blueprint}] ->
          code = Map.get(blueprint, :code, "")
          {_header, step_blocks} = split_steps(code)

          case List.keyfind(step_blocks, step_name, 0) do
            {^step_name, step_code} ->
              {:ok, step_code}

            nil ->
              {:error, :step_not_found}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:update_step, workflow_module, step_name, new_code}, _from, state) do
    reply =
      case :ets.lookup(@table_name, workflow_module) do
        [{^workflow_module, blueprint}] ->
          with {:ok, _name} <- extract_step_name_from_code(new_code) do
            code = Map.get(blueprint, :code, "")
            {header, step_blocks} = split_steps(code)

            # Replace existing step or append new one
            updated_blocks =
              case List.keyfind(step_blocks, step_name, 0) do
                {^step_name, _old_code} ->
                  List.keyreplace(step_blocks, step_name, 0, {step_name, new_code})

                nil ->
                  step_blocks ++ [{step_name, new_code}]
              end

            # Update steps list in blueprint metadata
            step_names = Enum.map(updated_blocks, fn {name, _code} -> name end)
            new_full_code = rebuild_code(header, updated_blocks)

            updated_blueprint =
              blueprint
              |> Map.put(:code, new_full_code)
              |> Map.put(:steps, step_names)
              |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

            :ets.insert(@table_name, {workflow_module, updated_blueprint})
            Logger.debug("Step '#{step_name}' updated in blueprint: #{workflow_module}")
            :ok
          else
            {:error, _reason} -> {:error, :invalid_step_code}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete_step, workflow_module, step_name}, _from, state) do
    reply =
      case :ets.lookup(@table_name, workflow_module) do
        [{^workflow_module, blueprint}] ->
          code = Map.get(blueprint, :code, "")
          {header, step_blocks} = split_steps(code)

          case List.keyfind(step_blocks, step_name, 0) do
            {^step_name, _code} ->
              remaining_blocks = List.keydelete(step_blocks, step_name, 0)
              step_names = Enum.map(remaining_blocks, fn {name, _code} -> name end)
              new_full_code = rebuild_code(header, remaining_blocks)

              updated_blueprint =
                blueprint
                |> Map.put(:code, new_full_code)
                |> Map.put(:steps, step_names)
                |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

              :ets.insert(@table_name, {workflow_module, updated_blueprint})
              Logger.debug("Step '#{step_name}' deleted from blueprint: #{workflow_module}")
              :ok

            nil ->
              {:error, :step_not_found}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, reply, state}
  end

  # ── Private Helpers: Python code parsing ──────────

  @doc false
  @spec split_steps(String.t()) :: {String.t(), [{String.t(), String.t()}]}
  defp split_steps(code) when is_binary(code) do
    # Split by @step boundaries. Matches @step at the start of a line,
    # optionally indented, with optional parens: @step or @step()
    parts = String.split(code, ~r/(?:^|\n)(?=\s*@step\b)/m)

    case parts do
      [header | step_blocks] when header != "" or step_blocks != [] ->
        header = String.trim(header)

        steps =
          step_blocks
          |> Enum.map(fn block ->
            trimmed = String.trim(block)

            case extract_step_name_from_code(trimmed) do
              {:ok, name} -> {name, trimmed}
              {:error, _} -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {header, steps}

      [single] ->
        {String.trim(single), []}

      [] ->
        {"", []}
    end
  end

  @doc false
  @spec rebuild_code(String.t(), [{String.t(), String.t()}]) :: String.t()
  defp rebuild_code(header, step_blocks) do
    body =
      step_blocks
      |> Enum.map(fn {_name, block} -> block end)
      |> Enum.join("\n\n")

    if header == "" do
      body
    else
      header <> "\n\n" <> body
    end
  end

  @doc false
  @spec extract_step_name_from_code(String.t()) :: {:ok, String.t()} | {:error, :no_def_found}
  defp extract_step_name_from_code(code_block) do
    # Extract function name from: (async)? def function_name(
    case Regex.run(~r/(?:async\s+)?def\s+(\w+)\s*\(/, code_block) do
      [_, name] -> {:ok, name}
      nil -> {:error, :no_def_found}
    end
  end
end
