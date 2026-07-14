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

## Propagación de auth_token

Cuando un workflow se ejecuta vía REST API con `Authorization: Bearer <token>`, el engine propaga el JWT del usuario al worker para que los steps que llaman APIs externas puedan autenticarse:

```
execution_controller.ex
  → get_req_header(conn, "authorization") → ["Bearer <token>"]
  → execute_blueprint(workflow_name, inputs, auth_token)
  → Context.new(..., metadata: %{auth_token: token})

state_handlers.ex (:remote path)
  → get_in(data.context.metadata, [:auth_token])
  → Map.put(step_inputs, "auth_token", token)
  → Logger.info("Propagating auth_token to step X (len=NNN)")

delegating_workflow.ex
  → task = %{inputs: step_inputs, ...}  # incluye auth_token
  → TaskRouter.queue_task()

worker_service_server.ex
  → convert_to_struct(task.inputs) → Protobuf Struct
  → gRPC → Worker Python

Worker Python (create_fund)
  → auth_token = (inputs or {}).get("auth_token")
  → headers = {"Authorization": f"Bearer {auth_token}"}
  → urllib.request.Request(url, headers=headers)
```

### ⚠️ Tokens válidos
- ✅ OAuth2 PKCE (`/oauth/token` con `authorization_code`) — tiene `domain_roles`, pasa introspection
- ❌ `/api/public/login` — tiene `domain_roles` pero NO pasa `/oauth/introspect` (token de sesión)
- ❌ `client_credentials` (`internal_login`) — pasa introspection pero NO tiene `domain_roles`

### Verificación en logs
```bash
# Engine logs
ssh VPS "sudo docker logs zea_cerebelum | grep -E 'Propagating auth_token|No auth_token'"

# Worker logs
ssh VPS "sudo docker logs zea_sudlich_worker | grep -E 'auth_token present|WARNING.*auth_token'"
```
