# Plan: Zero-friction Dev Experience

- **Hash**: `20260705-154624-a35fc13`
- **Engine**: ZeaCl/cerebelum @ a35fc13
- **Board**: https://github.com/orgs/ZeaCl/projects/6
- **Objetivo**: `cerebelum run` hace todo. El dev solo edita `workflow.py` y ejecuta.

---

## I1. Engine: endpoint de dev-certs

Para que el CLI genere certs sin que el dev se entere.

- [ ] I1.1. Endpoint `POST /api/v1/dev-certs` (autenticado con JWT)
- [ ] I1.2. Usa la misma CA de `priv/certs/` para firmar client certs
- [ ] I1.3. Devuelve `{ ca_crt, client_crt, client_key }`
- [ ] I1.4. Rate-limit: 5 certs por minuto por usuario

### Tests
- `curl -H "Authorization: Bearer <JWT>" -X POST /api/v1/dev-certs` → `{ ca_crt, client_crt, client_key }`
- Segundo request con mismo JWT → mismo cert (idempotente)
- Sin JWT → 401

---

## I2. CLI: `cerebelum run` inteligente

Reemplaza el `run` actual. Hace checklist y auto-resuelve.

- [ ] I2.1. Check login → si no, dispara OAuth2 PKCE
- [ ] I2.2. Check certs → si no, `POST /api/v1/dev-certs` y guarda en `~/.cerebelum/certs/`
- [ ] I2.3. Check blueprint → si no desplegado, deploy automático desde `workflow.py` (cwd)
- [ ] I2.4. Check worker → si no corriendo, `python worker.py &` (o `cerebelum-sdk` worker)
- [ ] I2.5. Ejecutar → `POST /api/v1/executions` o flujo embedido
- [ ] I2.6. Mostrar logs en tiempo real (poll events)
- [ ] I2.7. Resumen final con tiempo total

### Tests
- Primer `cerebelum run` → resuelve login, certs, deploy, worker, ejecuta ✅
- Segundo `cerebelum run` → solo redeploya si cambió workflow.py, ejecuta ✅
- Sin workflow.py en cwd → error claro
- Worker ya corriendo → no lo reinicia

---

## I3. CLI: `cerebelum logs` (sin args)

- [ ] I3.1. Sin argumentos → busca el último execution_id de `~/.cerebelum/last_exec`
- [ ] I3.2. Con `execution_id` → comportamiento actual
- [ ] I3.3. `--follow` → streaming (ya existe)

---

## I4. CLI: `cerebelum status`

- [ ] I4.1. Muestra: auth status, certs status, blueprints locales, worker status, últimas ejecuciones
- [ ] I4.2. Formato legible (tabla/resumen)

---

## I5. Template: workflow demo

- [ ] I5.1. `create-cerebelum/template/workflow.py` → workflow con 3 steps encadenados, delays simulados
- [ ] I5.2. Steps: `obtener_datos` → `procesar_datos` → `notificar`
- [ ] I5.3. Comentarios explicando cómo modificar/agregar steps

---

## Dependencias

```
I1 (dev-certs endpoint) ──┐
                           ├──→ I2 (cerebelum run)
I5 (template) ─────────────┘
I2 ──→ I3 (logs sin args)
I2 ──→ I4 (status)
```
