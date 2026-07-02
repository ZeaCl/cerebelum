# Requirements — Python Distributed Workflow Execution

## Introduction
Permitir ejecución end-to-end de workflows definidos en Python vía gRPC, usando el mismo engine y event sourcing que los workflows Elixir nativos.

---

## Requirements

### R1: Engine dispatches blueprint steps to workers
**User Story:** As a Python developer, I want my workflow steps to be executed by registered Python workers, so that I don't need to recompile the Elixir engine.

#### Acceptance Criteria
1. WHEN the Engine reaches a step from a blueprint workflow THEN it SHALL delegate execution to `Cerebelum.WorkflowDelegatingWorkflow.execute_step/3`
2. WHEN `DelegatingWorkflow.execute_step` is called THEN it SHALL create a task in `TaskRouter` with the step name, inputs, and execution context
3. WHEN a task is enqueued THEN the Engine SHALL transition to a waiting state without blocking the process
4. IF no workers are registered for the step type THEN the Engine SHALL emit a `StepFailedEvent` with reason `:no_workers_available`

### R2: Workers poll and execute steps
**User Story:** As a Python worker, I want to poll for pending tasks and execute them, so that I can process workflow steps independently.

#### Acceptance Criteria
1. WHEN a worker calls `PollForTask` THEN `TaskRouter` SHALL return the highest-priority pending task
2. WHEN a worker completes a task THEN it SHALL call `SubmitResult` with the execution ID, task ID, and result
3. WHEN `SubmitResult` is received THEN the Engine SHALL be notified via `DelegatingWorkflow.notify_task_result/3`
4. IF a worker fails to report back within 5 minutes THEN the task SHALL be marked as `:timeout` and retried up to 3 times

### R3: Engine resumes execution after worker completion
**User Story:** As the system, I want the Engine to continue execution when a worker completes a step, so that workflows progress automatically.

#### Acceptance Criteria
1. WHEN `notify_task_result` is called THEN the Engine SHALL transition from waiting state to `:executing_step`
2. WHEN the result is `{:ok, value}` THEN the Engine SHALL store it and advance to the next step
3. WHEN the result is `{:error, reason}` THEN the Engine SHALL evaluate diverge rules from the blueprint
4. WHEN all steps complete THEN the Engine SHALL emit `ExecutionCompletedEvent` and store final results

### R4: Blueprint metadata drives step execution
**User Story:** As the system, I want the blueprint definition to fully describe the workflow structure, so that the Engine can execute it without Elixir modules.

#### Acceptance Criteria
1. WHEN `Data.new/3` is called with `Cerebelum.WorkflowDelegatingWorkflow` THEN it SHALL extract the timeline from the blueprint in the execution context
2. IF the blueprint context contains `:blueprint` key THEN `Metadata.extract/1` SHALL use the blueprint's timeline, diverges, and branches
3. WHERE a step is defined in the blueprint's timeline THEN `StepExecutor` SHALL call `DelegatingWorkflow.execute_step` instead of `apply(module, step_name, args)`
4. WHEN the blueprint validation succeeds THEN `ExecutionStartedEvent` SHALL include the blueprint version

### R5: Event sourcing parity with native workflows
**User Story:** As an operator, I want Python workflows to produce the same events as Elixir workflows, so that I have a complete audit trail.

#### Acceptance Criteria
1. WHEN a Python workflow executes THEN it SHALL emit `ExecutionStartedEvent`, `StepExecutedEvent`, and `ExecutionCompletedEvent` identical to native workflows
2. WHEN a step is delegated to a worker THEN it SHALL emit `StepStartedEvent` with `executor: :worker`
3. WHEN a worker returns a result THEN it SHALL emit `StepExecutedEvent` with `duration_ms` measured from task dispatch to result
4. IF the workflow fails THEN it SHALL emit `ExecutionFailedEvent` with partial results

### R6: Error handling and retry
**User Story:** As a developer, I want failed steps to be retried or routed via diverge rules, just like native workflows.

#### Acceptance Criteria
1. WHEN a worker returns `{:error, reason}` THEN the Engine SHALL check blueprint diverge rules for pattern matches
2. IF a diverge rule matches `{:error, reason} -> back_to(:step_name)` THEN the Engine SHALL jump to that step and re-execute
3. IF no diverge rules match THEN the Engine SHALL mark the execution as `:failed`
4. WHERE a task times out AFTER 3 retries THEN the task SHALL be sent to the Dead Letter Queue (DLQ)
