# Architecture Overview

Cerebelum follows **Clean Architecture** with four layers and strict dependency inversion. It's built on Elixir/OTP for fault tolerance, uses event sourcing for complete auditability, and supports multi-language workers via gRPC.

---

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│  Presentation Layer                                        │
│  • REST API (Phoenix + Bandit)                             │
│  • gRPC Server (mTLS)                                      │
│  • Plugs: JwtAuth, RateLimiter                             │
└──────────────────────┬──────────────────────────────────────┘
                       │ depends on ↓
┌──────────────────────▼──────────────────────────────────────┐
│  Application Layer                                         │
│  • Execution Engine (gen_statem)                           │
│  • Step Executor (dependency injection)                    │
│  • Branch / Diverge / Jump Handlers                        │
│  • Parallel Executor                                       │
│  • State Reconstructor (event replay)                      │
│  • Resurrector (crash recovery)                            │
│  • Approval (human-in-the-loop)                            │
└──────────────────────┬──────────────────────────────────────┘
                       │ depends on ↓
┌──────────────────────▼──────────────────────────────────────┐
│  Domain Layer                                              │
│  • Workflow DSL (macros)                                   │
│  • Workflow Validator (compile-time)                       │
│  • 18 Domain Events (immutable, append-only)               │
│  • Flow Actions (continue, back_to, skip_to, failed)       │
│  • Context (immutable)                                     │
│  • Pattern Matcher (diverge)                               │
│  • Cond Evaluator (branch)                                 │
└──────────────────────┬──────────────────────────────────────┘
                       │ implemented by ↑
┌──────────────────────▼──────────────────────────────────────┐
│  Infrastructure Layer                                      │
│  • EventStore (PostgreSQL, 640K+ events/sec)               │
│  • Worker Registry (Python/TypeScript workers)             │
│  • Task Router (gRPC dispatch)                             │
│  • Blueprint Registry (workflow definitions)               │
│  • DLQ (Dead Letter Queue)                                 │
│  • Workflow Scheduler (resurrection loop)                  │
│  • Execution State Manager                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Supervision Tree

```
Cerebelum.Application (OTP Application)
│
├── Cerebelum.Repo                          ← Ecto database
├── Cerebelum.API.Endpoint                  ← REST API (Phoenix/Bandit)
├── Cerebelum.EventStore                    ← Append-only event log
├── Cerebelum.Workflow.Registry             ← Compiled workflow modules
├── Cerebelum.Execution.Registry            ← Active execution processes
├── Cerebelum.Execution.Supervisor          ← DynamicSupervisor for engines
│   └── Engine (gen_statem) per execution   ← State machine per workflow
├── Cerebelum.Infrastructure.WorkerRegistry        ← Python/TS worker pool
├── Cerebelum.Infrastructure.TaskRouter            ← gRPC task dispatch
├── Cerebelum.Infrastructure.BlueprintRegistry     ← Deployed blueprints
├── Cerebelum.Infrastructure.ExecutionStateManager ← ETS state cache
├── Cerebelum.Infrastructure.DLQ                   ← Failed step queue
├── Cerebelum.Execution.Resurrector                ← Boot-time resurrection
└── Cerebelum.Infrastructure.WorkflowScheduler     ← Periodic resurrection
```

---

## Execution Engine (gen_statem)

The engine implements a finite state machine per workflow execution:

```
                    ┌─────────────┐
                    │ initializing │
                    └──────┬──────┘
                           │ start
                           ▼
                 ┌──────────────────┐
            ┌───→│  executing_step  │←──────────────────┐
            │    └────────┬─────────┘                   │
            │             │                             │
            │     ┌───────┼───────┐                     │
            │     ▼       ▼       ▼                     │
            │  ┌──────┐ ┌──────┐ ┌──────────────────┐  │
            │  │ next │ │branch│ │ diverge (retry/   │  │
            │  │ step │ │ eval │ │ back_to/skip_to)  │──┘
            │  └──┬───┘ └──┬───┘ └──────────────────┘
            │     │        │
            │     ▼        ▼
            │  ┌──────────────────┐
            │  │   completed      │
            │  └──────────────────┘
            │
            │  ┌──────────────────┐
            └──│     failed       │
               └──────────────────┘

    [Future states not shown: sleeping, waiting_for_approval]
```

