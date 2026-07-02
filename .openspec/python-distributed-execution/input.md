# Input — Python Distributed Workflow Execution

## Propósito
Permitir que workflows definidos en Python (vía `@step` + `@workflow`) se ejecuten en el engine de Cerebelum por gRPC, sin necesidad de recompilar ni reiniciar el servidor Elixir.

## Alcance
- **IN**: Un dev Python define un workflow con `@step`/`@workflow`, lo envía por gRPC (`DistributedExecutor`), el engine lo ejecuta y devuelve resultados
- **IN**: El engine despacha cada step a workers Python registrados vía `TaskRouter`
- **IN**: Los workers hacen poll, ejecutan el step, y envían el resultado de vuelta
- **OUT**: Workflows con steps Elixir (ya funcionan nativamente)
- **OUT**: Workflows con steps mixtos Python+Elixir (futuro)

## Contexto
**Lo que YA funciona:**
- `SubmitBlueprint` vía gRPC: el blueprint se valida y almacena ✅
- `DistributedExecutor.execute()`: el SDK Python envía el blueprint y llama a `ExecuteWorkflow` ✅
- `TaskRouter`: sistema de colas para distribuir tasks a workers ✅
- `WorkerRegistry`: registro de workers Python disponibles ✅
- Workflows Elixir nativos: 100% funcionales ✅
- Python SDK local mode (`LocalExecutor`): 100% funcional ✅

**Lo que FALLA:**
- `ExecuteWorkflow` llama a `Cerebelum.WorkflowDelegatingWorkflow` pero:
  - `DelegatingWorkflow.execute_step/3` no está conectado al loop de ejecución del Engine
  - `DelegatingWorkflow` no accede correctamente al blueprint desde el contexto
  - No hay reconciliación entre los steps del blueprint y el `StepExecutor`
  - Los workers no reciben tasks porque la integración `Engine → TaskRouter → Worker` no está cerrada

**Restricciones:**
- El engine usa `:gen_statem` con `StateHandlers.executing_step`
- Los workflows Elixir ejecutan steps vía `StepExecutor.execute_step/6`
- Los workflows Python deben ejecutar steps vía `DelegatingWorkflow → TaskRouter → Worker`
- El engine no puede bloquearse esperando workers (debe ser async con callbacks)

## Stakeholders
- Devs Python que quieren workflows sin recompilar
- Devs Elixir que mantienen el engine
- Operadores que monitorean ejecuciones
