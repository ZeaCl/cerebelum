"""My Cerebelum Workflow — modify this file to build your workflow."""

from cerebelum import step, workflow

# ── Define your steps ─────────────────────────────────────

@step
async def hello(context):
    """First step: greets the world."""
    return {"message": "Hello, Cerebelum! 🧠"}

# Add more steps here...
# @step
# async def my_step(context, previous_result=None):
#     return {"data": "my result"}

# ── Define your workflow ──────────────────────────────────

@workflow
def my_workflow(wf):
    wf.timeline(hello)
    # wf.timeline(hello >> my_step)  # Chain steps

# ── Execute ───────────────────────────────────────────────

import asyncio

async def main():
    result = await my_workflow.execute({})
    print(f"Status: {result.status}")

if __name__ == "__main__":
    asyncio.run(main())
