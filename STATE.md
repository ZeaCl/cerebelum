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
- [ ] F1. Configurar gRPC server con TLS en Elixir
- [ ] F2. Montar certs en `docker-compose.prod.yml`
- [ ] F3. Abrir puerto 50051 en security group (`main.tf`)
- [ ] F4. Worker Python con TLS (`ssl_channel_credentials`)
- [ ] F5. Validar — health check gRPC → running, worker registrado, eventos con org_id

---

## ⚪ Fase G — Sin empezar
- Multi-tenancy: Org A no ve ejecuciones de Org B
- Rate limit: 429 al exceder 1000 req/min

## ⚪ Fase H — Sin empezar
- `llms.txt` actualizado
- README.md ZEA actualizado
