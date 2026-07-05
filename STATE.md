# STATE.md — Cerebelum Production Deploy

> **Plan activo**: `.plan/20260705-122548-7ec618d/PLAN.md` (Publicar SDKs + create-cerebelum)
> **Plan anterior**: `.plan/20260702-213331-2d8809e/PLAN.md` ✅ Completado
> **Board**: https://github.com/orgs/ZeaCl/projects/6
> **Última actualización**: 2026-07-05

---

## ✅ Fases completadas

| Fase | Descripción |
|---|---|
| A | Database Init |
| B | Docker Image + CI/CD |
| T | Terraform secrets + DNS |
| C | Deploy en ZEA Platform |
| D | Validación REST API |
| E | Validación Demo Cloud (login, deploy, run, logs) |
| F | gRPC + Python Worker (mTLS, lifecycle) |
| G | Multi-tenancy + Rate Limiting |

---

## 🔴 H — Publicar SDKs + create-cerebelum

### Objetivo
Publicar paquetes en PyPI/npm para que `npx @zea.cl/create-cerebelum my-project` funcione en cualquier máquina.

### Progreso
- [ ] H1. Python SDK → PyPI (`cerebelum-sdk`)
- [ ] H2. CLI → npm (`@zea.cl/cerebelum-cli`)
- [ ] H3. Scaffold → npm (`@zea.cl/create-cerebelum`)

### Próximo paso
H1.1 — Crear `pyproject.toml` para el SDK de Python
