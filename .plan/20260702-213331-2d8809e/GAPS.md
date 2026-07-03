# Gaps — Lo que falta para producción

## A. Database Init (init_aws.sh)
El script `ZeaCl/zea/init_aws.sh` crea usuarios y DBs para thalamus y cranium.
**Falta**: `cerebelum_user` + `cerebelum_prod`

```sql
CREATE USER cerebelum_user WITH PASSWORD '$CEREBELUM_DB_PASSWORD';
CREATE DATABASE cerebelum_prod;
GRANT ALL PRIVILEGES ON DATABASE cerebelum_prod TO cerebelum_user;
ALTER DATABASE cerebelum_prod OWNER TO cerebelum_user;
```

## B. Docker Image
- La imagen se construye con `docker build -t ghcr.io/zeacl/cerebelum:latest .`
- El GitHub Action `.github/workflows/publish.yml` la publica automáticamente
- **Falta**: build + push inicial (o esperar al CI)

## C. Release.migrate
`Cerebelum.Release.migrate/0` ya existe y ejecuta migraciones Ecto.
- Dockerfile CMD: `/app/bin/cerebelum start` (no `eval`)
- El migrate se ejecuta como container separado:
  `command: /app/bin/cerebelum eval "Cerebelum.Release.migrate"`
- **OK**: Ya configurado en docker-compose.prod.yml

## D. Terraform Secrets
Ya agregados en `main.tf`:
- `random_password.cerebelum_db`
- `random_password.cerebelum_secret`
- `cloudflare_record.cerebelum`
- userdata.tftpl incluye `${cerebelum_db_password}`, `${secret_key_base_cerebelum}`

## E. Validación Demo Cloud
El repo `ZeaCl/cerebelum-demo-cloud` tiene:
- `template/workflow.py` — ejemplo funcional
- `template/requirements.txt`
- `template/README.md`
- README con quickstart cloud

**Falta probar**:
1. `pip install cerebelum-sdk` (o instalar desde GitHub)
2. Ejecutar workflow local → completed
3. Deploy a cerebelum.zea.cl → blueprint registrado
4. Ejecutar en cloud → completed 5/5
5. Ver logs → streaming eventos
