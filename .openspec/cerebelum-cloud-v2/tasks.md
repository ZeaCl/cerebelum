# Implementation Plan — Cerebelum Cloud

- [ ] 1. **JWTAuth Plug sin dependencia Req**
  - [ ] 1.1 Implementar `Cerebelum.API.Plugs.JWTAuth` usando `Finch` para JWKS fetch
  - [ ] 1.2 Validar firma JWT con `JOSE` (ya en deps)
  - [ ] 1.3 Extraer `sub`, `organization_id` de los claims
  - [ ] 1.4 Agregar al pipeline `:api` en el router
  - [ ] 1.5 Test: sin token → 401, token inválido → 401, válido → 200
  _Requirements: R3.1, R3.2, R3.3, R3.4_

- [ ] 2. **Multi-tenancy — organization_id en todo el stack**
  - [ ] 2.1 Agregar `organization_id` a `Cerebelum.Context`
  - [ ] 2.2 Migración DB: columna en tabla `events`
  - [ ] 2.3 `EventStore` guarda y filtra por `organization_id`
  - [ ] 2.4 `ExecutionController` usa `conn.assigns.organization_id`
  - [ ] 2.5 Test: Org A no ve ejecuciones de Org B
  _Requirements: R4.1, R4.2, R4.3, R4.4_

- [ ] 3. **SDK Python publicable en PyPI**
  - [ ] 3.1 Completar `pyproject.toml` con metadata, classifiers, version
  - [ ] 3.2 Agregar soporte para `CEREBELUM_URL` y `CEREBELUM_TOKEN` env vars
  - [ ] 3.3 GitHub Action: publicar en PyPI al pushear tag `v*`
  _Requirements: R1.1, R1.2, R1.3, R1.4_

- [ ] 4. **CLI publicable en npm**
  - [ ] 4.1 Publicar como `@zea.cl/cerebelum-cli` en npm
  - [ ] 4.2 `cerebelum login` → OAuth2 Thalamus → guarda token
  - [ ] 4.3 `cerebelum whoami` → user, org, token status
  - [ ] 4.4 `cerebelum init <name>` → scaffold template
  - [ ] 4.5 `cerebelum deploy workflow.py` → SubmitBlueprint
  - [ ] 4.6 `cerebelum workflow list|show|delete|run` → CRUD
  - [ ] 4.7 `cerebelum execution list|status|logs|stop|resume|approve` → lifecycle
  - [ ] 4.8 `cerebelum worker list` + `cerebelum doctor` → ops
  _Requirements: R2.1-R2.6_

- [ ] 5. **Dockerfile multi-stage + GitHub Container Registry**
  - [ ] 5.1 `Dockerfile`: `deps` → `build` → `runtime` (alpine, patrón Thalamus)
  - [ ] 5.2 `Cerebelum.Release.migrate/0` para migraciones DB
  - [ ] 5.3 Health check endpoint: DB + gRPC + Thalamus JWKS status
  - [ ] 5.4 GitHub Action: build + push `ghcr.io/zeacl/cerebelum:latest`
  _Requirements: R5.1, R5.3_

- [ ] 6. **Integración en ZEA docker-compose + Caddy + Watchtower**
  - [ ] 6.1 `migrate_cerebelum` service → corre migraciones antes de arrancar
  - [ ] 6.2 `cerebelum` service con imagen `ghcr.io/zeacl/cerebelum:latest`
  - [ ] 6.3 Env vars: `DATABASE_URL`, `THALAMUS_URL`, `SECRET_KEY_BASE`
  - [ ] 6.4 `cerebelum.zea.cl` → Caddyfile reverse_proxy
  - [ ] 6.5 Watchtower auto-update
  _Requirements: R5.1, R5.2, R5.3, R5.4_

- [ ] 7. **Rate limiting**
  - [ ] 7.1 Rate limiter por `organization_id` (1000 req/min)
  - [ ] 7.2 Response headers: `X-RateLimit-Remaining`, `Retry-After`
  _Requirements: R7.1, R7.2, R7.3_

- [ ] 8. **Demo cloud end-to-end (`cerebelum-demo-cloud`)**
  - [ ] 8.1 `pip install cerebelum-sdk` desde PyPI
  - [ ] 8.2 `cerebelum init my-demo` → scaffold
  - [ ] 8.3 `cerebelum login` → JWT
  - [ ] 8.4 `cerebelum deploy workflow.py` → blueprint en engine
  - [ ] 8.5 `cerebelum run OrderWorkflow` → ejecutar
  - [ ] 8.6 `cerebelum logs <id> --follow` → streaming
  - [ ] 8.7 Verificar multi-tenancy: otro token no ve eventos
  _Requirements: R6_

- [ ] 9. **Template `cerebelum init`**
  - [ ] 9.1 `workflow.py` template con `@step` + `@workflow`
  - [ ] 9.2 `requirements.txt` con `cerebelum-sdk`
  - [ ] 9.3 `README.md` con quickstart 3 pasos
  _Requirements: R2.2, R6_

- [ ] 10. **Documentación en ZEA Platform**
  - [ ] 10.1 Agregar a tabla de servicios en `zea/README.md`
  - [ ] 10.2 Actualizar `zea/docs/index.html`
  - [ ] 10.3 Agregar sección en `llms.txt` con API, auth, quickstart
  - [ ] 10.4 Links a SDKs (npm, PyPI)
  _Requirements: R8_
