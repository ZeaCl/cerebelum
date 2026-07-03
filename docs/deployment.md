# Deployment

Cerebelum can be deployed standalone or as part of ZEA Platform.

---

## Docker (Standalone)

```bash
# Build
docker build -t cerebelum .

# Run
docker run -d \
  -e DATABASE_URL=ecto://user:pass@host:5432/cerebelum_prod \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e THALAMUS_URL=http://thalamus:4000 \
  -p 4001:4001 \
  -p 50051:50051 \
  cerebelum

# Health
curl http://localhost:4001/health
```

## ZEA Platform (Recommended)

Cerebelum runs as a service in the ZEA ecosystem alongside Thalamus (auth), Cranium (API), and Caddy (reverse proxy).

### Architecture

```
Internet → Caddy (:443) → cerebelum.zea.cl → Cerebelum (:4001)
                        → auth.zea.cl      → Thalamus (:4000)
                        → api.zea.cl       → Cranium (:4000)
                        → zea.cl           → App (:3000)
```

### Service Definition

```yaml
# docker-compose.prod.yml (ZeaCl/zea)
migrate_cerebelum:
  image: ghcr.io/zeacl/cerebelum:latest
  environment:
    DATABASE_URL: ecto://cerebelum_user:${CEREBELUM_DB_PASSWORD}@postgres:5432/cerebelum_prod
    SECRET_KEY_BASE: ${SECRET_KEY_BASE_CEREBELUM}
    THALAMUS_URL: http://thalamus:4000
  command: /app/bin/cerebelum eval "Cerebelum.Release.migrate"
  depends_on:
    postgres:
      condition: service_healthy

cerebelum:
  image: ghcr.io/zeacl/cerebelum:latest
  environment:
    DATABASE_URL: ecto://cerebelum_user:${CEREBELUM_DB_PASSWORD}@postgres:5432/cerebelum_prod
    MIX_ENV: prod
    PHX_HOST: cerebelum.zea.cl
    PORT: 4001
    SECRET_KEY_BASE: ${SECRET_KEY_BASE_CEREBELUM}
    THALAMUS_URL: http://thalamus:4000
  depends_on:
    postgres:
      condition: service_healthy
    migrate_cerebelum:
      condition: service_completed_successfully
```

### Caddy Route

```caddyfile
cerebelum.zea.cl {
    reverse_proxy cerebelum:4001
}
```

### Deploy Flow

```bash
# 1. Code pushed to main → GitHub Actions builds image
# 2. Image published to ghcr.io/zeacl/cerebelum:latest
# 3. Watchtower auto-pulls every 5 min on EC2
# OR manually:
ssh ubuntu@<ec2-ip>
docker pull ghcr.io/zeacl/cerebelum:latest
docker compose -f docker-compose.prod.yml up -d cerebelum
```

## Production Release

```bash
MIX_ENV=prod mix deps.get
MIX_ENV=prod mix release
_build/prod/rel/cerebelum/bin/cerebelum start
```

Run migrations:

```bash
_build/prod/rel/cerebelum/bin/cerebelum eval "Cerebelum.Release.migrate"
```

## Database

```sql
CREATE USER cerebelum_user WITH PASSWORD 'secure_password';
CREATE DATABASE cerebelum_prod;
GRANT ALL PRIVILEGES ON DATABASE cerebelum_prod TO cerebelum_user;
ALTER DATABASE cerebelum_prod OWNER TO cerebelum_user;
```

## Infrastructure (Terraform)

Secrets and DNS are managed via `ZeaCl/infra`:

```hcl
resource "random_password" "cerebelum_secret" { length = 64 }
resource "random_password" "cerebelum_db"     { length = 48 }
resource "cloudflare_record" "cerebelum" {
  name    = "cerebelum"
  content = aws_eip.zea_eip.public_ip
  type    = "A"
}
```

## Health Check

```bash
curl https://cerebelum.zea.cl/health
# {"status":"ok","version":"0.1.0","db":"ok","grpc":"stopped"}
```
