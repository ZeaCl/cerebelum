# Tutorial: First Python Workflow

Build and run a workflow with the Python SDK. **Time: 5 minutes**.

---

## Prerequisites

- Python 3.10+
- Cerebelum SDK installed

```bash
pip install cerebelum-sdk
```

---

## Step 1: Create a Workflow

Create `hello_workflow.py`:

```python
from cerebelum import step, workflow
import asyncio
from datetime import datetime


@step
async def greet(context, **kwargs):
    """Step 1: Generate a greeting."""
    name = context.inputs.get("name", "World")
    return {"message": f"Hello, {name}!"}


@step
async def personalize(context, greet=None, **kwargs):
    """Step 2: Add metadata to the greeting."""
    greeting_data = greet or {}
    return {
        "message": greeting_data.get("message", ""),
        "timestamp": datetime.utcnow().isoformat(),
        "emoji": "👋"
    }


@step
async def deliver(context, greet=None, personalize=None, **kwargs):
    """Step 3: Deliver the message."""
    personalized = personalize or {}
    message = personalized.get("message", "")
    print(f"📨 Delivering: {message}")
    return {"delivered": True, "message": message}


@workflow
def hello_workflow(wf):
    """Define the workflow structure."""
    wf.timeline(greet >> personalize >> deliver)
```

### What's happening

1. `@step` — decorates async functions as workflow steps
2. `context` — the execution context (has `.inputs`, `.execution_id`, etc.)
3. `**kwargs` — receives previous step results by name
4. `@workflow` — decorates the workflow definition function
5. `wf.timeline(A >> B >> C)` — chains steps in order

---

## Step 2: Run

```bash
python hello_workflow.py
```

Or programmatically:

```python
import asyncio
from hello_workflow import hello_workflow

async def main():
    result = await hello_workflow.execute({"name": "Alice"})
    print(f"Status: {result.status}")
    print(f"Results: {result.results}")

asyncio.run(main())
```

```
📨 Delivering: Hello, Alice!
Status: completed
Results: {
  'greet': {'message': 'Hello, Alice!'},
  'personalize': {'message': 'Hello, Alice!', 'timestamp': '...', 'emoji': '👋'},
  'deliver': {'delivered': True, 'message': 'Hello, Alice!'}
}
```

---

## Step 3: Run in Cloud Mode (ZEA Platform)

```bash
# Create a project with the CLI
npx @zea.cl/create-cerebelum my-project
cd my-project

# Copy your workflow
cp hello_workflow.py workflow.py

# Run it in the cloud
cerebelum run workflow.py
```

The CLI handles everything:
- ✅ Auth (OAuth2 via Thalamus)
- ✅ mTLS certs
- ✅ Deploy blueprint
- ✅ Worker process
- ✅ Execution + live logs

---

## Step 4: Add Parallel Execution

Speed up independent operations:

```python
from cerebelum import step, workflow
import asyncio


@step
async def fetch_users(context, **kwargs):
    await asyncio.sleep(0.5)  # Simulate API call
    return {"count": 1_250}


@step
async def fetch_orders(context, **kwargs):
    await asyncio.sleep(0.8)  # Simulate API call
    return {"count": 34_500}


@step
async def fetch_revenue(context, **kwargs):
    await asyncio.sleep(0.3)  # Simulate API call
    return {"amount": 5_200_000}


@step
async def aggregate(context, fetch_users=None, fetch_orders=None, fetch_revenue=None, **kwargs):
    users = fetch_users or {}
    orders = fetch_orders or {}
    revenue = fetch_revenue or {}
    return {
        "total_users": users.get("count", 0),
        "total_orders": orders.get("count", 0),
        "total_revenue": revenue.get("amount", 0),
        "avg_order_value": revenue.get("amount", 0) / max(orders.get("count", 1), 1)
    }


@workflow
def analytics_workflow(wf):
    # fetch_users, fetch_orders, fetch_revenue run in parallel
    wf.timeline([fetch_users, fetch_orders, fetch_revenue] >> aggregate)
```

All three fetch steps run concurrently (~0.8s total) instead of sequentially (~1.6s).

---

## Step 5: Error Handling

Catch and handle errors gracefully:

```python
from cerebelum import step, workflow


@step
async def fetch_data(context, **kwargs):
    endpoint = context.inputs.get("endpoint")
    try:
        response = await api_call(endpoint)
        return {"data": response}
    except TimeoutError:
        return {"error": "timeout"}
    except Exception as e:
        return {"error": str(e)}


@step
async def process(context, fetch_data=None, **kwargs):
    result = fetch_data or {}
    if "error" in result:
        if result["error"] == "timeout":
            # Return error code that the engine can handle
            return {"status": "retry"}
        return {"status": "failed", "reason": result["error"]}
    return {"status": "ok", "data": result["data"]}


@workflow
def resilient_workflow(wf):
    wf.timeline(fetch_data >> process)
```

---

## Next Steps

- [Python SDK Guide](../sdk/python.md) — Full reference
- [First Elixir Workflow](01-first-elixir-workflow.md) — Compare approaches
- [Parallel Execution](03-parallel-execution.md) — In-depth parallel patterns
- [Error Handling Patterns](04-error-handling.md) — Retry, diverge, DLQ
