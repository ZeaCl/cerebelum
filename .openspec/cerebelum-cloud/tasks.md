# Implementation Plan — Cerebelum Cloud

- [ ] 1. **JWTAuth Plug funcional**
  - [ ] 1.1 Reimplementar `Cerebelum.API.Plugs.JWTAuth` sin dependencia `Req`
  - [ ] 1.2 Validar JWT contra Thalamus JWKS (`/.well-known/jwks.json`)
  - [ ] 1.3 Extraer `sub`, `organization_id`, `scopes` del JWT
  - [ ] 1.4 Guardar claims en `conn.assigns`
  - [ ] 1.5 Agregar plug al pipeline `:api` en el router
  - _Requirements: R1.1, R1.2, R1.3_

- [ ] 2. **Multi-tenancy — organization_id en todo el stack**
  - [ ] 2.1 Agregar `organization_id` a `Cerebelum.Context` struct
  - [ ] 2.2 Migración: agregar columna `organization_id` a tabla `events`
  - [ ] 2.3 `EventStore.append` guarda `organization_id` del contexto
  - [ ] 2.4 `EventStore.list_executions` filtra por `organization_id`
  - [ ] 2.5 `EventStore.get_events` no devuelve eventos de otras orgs
  - _Requirements: R2.1, R2.2, R2.3, R2.4_

- [ ] 3. **gRPC auth + scoping**
  - [ ] 3.1 Interceptor gRPC que valide JWT de metadata headers
  - [ ] 3.2 `worker_service_server.ex` extrae `organization_id` del contexto gRPC
  - [ ] 3.3 `BlueprintRegistry` scoped por organization
  - _Requirements: R1.4, R2.4_

- [ ] 4. **SDKs publicados en registries**
  - [ ] 4.1 Python SDK: publicar en PyPI (`pip install cerebelum-sdk`)
  - [ ] 4.2 TypeScript SDK: publicar en npm (`@zea.cl/cerebelum`)
  - [ ] 4.3 Ambos SDKs leen `CEREBELUM_URL` y `CEREBELUM_TOKEN` de env vars
  - [ ] 4.4 CI/CD: GitHub Actions auto-publica en cada release tag
  - _Requirements: R3.1, R3.2, R3.3, R3.4_

- [ ] 5. **CLI publicable**
  - [ ] 5.1 Publicar CLI como `@zea.cl/cerebelum-cli` en npm
  - [ ] 5.2 `npx cerebelum` → help con todos los comandos
  - [ ] 5.3 Comando `cerebelum run <workflow>` con `--input`
  - [ ] 5.4 Comando `cerebelum logs <execution_id>` con streaming
  - _Requirements: R4.1, R4.2, R4.3, R4.4_

- [ ] 6. **Deploy cloud (Docker)**
  - [ ] 6.1 `Dockerfile` optimizado para producción (multi-stage)
  - [ ] 6.2 `docker-compose.yml` con engine + PostgreSQL
  - [ ] 6.3 Health check endpoint que reporta DB + gRPC status
  - [ ] 6.4 Config vía env vars: `DATABASE_URL`, `THALAMUS_JWKS_URL`, `CEREBELUM_URL`
  - _Requirements: R5.1, R5.2, R5.3, R5.4_

- [ ] 7. **Rate limiting**
  - [ ] 7.1 Rate limiter por `organization_id` (1000 req/min por defecto)
  - [ ] 7.2 Soporte para PAT (Personal Access Token) con límites configurables
  - [ ] 7.3 Response headers: `X-RateLimit-Remaining`, `Retry-After`
  - _Requirements: R6.1, R6.2, R6.3_

- [ ] 8. **Demo cloud end-to-end**
  - [ ] 8.1 Arrancar engine cloud con `docker compose up`
  - [ ] 8.2 Obtener JWT de Thalamus (`curl -X POST /oauth/token`)
  - [ ] 8.3 Ejecutar workflow con `curl -H "Authorization: Bearer <JWT>"`
  - [ ] 8.4 Verificar que eventos están scoped por `organization_id`
  - [ ] 8.5 Verificar que otra org no puede ver los eventos
  - _Requirements: R1-R6_
