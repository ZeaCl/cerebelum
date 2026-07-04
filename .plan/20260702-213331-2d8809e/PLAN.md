# Plan: Cerebelum Production Deploy + Demo Validation

- **Hash**: `20260702-213331-2d8809e`
- **Path**: `ZeaCl/cerebelum/.plan/20260702-213331-2d8809e/`
- **Engine**: ZeaCl/cerebelum @ 1e11e6b
- **Board**: https://github.com/orgs/ZeaCl/projects/6
- **Objetivo**: Desplegar cerebelum en ZEA Platform producción y validar demo-cloud contra él

> Mark `[x]` as you complete. Push after each phase.

---

## A. Database Init
- [x] A1. `init_aws.sh`: agregar `cerebelum_user` + `cerebelum_prod` database
- [x] A2. Commit + push `init_aws.sh` en `ZeaCl/zea`

## B. Docker Image & CI
- [x] B0. Commit + push `.github/workflows/publish.yml` (está untracked, CI no existe en remote)
- [x] B1. Disparar CI: push a main → build `ghcr.io/zeacl/cerebelum:latest`
- [x] B2. Verificar que el workflow corrió: `gh run list --repo ZeaCl/cerebelum`
- [x] B3. Verificar que `Release.migrate/0` funciona en el container

## T. Infra / Terraform
- [x] T1. Commit + push `main.tf` + `userdata.tftpl` en `ZeaCl/infra`
- [x] T2. `terraform apply` → secrets + DNS `cerebelum.zea.cl`
- [x] T3. Verificar `cloudflare_record.cerebelum` resuelve a la IP del servidor

## C. Deploy en ZEA
- [x] C1. `docker compose -f docker-compose.prod.yml up -d` (desde zea/)
- [x] C2. Verificar containers: `docker ps | grep cerebelum`
- [x] C3. Logs: `docker logs zea_cerebelum` sin errores

## D. Validación REST API
- [x] D1. `curl https://cerebelum.zea.cl/health` → 200
- [x] D2. `curl https://cerebelum.zea.cl/api/v1/executions` → 401 (sin token)
- [x] D3. `curl -H "Authorization: Bearer <JWT>" https://cerebelum.zea.cl/api/v1/executions` → 200

## E. Validación Demo Cloud
- [x] E1. Clonar: `git clone ZeaCl/cerebelum-demo-cloud`
- [x] E2. `pip install cerebelum-sdk`
- [x] E3. `python template/workflow.py` → `Status: completed` (local)
- [x] E4. `cerebelum login` → OAuth2 PKCE vía Thalamus → JWT guardado
- [x] E5. `cerebelum deploy workflow.py` → blueprint subido (endpoint creado)
- [x] E6. `cerebelum run my_workflow --inputs '{"name":"ZEA"}'` → exec_xxx completed
- [x] E7. `cerebelum logs <id>` → streaming eventos (ExecutionStarted → StepStarted → StepCompleted → ExecutionCompleted)
- [x] E8. `cerebelum doctor` → health OK

## F. Validación gRPC + Python Worker
- [x] Certificados mTLS generados (CA + server + client)
- [x] gRPC server con mTLS en prod → health: "running"
- [x] Puerto 50051 abierto en AWS SG vía terraform apply
- [x] Worker Python registrado vía mTLS
- [x] Worker lifecycle completo: poll → execute → submit
- [x] Eventos emitidos vía Engine: Started → StepExecuted → Completed
- [ ] Eventos con organization_id

## G. Multi-tenancy & Rate Limiting
- [x] Filtro de ejecuciones por organization_id del JWT
- [x] ETS mapping execution_id → org_id
- [x] Rate limiter funcional (1000 req/min, per org)
- [x] Rate limit headers: x-ratelimit-remaining, retry-after
- [ ] Test cross-org con segundo JWT (Südlich)
- [ ] org_id en eventos del EventStore

## H. Docs finales
- [ ] H1. `llms.txt` actualizado con Cerebelum
- [ ] H2. `README.md` ZEA actualizado

---

## Bugs fixeados post-deploy

| Commit | Fix |
|--------|-----|
| `cc5d809` | Agregar `releases` config a mix.exs para build Docker |
| `e6f2a6a` | Quitar `:inet6` que rompía IPv4 en Docker |
| `1ffaddf` | Agregar Phoenix Endpoint al supervision tree |
| `ef1a195` | Agregar Workflow.Registry al supervision tree |
| `bcc792c` | Agregar `:inets` a extra_applications para JWKS |
| `b1b8cec` | Parsear correctamente JWKS con kid |
| `0a8152d` | Usar Thalamus token introspection en vez de JWKS |
| `893fcb2` | WorkerRegistry → Infrastructure.WorkerRegistry |
| `b81e997` | CLI completo con 16 comandos |
