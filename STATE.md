# STATE.md — Cerebelum Production Deploy

> **Plan activo**: `.plan/20260702-213331-2d8809e/PLAN.md`
> **Board**: https://github.com/orgs/ZeaCl/projects/6
> **Última actualización**: 2026-07-04

---

## Estado general

| Fase | Descripción | Estado |
|---|---|---|
| A | Database Init | ✅ Done |
| B | Docker Image + CI/CD | ✅ Done |
| T | Terraform secrets + DNS | ✅ Done |
| C | Deploy en ZEA Platform | ✅ Done |
| D | Validación REST API | ✅ Done |
| E | Validación Demo Cloud | ✅ Done |
| **F** | **gRPC + Python Worker** | 🔴 **En progreso** |
| G | Multi-tenancy + Rate Limiting | ⚪ Todo |
| H | Docs finales | ⚪ Todo |

---

## 🔴 Fase F — En progreso

### Objetivo
Validar que un Python Worker se conecta al engine vía gRPC con mTLS, registra workflows, y ejecuta pasos distribuidos con eventos etiquetados con `organization_id`.

### Progreso
- [x] F0. Certs mTLS generados (`priv/certs/`)
- [x] F1. gRPC server con mTLS corriendo en prod
- [x] F2. Health check → `"grpc": "running"`
- [x] F3. Certs montados en container (`/app/certs`)
- [x] F4. Worker Python conecta vía mTLS (SSH tunnel)
- [x] F5. Worker registrado exitosamente (`RegisterResponse.success=true`)
- [ ] F6. Abrir puerto 50051 en AWS SG (terraform apply — sin creds)
- [ ] F7. Test completo: poll → execute → submit → eventos con org_id

---

## ⚪ Fase G — Multi-tenancy & Rate Limiting

### Objetivo
1. Org A no ve ejecuciones de Org B
2. Rate limit: 429 al exceder 1000 req/min

### Progreso
- [ ] G1. Diagnosticar estado actual del rate limiter
- [ ] G2. Diagnosticar extracción de org_id del JWT
- [ ] G3. Filtrar ejecuciones por org_id
- [ ] G4. Test: Org A no ve ejecuciones de Org B
- [ ] G5. Test: Rate limit → 429

## ⚪ Fase H — Sin empezar
- `llms.txt` actualizado
- README.md ZEA actualizado
