defmodule Cerebelum.Execution.PythonStepCompletedEvent do
  @moduledoc """
  Event emitted when a Python worker completes a step.

  Stored in Cerebelum EventStore for state reconstruction.
  """
  defstruct [
    :execution_id,
    :step_name,
    :step_label,
    :status,      # "ok" | "waiting_for_approval" | "validation_error" | "failed"
    :result,      # step return value (form data, errors, etc.)
    :worker_id,
    :workflow_id,
    :timestamp
  ]
end
