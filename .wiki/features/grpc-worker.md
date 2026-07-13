# gRPC Worker — Distributed Execution

Comunicación gRPC entre Cerebelum y Python Workers para ejecución distribuida de steps.

## Arquitectura

```
Cerebelum (Elixir)                    Python Worker
     │                                      │
     │  gRPC:50051 ───────────────────────→ │
     │  RegisterWorker                      │
     │  ←──────────────────────── Worker ID │
     │                                      │
     │  gRPC:50051 ───────────────────────→ │
     │  ExecuteTask(step, inputs)           │
     │  ←──────────────────────── result    │
```

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/infrastructure/worker_service_server.ex` | gRPC server, registra workers, ejecuta tareas |
| `lib/cerebelum/infrastructure/task_router.ex` | Sticky routing a workers |
| `lib/cerebelum/infrastructure/blueprint_registry.ex` | Registro de blueprints deployados |
| `lib/cerebelum/workflow/delegating_workflow.ex` | WorkflowDelegatingWorkflow genérico |

## Puerto

- **50051** (gRPC, sin TLS en local, mTLS en prod)
- Variable: `GRPC_PORT`

## Worker SDK (Python)

- Repo: `ZeaCl/cerebelum-python`
- Paquete: `cerebelum-sdk>=0.3.1`
- Conexión: `CEREBELUM_CORE_URL=cerebelum:50051`

## Marcadores

Workers pueden enviar señales especiales al engine:
- **APPROVAL** → Engine entra en `:waiting_for_approval`
- **SLEEP** → Engine entra en `:sleeping`

## Deploy de blueprints

Workers deployan blueprints vía gRPC que se almacenan en BlueprintRegistry (ETS):
```elixir
BlueprintRegistry.store_blueprint("my_workflow", %{language: "python", steps: [...]})
```
