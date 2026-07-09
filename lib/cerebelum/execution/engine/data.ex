defmodule Cerebelum.Execution.Engine.Data do
  @moduledoc """
  Data structure and helpers for execution engine state.

  This module defines the execution data structure and provides
  helper functions for manipulating it during workflow execution.
  """

  alias Cerebelum.Context
  alias Cerebelum.Workflow.Metadata
  alias Cerebelum.Execution.ResultsCache

  @type t :: %__MODULE__{
          context: Context.t(),
          workflow_metadata: map(),
          timeline: [atom()],
          results: ResultsCache.t(),
          current_step_index: non_neg_integer(),
          iteration: non_neg_integer(),
          event_version: non_neg_integer(),
          error: term() | nil,
          sleep_duration_ms: non_neg_integer() | nil,
          sleep_started_at: integer() | nil,
          sleep_step_name: atom() | nil,
          sleep_result: term() | nil,
          approval_type: atom() | nil,
          approval_data: map() | nil,
          approval_step_name: atom() | nil,
          approval_timeout_ms: non_neg_integer() | nil,
          approval_started_at: integer() | nil,
          blueprint: map() | nil,
          blueprint_name: String.t() | nil
        }

  defstruct [
    :context,
    :workflow_metadata,
    :timeline,
    results: %{},
    current_step_index: 0,
    iteration: 0,
    event_version: 0,
    error: nil,
    sleep_duration_ms: nil,
    sleep_started_at: nil,
    sleep_step_name: nil,
    sleep_result: nil,
    approval_type: nil,
    approval_data: nil,
    approval_step_name: nil,
    approval_timeout_ms: nil,
    approval_started_at: nil,
    blueprint: nil,
    blueprint_name: nil
  ]

  @doc """
  Creates initial execution data.

  ## Parameters

  - `workflow_module` - The workflow module to execute
  - `inputs` - User inputs for the workflow
  - `context_opts` - Options for context creation

  ## Examples

      data = Data.new(MyWorkflow, %{user_id: 123}, [])
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(workflow_module, inputs, context_opts) do
    workflow_metadata = Metadata.extract(workflow_module)
    context = Context.new(workflow_module, inputs, context_opts)

    # Extract blueprint info from opts (for distributed workflows)
    blueprint = context_opts[:blueprint]
    blueprint_name = context_opts[:blueprint_name] || context_opts[:workflow_module]

    %__MODULE__{
      context: context,
      workflow_metadata: workflow_metadata,
      timeline: if(blueprint, do: extract_blueprint_timeline(blueprint), else: workflow_metadata.timeline),
      results: %{},
      current_step_index: 0,
      iteration: 0,
      blueprint: blueprint,
      blueprint_name: blueprint_name
    }
  end

  defp extract_blueprint_timeline(blueprint) do
    definition = blueprint[:definition] || blueprint["definition"] || %{}
    timeline = definition[:timeline] || definition["timeline"] || []
    Enum.map(timeline, fn step ->
      name = step[:name] || step["name"]
      String.to_atom(to_string(name))
    end)
  end

  @doc """
  Gets the name of the current step based on the step index.

  ## Examples

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b, :c]}, current_step_index: 1}
      iex> Data.current_step_name(data)
      :b
  """
  @spec current_step_name(t()) :: atom() | nil
  def current_step_name(data) do
    Enum.at(data.timeline, data.current_step_index)
  end

  @doc """
  Stores the result of a step execution.

  ## Examples

      iex> data = %Data{results: %{}}
      iex> data = Data.store_result(data, :step1, {:ok, "result"})
      iex> data.results
      %{step1: {:ok, "result"}}
  """
  @spec store_result(t(), atom(), term()) :: t()
  def store_result(data, step_name, result) do
    %{data | results: ResultsCache.put(data.results, step_name, result)}
  end

  @doc """
  Advances to the next step in the timeline.

  ## Examples

      iex> data = %Data{current_step_index: 0}
      iex> data = Data.advance_step(data)
      iex> data.current_step_index
      1
  """
  @spec advance_step(t()) :: t()
  def advance_step(data) do
    %{data | current_step_index: data.current_step_index + 1}
  end

  @doc """
  Updates the current step in the context.

  ## Examples

      iex> data = %Data{context: ctx}
      iex> data = Data.update_context_step(data, :new_step)
      iex> data.context.current_step
      :new_step
  """
  @spec update_context_step(t(), atom()) :: t()
  def update_context_step(data, step_name) do
    updated_context = Context.update_step(data.context, step_name)
    %{data | context: updated_context}
  end

  @doc """
  Marks the execution as failed with an ErrorInfo struct.

  ## Examples

      alias Cerebelum.Execution.ErrorInfo

      iex> data = %Data{error: nil}
      iex> error_info = ErrorInfo.from_timeout(:step1, "exec-123")
      iex> data = Data.mark_failed(data, error_info)
      iex> data.error.kind
      :timeout
  """
  @spec mark_failed(t(), Cerebelum.Execution.ErrorInfo.t()) :: t()
  def mark_failed(data, %Cerebelum.Execution.ErrorInfo{} = error_info) do
    %{data | error: error_info}
  end

  @doc """
  Checks if the workflow execution has finished (all steps executed).

  ## Examples

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b]}, current_step_index: 2}
      iex> Data.finished?(data)
      true

      iex> data = %Data{workflow_metadata: %{timeline: [:a, :b]}, current_step_index: 1}
      iex> Data.finished?(data)
      false
  """
  @spec finished?(t()) :: boolean()
  def finished?(data) do
    data.current_step_index >= length(data.timeline)
  end

  @doc """
  Updates the current step index.

  ## Examples

      iex> data = %Data{current_step_index: 0}
      iex> data = Data.update_current_step_index(data, 5)
      iex> data.current_step_index
      5
  """
  @spec update_current_step_index(t(), non_neg_integer()) :: t()
  def update_current_step_index(data, new_index) do
    %{data | current_step_index: new_index}
  end

  @doc """
  Updates the results cache.

  ## Examples

      iex> data = %Data{results: %{}}
      iex> data = Data.update_results(data, %{step1: :result1})
      iex> data.results
      %{step1: :result1}
  """
  @spec update_results(t(), map()) :: t()
  def update_results(data, new_results) do
    %{data | results: new_results}
  end

  @doc """
  Increments the iteration counter (for loop detection).

  ## Examples

      iex> data = %Data{iteration: 0}
      iex> data = Data.increment_iteration(data)
      iex> data.iteration
      1
  """
  @spec increment_iteration(t()) :: t()
  def increment_iteration(data) do
    %{data | iteration: data.iteration + 1}
  end

  @doc """
  Increments the event version counter and returns the new version.

  ## Examples

      iex> data = %Data{event_version: 0}
      iex> {version, data} = Data.next_event_version(data)
      iex> version
      0
      iex> data.event_version
      1
  """
  @spec next_event_version(t()) :: {non_neg_integer(), t()}
  def next_event_version(data) do
    current_version = data.event_version
    {current_version, %{data | event_version: current_version + 1}}
  end

  @doc """
  Builds a status map for the current execution state.

  ## Examples

      data = Data.new(MyWorkflow, %{}, [])
      status = Data.build_status(data, :executing_step)
  """
  @spec build_status(t(), atom()) :: map()
  def build_status(data, state) do
    timeline_length = length(data.timeline)

    error_info =
      if data.error do
        %{
          error: Cerebelum.Execution.ErrorInfo.to_map(data.error),
          error_message: Cerebelum.Execution.ErrorInfo.format(data.error)
        }
      else
        %{error: nil, error_message: nil}
      end

    Map.merge(
      %{
        state: state,
        execution_id: data.context.execution_id,
        workflow_module: data.context.workflow_module,
        current_step: current_step_name(data),
        timeline_progress: "#{data.current_step_index}/#{timeline_length}",
        completed_steps: data.current_step_index,
        total_steps: timeline_length,
        results: json_safe_results(data.results),
        context: data.context,
        iteration: data.iteration
      },
      error_info
    )
  end

  @doc """
  Converts results map to JSON-safe format.

  Tuples like `{:waiting_for_approval, data}` or `{:sleep, duration, data}`
  are converted to maps that Jason can serialize.
  """
  @spec json_safe_results(map()) :: map()
  def json_safe_results(results) when is_map(results) do
    Map.new(results, fn {step_name, value} ->
      {step_name, json_safe_value(value)}
    end)
  end

  defp json_safe_value({:waiting_for_approval, data}) do
    %{status: "waiting_for_approval", data: data}
  end

  defp json_safe_value({:sleep, duration_ms, data}) do
    %{status: "sleep", duration_ms: duration_ms, data: data}
  end

  defp json_safe_value({:ok, value}) do
    json_safe_value(value)
  end

  defp json_safe_value({:error, reason}) do
    %{status: "error", reason: reason}
  end

  defp json_safe_value(value), do: value
end
