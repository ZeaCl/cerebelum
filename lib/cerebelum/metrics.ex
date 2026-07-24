defmodule Cerebelum.Metrics do
  @moduledoc """
  Custom PromEx plugin for Cerebelum business metrics.

  Wires telemetry events emitted by the execution engine, controllers,
  and infrastructure modules into Prometheus metrics.
  """

  use PromEx.Plugin

  alias PromEx.MetricTypes.Event

  @impl true
  def event_metrics(_opts) do
    [
      # ── Workflow Executions ──────────────────────────
      Event.build(
        :cerebelum_execution_event_metrics,
        [
          counter("cerebelum.executions.started.count",
            event_name: [:cerebelum, :executions, :started],
            measurement: :count,
            description: "Total workflow executions started",
            tags: [:blueprint_name]
          ),
          counter("cerebelum.executions.completed.count",
            event_name: [:cerebelum, :executions, :completed],
            measurement: :count,
            description: "Total workflow executions completed successfully"
          ),
          counter("cerebelum.executions.failed.count",
            event_name: [:cerebelum, :executions, :failed],
            measurement: :count,
            description: "Total workflow executions failed",
            tags: [:error_kind]
          )
        ]
      ),

      # ── Steps ────────────────────────────────────────
      Event.build(
        :cerebelum_step_event_metrics,
        [
          counter("cerebelum.steps.executed.count",
            event_name: [:cerebelum, :steps, :executed],
            measurement: :count,
            description: "Total steps executed successfully",
            tags: [:step_name]
          ),
          counter("cerebelum.steps.failed.count",
            event_name: [:cerebelum, :steps, :failed],
            measurement: :count,
            description: "Total steps failed",
            tags: [:step_name]
          )
        ]
      ),

      # ── Sleep & HITL ─────────────────────────────────
      Event.build(
        :cerebelum_sleep_approval_event_metrics,
        [
          counter("cerebelum.workflows.sleep.entered.count",
            event_name: [:cerebelum, :workflows, :sleep, :entered],
            measurement: :count,
            description: "Total times workflows entered sleep state",
            tags: [:step_name]
          ),
          counter("cerebelum.workflows.sleep.exited.count",
            event_name: [:cerebelum, :workflows, :sleep, :exited],
            measurement: :count,
            description: "Total times workflows exited sleep state"
          ),
          counter("cerebelum.workflows.approval.entered.count",
            event_name: [:cerebelum, :workflows, :approval, :entered],
            measurement: :count,
            description: "Total HITL approval requests",
            tags: [:approval_type]
          ),
          counter("cerebelum.workflows.approval.exited.count",
            event_name: [:cerebelum, :workflows, :approval, :exited],
            measurement: :count,
            description: "Total HITL approval resolutions",
            tags: [:outcome]
          )
        ]
      ),

      # ── Blueprints ───────────────────────────────────
      Event.build(
        :cerebelum_blueprint_event_metrics,
        [
          counter("cerebelum.blueprints.deployed.count",
            event_name: [:cerebelum, :blueprints, :deployed],
            measurement: :count,
            description: "Total blueprints deployed",
            tags: [:language]
          ),
          counter("cerebelum.blueprints.steps.updated.count",
            event_name: [:cerebelum, :blueprints, :steps, :updated],
            measurement: :count,
            description: "Total step updates",
            tags: [:workflow]
          ),
          counter("cerebelum.blueprints.steps.deleted.count",
            event_name: [:cerebelum, :blueprints, :steps, :deleted],
            measurement: :count,
            description: "Total step deletions",
            tags: [:workflow]
          )
        ]
      ),

      # ── Workers ──────────────────────────────────────
      Event.build(
        :cerebelum_worker_event_metrics,
        [
          last_value("cerebelum.workers.connected.count",
            event_name: [:cerebelum, :workers, :connected],
            measurement: :count,
            description: "Number of workers currently connected",
            tags: [:worker_id, :language]
          ),
          last_value("cerebelum.workers.disconnected.count",
            event_name: [:cerebelum, :workers, :disconnected],
            measurement: :count,
            description: "Number of workers disconnected (cumulative)",
            tags: [:worker_id, :reason]
          )
        ]
      ),

      # ── Tasks ────────────────────────────────────────
      Event.build(
        :cerebelum_task_event_metrics,
        [
          last_value("cerebelum.tasks.queued.count",
            event_name: [:cerebelum, :tasks, :queued],
            measurement: :count,
            description: "Current number of tasks in queue",
            tags: [:step_name]
          ),
          last_value("cerebelum.tasks.completed.count",
            event_name: [:cerebelum, :tasks, :completed],
            measurement: :count,
            description: "Current number of tasks completed",
            tags: [:step_name]
          )
        ]
      )
    ]
  end
end
