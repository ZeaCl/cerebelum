# Plan: Cerebelum Production Deploy + Demo Validation

- **Hash**: 20260702-213331-2d8809e
- **Engine**: ZeaCl/cerebelum @ 2d8809e
- **Objetivo**: Desplegar cerebelum en ZEA Platform producción y validar demo-cloud contra él

---

## Checklist

### A. Database Init
- [ ] A1. `init_aws.sh`: agregar `cerebelum_user` + `cerebelum_prod` database

### B. Docker Image
- [ ] B1. Build: `docker build -t ghcr.io/zeacl/cerebelum:latest .` (desde cerebelum-core/)
- [ ] B2. Push: `docker push ghcr.io/zeacl/cerebelum:latest`
- [ ] B3. Verificar que `Release.migrate/0` funciona en el container

### C. Deploy en ZEA
- [ ] C1. `docker compose -f docker-compose.prod.yml up -d` (desde zea/)
- [ ] C2. Verificar containers: `docker ps | grep cerebelum`
- [ ] C3. Logs: `docker logs zea_cerebelum` sin errores

### D. Validación REST API
- [ ] D1. `curl https://cerebelum.zea.cl/health` → 200
- [ ] D2. `curl https://cerebelum.zea.cl/api/v1/executions` → 401 (sin token)
- [ ] D3. `curl -H "Authorization: Bearer <JWT>" https://cerebelum.zea.cl/api/v1/executions` → 200

### E. Validación Demo Cloud
- [ ] E1. Clonar: `git clone ZeaCl/cerebelum-demo-cloud`
- [ ] E2. `pip install cerebelum-sdk`
- [ ] E3. `python template/workflow.py` → `Status: completed` (local)
- [ ] E4. `npx @zea.cl/cerebelum-cli login` → obtiene JWT
- [ ] E5. `cerebelum deploy template/workflow.py` → blueprint subido
- [ ] E6. `cerebelum run MyWorkflow --input '{"name":"ZEA"}'` → completed
- [ ] E7. `cerebelum logs <id> --follow` → streaming eventos
- [ ] E8. `cerebelum doctor` → health OK

### F. Validación gRPC + Python Worker
- [ ] F1. Worker Python registrado
- [ ] F2. Workflow distribuido via gRPC → 5/5 completed
- [ ] F3. Eventos en EventStore con organization_id

### G. Multi-tenancy
- [ ] G1. Org A no ve ejecuciones de Org B
- [ ] G2. Rate limit: >1000 req/min → 429

### H. Docs finales
- [ ] H1. `llms.txt` actualizado con Cerebelum
- [ ] H2. `README.md` ZEA actualizado
