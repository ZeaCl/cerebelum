# Resurrection — Workflow Recovery

Recuperación de workflows pausados o crasheados desde el EventStore.

## Flujo

```
1. StateReconstructor.reconstruct_to_engine_data(execution_id)
   → Lee todos los eventos del EventStore
   → Reconstruye el estado completo del Engine.Data

2. Supervisor.resume_execution(execution_id)
   → Verifica que no esté ya corriendo (Registry)
   → Valida que sea resumible (no completed permanentemente)
   → Inicia Engine con resume_from: data

3. Engine.init(resume_from: data)
   → Determina estado de resume (sleeping, waiting, executing, failed)
   → Calcula tiempos restantes de sleep/approval
```

## Estados resumibles

- Sleeping con tiempo restante > 0
- Waiting for approval
- Executing step (si crasheó a medio paso)
- Failed (errores transient)

## No resumible

- Completed (timeline terminado, sin error)

## Archivos clave

| Archivo | Rol |
|---|---|
| `lib/cerebelum/execution/state_reconstructor.ex` | Reconstruye Data desde eventos |
| `lib/cerebelum/execution/supervisor.ex` | `resume_execution/1`, `get_execution_pid/1` |
| `lib/cerebelum/execution/registry.ex` | Registro de ejecuciones activas |
| `lib/cerebelum/execution/resurrector.ex` | Escanea workflows pausados al boot |
