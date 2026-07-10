# TypeScript SDK

Build and run Cerebelum workflows in TypeScript/JavaScript. Uses decorators for step/workflow definition and runs as a gRPC worker in cloud mode.

---

## Installation

```bash
npm i @zea.cl/cerebelum
```

---

## Core Concepts

### Step

A `@Step()` decorates an async method that performs one unit of work:

```typescript
import { Step, CerebelumContext } from '@zea.cl/cerebelum';

class MySteps {
  @Step()
  async fetchUser(context: CerebelumContext): Promise<any> {
    const userId = context.inputs.user_id;
    const user = await db.getUser(userId);
    return { id: user.id, name: user.name };
  }
}
```

- **`CerebelumContext`**: Typed execution context (`.inputs`, `.executionId`, `.organizationId`)
- **Previous results**: Received as method arguments (named by step method)
- **Return**: Any serializable object

### Workflow

A `@Workflow()` decorates a class that defines the step sequence:

```typescript
import { Workflow } from '@zea.cl/cerebelum';

@Workflow()
class OnboardingWorkflow {
  build(wf: WorkflowBuilder) {
    wf.timeline(
      this.fetchUser,
      this.validate,
      this.sendEmail
    );
  }
}
```

---

## Timeline Operators

| Pattern | Meaning |
|---|---|
| `wf.timeline(A, B, C)` | Sequential: A → B → C |
| `wf.parallel([A, B, C])` | Parallel: A, B, C together |
| `wf.timeline(wf.parallel([A, B]), C)` | Parallel then sequential |

---

## Complete Example

```typescript
import { Step, Workflow, CerebelumContext } from '@zea.cl/cerebelum';

@Workflow()
class SalesAnalysis {
  @Step()
  async fetchData(context: CerebelumContext): Promise<any> {
    // Simulate API call
    await new Promise(resolve => setTimeout(resolve, 800));
    return {
      users: 1_250,
      sales: 34_500_000,
      period: context.inputs.period || 'Q4'
    };
  }

  @Step()
  async enrich(context: CerebelumContext, fetchData: any): Promise<any> {
    await new Promise(resolve => setTimeout(resolve, 500));
    return {
      ...fetchData,
      classification: 'growth',
      timestamp: new Date().toISOString()
    };
  }

  @Step()
  async generateReport(
    context: CerebelumContext,
    fetchData: any,
    enrich: any
  ): Promise<any> {
    const data = enrich || fetchData;
    return {
      report: `Sales ${data.period}: $${data.sales.toLocaleString()}`,
      metrics: {
        averageTicket: data.sales / Math.max(data.users, 1),
        category: data.classification || 'n/a'
      }
    };
  }

  build(wf: WorkflowBuilder) {
    wf.timeline(
      this.fetchData,
      this.enrich,
      this.generateReport
    );
  }
}
```

---

## Execution

### Local

```typescript
import { SalesAnalysis } from './sales-analysis';

const workflow = new SalesAnalysis();
const result = await workflow.execute({ period: 'Q4-2025' });

console.log(`Status: ${result.status}`);
console.log('Results:', result.results);
```

### Cloud (ZEA Platform)

```bash
# CLI handles deployment and execution
cerebelum run workflow.ts
```

---

## Typed Context

```typescript
interface CerebelumContext {
  inputs: Record<string, any>;
  executionId: string;
  organizationId?: string;
  correlationId?: string;
  tags: string[];
}
```

---

## Error Handling

```typescript
@Step()
async callExternalAPI(context: CerebelumContext): Promise<any> {
  try {
    const response = await fetch(context.inputs.url);
    if (!response.ok) {
      return { status: 'error', code: response.status };
    }
    return { status: 'ok', data: await response.json() };
  } catch (error) {
    if (error.name === 'TimeoutError') {
      return { status: 'timeout' };
    }
    return { status: 'failed', message: error.message };
  }
}
```

The engine maps statuses to diverge actions on the Elixir side.

---

## Worker Mode

```bash
# Start TypeScript worker
npx cerebelum-worker --port 9000

# Or programmatically
import { CerebelumWorker } from '@zea.cl/cerebelum/worker';

const worker = new CerebelumWorker({
  port: 9000,
  workflows: [SalesAnalysis],
  engineUrl: 'https://cerebelum.zea.cl'
});

await worker.start();
```

---

## See Also

- [Python SDK](python.md) — Python equivalent
- [SDK Overview](overview.md) — Comparison table
