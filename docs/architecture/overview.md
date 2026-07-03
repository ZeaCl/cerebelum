# Architecture Overview

Cerebelum follows Clean Architecture principles with four layers.

## Layers

```
┌─────────────────────────────────────┐
│     Presentation Layer              │  ← REST API (Phoenix), gRPC
├─────────────────────────────────────┤
│     Infrastructure Layer            │  ← EventStore, Worker Registry, DLQ
├─────────────────────────────────────┤
│     Application Layer               │  ← Use cases, execution orchestration
├─────────────────────────────────────┤
│     Domain Layer                    │  ← Workflow DSL, entities, rules
└─────────────────────────────────────┘
```

## Key Components

### Domain Layer
- **Workflow DSL** — Macro-based workflow definition
- **Step Executor** — Individual step execution with dependency injection
- **Branch/Diverge Handlers** — Conditional routing and error handling
- **Context** — Immutable execution context (inputs, organization_id, state)

### Application Layer
- **Execution Engine** — Main orchestrator (GenServer)
- **Parallel Executor** — Concurrent step execution
- **State Reconstructor** — Replay execution from events
- **Resurrector** — Wake hibernated workflows

### Infrastructure Layer
- **EventStore** — Append-only event log with batching (640K+ events/sec)
- **Worker Registry** — Python/TypeScript worker pool management
- **Task Router** — Distribute work to SDK workers
- **DLQ** — Dead Letter Queue for failed steps
- **Blueprint Registry** — Workflow definition storage

### Presentation Layer
- **REST API** — Phoenix endpoints with JWT auth + rate limiting
- **gRPC Server** — Multi-language worker communication (protobuf)
- **JWTAuth Plug** — Thalamus JWT validation
- **Rate Limiter Plug** — Per-organization request throttling

## Supervision Tree

```
Cerebelum.Application
├── Cerebelum.Repo
├── Cerebelum.API.Endpoint          ← REST API
├── Cerebelum.EventStore
├── Cerebelum.Workflow.Registry     ← Workflow definitions
├── Cerebelum.Execution.Registry    ← Active executions
├── Cerebelum.Execution.Supervisor  ← Execution processes
├── Cerebelum.Infrastructure.WorkerRegistry    ← Python workers
├── Cerebelum.Infrastructure.TaskRouter        ← Task distribution
├── Cerebelum.Infrastructure.BlueprintRegistry ← Blueprint storage
└── Cerebelum.Infrastructure.ExecutionStateManager
```

## Events

18 event types form the event sourcing log:

- **Workflow**: ExecutionStarted, ExecutionCompleted, ExecutionFailed
- **Step**: StepStarted, StepCompleted, StepFailed, StepSkipped, StepRetried
- **Branch**: BranchEvaluated, BranchTaken
- **Diverge**: DivergeTriggered, DivergeResolved
- **Flow**: BackToJumped, SkipToJumped, ContinueTriggered
- **Approval**: ApprovalRequested, ApprovalGranted, ApprovalDenied
- **Checkpoint**: CheckpointCreated

## Resilience

- **Process supervision** — OTP supervisors restart failed processes
- **Event sourcing** — Complete audit trail enables time-travel debugging
- **Workflow resurrection** — Hibernated workflows survive restarts
- **DLQ** — Failed steps moved to Dead Letter Queue after max retries
- **Optimistic concurrency** — Version numbers prevent event conflicts
