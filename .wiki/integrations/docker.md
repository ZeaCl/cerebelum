# Docker — Build & Deploy

## Dockerfile

Multi-stage build:
1. **Build stage**: `mix deps.get`, `mix compile`, `mix release`
2. **Runtime stage**: Imagen Alpine con Elixir runtime + release

## Imagen

- **Registry**: `ghcr.io/zeacl/cerebelum:latest`
- **CI/CD**: GitHub Actions `publish.yml` build + push

## Compose local

Servicio en `zea/docker-compose.local.yml`:
```yaml
cerebelum:
  image: ghcr.io/zeacl/cerebelum:latest  # prod
  # o build desde source para dev
  build:
    context: ../cerebelum
    dockerfile: Dockerfile
    target: runtime
  ports:
    - "50051:50051"
  environment:
    DATABASE_URL: "ecto://cerebelum_user:PASS@postgres:5432/cerebelum_prod"
    GRPC_PORT: "50051"
```

## Multi-instance (issues)

Para trabajar en issues sin tocar develop:
```yaml
cerebelum_issue_79:
  build:
    context: ../cerebelum-issue-79
  container_name: zea_cerebelum_issue_79
  ports:
    - "50052:50052"
  environment:
    DATABASE_URL: "ecto://cerebelum_user:PASS@postgres:5432/cerebelum_dev_79"
    GRPC_PORT: "50052"
```