---

## Events (18 Types)

Every state transition produces an immutable domain event:

### Workflow Lifecycle
`ExecutionStartedEvent` → `ExecutionCompletedEvent` / `ExecutionFailedEvent`

### Step Execution
`StepExecutedEvent` · `StepFailedEvent`

### Flow Control
`DivergeTakenEvent` · `BranchTakenEvent` · `JumpExecutedEvent`

### Parallel Execution
`ParallelStartedEvent` → `ParallelTaskCompletedEvent` / `ParallelTaskFailedEvent` → `ParallelCompletedEvent`

### Long-Running
`SleepStartedEvent` → `SleepCompletedEvent` · `WorkflowHibernatedEvent` → `WorkflowAwakenedEvent`

### Human-in-the-Loop
`ApprovalRequestedEvent` → `ApprovalReceivedEvent` / `ApprovalRejectedEvent` / `ApprovalTimeoutEvent`

### Checkpoint
`CheckpointCreatedEvent`

---

## Workflow DSL Architecture

The DSL follows a **Package by Feature** structure for maximum cohesion:

```
workflow/dsl/
├── workflow/        # workflow do ... end macro + parser
├── timeline/        # timeline do ... end macro + parser
├── diverge/         # diverge from: ... do ... end macro + parser
└── branch/          # branch after: ... on: ... do ... end macro + parser

flow_action/
├── continue/        # Continue action
├── back_to/         # BackTo action
├── skip_to/         # SkipTo action
└── failed/          # Failed action
```

**Principle**: Each feature is self-contained — modifying one doesn't affect others.

---

## Data Flow

```
  Inputs
    │
    ▼
┌─────────┐   ┌─────────┐   ┌─────────┐
│ Step 1  │──→│ Step 2  │──→│ Step 3  │──→ Result
│         │   │         │   │         │
│ ctx     │   │ ctx     │   │ ctx     │
│ inputs  │   │ step1   │   │ step1   │
└─────────┘   │         │   │ step2   │
              └─────────┘   └─────────┘

Each step receives:
  • context (immutable: inputs, execution_id, org_id, tags)
  • all previous step results (dependency injection)

On diverge/branch:
  • Engine evaluates conditions
  • Executes flow action (retry, back_to, skip_to, continue, failed)
  • Emits domain event
```

---

## Resilience

| Mechanism | How |
|---|---|
| **Process supervision** | OTP supervisors restart failed processes |
| **Event sourcing** | Complete audit trail, replayable state |
| **Workflow resurrection** | Hibernated workflows survive restarts |
| **DLQ** | Failed steps moved to Dead Letter Queue |
| **Optimistic concurrency** | Version numbers prevent event conflicts |
| **mTLS** | gRPC workers authenticated via certificates |
| **Rate limiting** | Per-organization request throttling |

---

## gRPC Architecture (Cloud Mode)

```
┌──────────────────┐         ┌──────────────────┐
│  Python Worker   │         │ TypeScript Worker│
│  (cerebelum-sdk) │         │ (@zea.cl/        │
│                  │         │  cerebelum)       │
└────────┬─────────┘         └────────┬─────────┘
         │                            │
         │ gRPC (mTLS)                │ gRPC (mTLS)
         ▼                            ▼
┌─────────────────────────────────────────────────┐
│              Cerebelum Engine                   │
│  ┌──────────────┐  ┌──────────────┐            │
│  │WorkerRegistry│  │  TaskRouter  │            │
│  └──────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────┘
```

- Workers register via `POST /api/internal/workers/register`
- Engine dispatches step execution via gRPC
- mTLS ensures encrypted, authenticated communication
- Dev certs available via `POST /api/v1/dev-certs`

---

## See Also

- [Workflow DSL Overview](../workflow-dsl/overview.md) — DSL layer in detail
- [Event Sourcing Guide](../guides/event-sourcing.md) — Event store deep dive
- [Long-Running Workflows](../guides/long-running-workflows.md) — Hibernation + resurrection
- [Thalamus Integration](../guides/thalamus-integration.md) — Auth architecture
