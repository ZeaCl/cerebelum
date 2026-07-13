# Python Worker SDK

- **Repo**: `ZeaCl/cerebelum-python`
- **Paquete**: `cerebelum-sdk>=0.3.1`
- **Protocolo**: gRPC en puerto 50051

## Conexión

```bash
CEREBELUM_CORE_URL=cerebelum:50051
```

## Workflow markers

Workers envían señales al engine vía gRPC:

| Marker | Engine state |
|---|---|
| `ApprovalMarker` | `:waiting_for_approval` |
| `SleepMarker` | `:sleeping` |

## Archivos clave (SDK)

| Archivo | Rol |
|---|---|
| `cerebelum/dsl/async_helpers.py` | `wait_for_approval()`, `sleep()` |
| `cerebelum/dsl/decorators.py` | `@step` wrapper |
| `cerebelum/dsl/workflow_markers.py` | `ApprovalMarker`, `SleepMarker` |
| `cerebelum/distributed.py` | Worker gRPC client |

## Debugging

- Worker no se conecta → `CEREBELUM_CORE_URL` debe apuntar a `cerebelum:50051`
- Steps instantáneos → `@step` decorator traga el marker (SDK >= 0.3.1)
- `previous_results` inesperado → agregar `**kwargs` a step functions
