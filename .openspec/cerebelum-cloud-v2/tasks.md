# Implementation Plan — Cerebelum Cloud

- [ ] 1. **JWTAuth Plug sin dependencia Req**
  - [ ] 1.1 Implementar `Cerebelum.API.Plugs.JWTAuth` usando `Finch` para JWKS fetch
  - [ ] 1.2 Validar firma JWT con `JOSE` (ya en deps)
  - [ ] 1.3 Extraer `sub`, `organization_id` de los claims
  - [ ] 1.4 Agregar al pipeline `:api` en el router
  - [ ] 1.5 Test: request sin token → 401, con token inválido → 401, con token válido → pasa
  - _Requirements: R3.1, R3.2, R3.3, R3.4_

- [ ] 2. **Multi-tenancy — organization_id en todo el stack**
  - [ ] 2.1 Agregar `organization_id` a `Cerebelum.Context`
  - [ ] 2.2 Migración DB: columna en tabla `events`
  - [ ] 2.3 `EventStore` guarda y filtra por `organization_id`
  - [ ] 2.4 `ExecutionController` usa `conn.assigns.organization_id`
  - [ ] 2.5 Test: Org A no puede ver ejecuciones de Org B
  - _Requirements: R4.1, R4.2, R4.3, R4.4_

- [ ] 3. **SDK Python publicable en PyPI**
  - [ ] 3.1 Completar `pyproject.toml` con metadata, classifiers, version
  - [ ] 3.2 Agregar soporte para `CEREBELUM_URL` y `CEREBELUM_TOKEN` env vars
  - [ ] 3.3 Agregar `cerebelum deploy` vía gRPC `SubmitBlueprint`
  - [ ] 3.4 GitHub Action: publicar en PyPI al pushear tag `v*`
  - _Requirements: R1.1, R1.2, R1.3, R1.4_

- [ ] 4. **CLI publicable en npm**
  - [ ] 4.1 Publicar como `@zea.cl/cerebelum-cli` en npm
  - [ ] 4.2 Comando `cerebelum login` → OAuth2 Thalamus → guarda token
  - [ ] 4.3 Comando `cerebelum init <name>` → scaffold template
  - [ ] 4.4 Comando `cerebelum deploy workflow.py` → SubmitBlueprint
  - [ ] 4.5 Comando `cerebelum logs <id> --follow` → streaming vía REST
  - _Requirements: R2.1, R2.2, R2.3, R2.4, R2.5, R2.6_

- [ ] 5. **Integración en ZEA Platform docker-compose**
  - [ ] 5.1 Agregar `cerebelum` service al `docker-compose.yml` de ZEA
  - [ ] 5.2 Agregar ruta `cerebelum.zea.localhost` en Caddyfile
  - [ ] 5.3 Health check endpoint: DB + gRPC status
  - [ ] 5.4 Config via env vars: `DATABASE_URL`, `THALAMUS_URL`
  - _Requirements: R5.1, R5.2, R5.3, R5.4_

- [ ] 6. **Rate limiting**
  - [ ] 6.1 Rate limiter por `organization_id` (1000 req/min)
  - [ ] 6.2 Response headers: `X-RateLimit-Remaining`, `Retry-After`
  - _Requirements: R7.1, R7.2, R7.3_

- [ ] 7. **Demo cloud end-to-end (`cerebelum-demo-cloud`)**
  - [ ] 7.1 `pip install cerebelum-sdk` desde PyPI
  - [ ] 7.2 `cerebelum init my-demo` → scaffold
  - [ ] 7.3 `cerebelum login` → obtener JWT
  - [ ] 7.4 `cerebelum deploy workflow.py` → blueprint en engine
  - [ ] 7.5 `cerebelum run OrderWorkflow --input '{"order":{...}}'` → ejecutar
  - [ ] 7.6 `cerebelum logs <id> --follow` → streaming eventos
  - [ ] 7.7 Verificar multi-tenancy: otro token no ve los eventos
  - _Requirements: R6.1, R6.2, R6.3, R6.4, R6.5_

- [ ] 8. **Template `cerebelum init`**
  - [ ] 8.1 `workflow.py` template con `@step` + `@workflow` ejemplo
  - [ ] 8.2 `requirements.txt` con `cerebelum-sdk`
  - [ ] 8.3 `README.md` con los 3 pasos del quickstart
  - _Requirements: R2.2, R6.1, R6.2, R6.3_
