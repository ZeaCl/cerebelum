# Plan: Cerebelum Production Deploy + Demo Validation

- **Hash**: `20260702-213331-2d8809e`
- **Path**: `ZeaCl/cerebelum/.plan/20260702-213331-2d8809e/`
- **Engine**: ZeaCl/cerebelum @ 2d8809e
- **Objetivo**: Desplegar cerebelum en ZEA Platform producción y validar demo-cloud contra él

> Mark `[x]` as you complete. Push after each phase.

---

## A. Database Init
- [x] A1. `init_aws.sh`: agregar `cerebelum_user` + `cerebelum_prod` database
- [x] A2. Commit + push `init_aws.sh` en `ZeaCl/zea`

## B. Docker Image & CI
- [x] B0. Commit + push `.github/workflows/publish.yml` (está untracked, CI no existe en remote)
- [x] B1. Disparar CI: `gh workflow run publish.yml` o push a main → build `ghcr.io/zeacl/cerebelum:latest`
- [x] B2. Verificar que el workflow corrió: `gh run list --repo ZeaCl/cerebelum`
- [x] B3. Verificar que `Release.migrate/0` funciona en el container

## T. Infra / Terraform
- [x] T1. Commit + push `main.tf` + `userdata.tftpl` en `ZeaCl/infra`
- [x] T2. `terraform apply` → secrets (`cerebelum_db_password`, `secret_key_base_cerebelum`) + DNS `cerebelum.zea.cl`
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
- [ ] E4. `npx @zea.cl/cerebelum-cli login` → obtiene JWT
- [ ] E5. `cerebelum deploy template/workflow.py` → blueprint subido
- [ ] E6. `cerebelum run MyWorkflow --input '{"name":"ZEA"}'` → completed
- [ ] E7. `cerebelum logs <id> --follow` → streaming eventos
- [x] E8. `cerebelum doctor` → health OK

## F. Validación gRPC + Python Worker
- [ ] F1. Worker Python registrado
- [ ] F2. Workflow distribuido via gRPC → 5/5 completed
- [ ] F3. Eventos en EventStore con organization_id

## G. Multi-tenancy
- [ ] G1. Org A no ve ejecuciones de Org B
- [ ] G2. Rate limit: >1000 req/min → 429

## H. Docs finales
- [ ] H1. `llms.txt` actualizado con Cerebelum
- [ ] H2. `README.md` ZEA actualizado
