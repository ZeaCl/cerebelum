# Input — Cerebelum Cloud

## Propósito
Permitir que cualquier desarrollador use Cerebelum como servicio cloud, sin necesidad de montar infraestructura propia. Mismo modelo que Thalamus/Cranium en ZEA Platform.

## Alcance
- **IN**: Autenticación vía Thalamus JWT
- **IN**: Multi-tenancy — workflows y ejecuciones scoped por `organization_id`
- **IN**: SDKs públicos: `@zea.cl/cerebelum` (npm), `cerebelum-sdk` (PyPI)
- **IN**: CLI: `npx cerebelum` / `pip install cerebelum-cli`
- **IN**: REST API y gRPC con JWT auth
- **IN**: Deploy cloud con Docker + docker-compose
- **OUT**: On-premise (ya cubierto por el demo actual)
- **OUT**: UI de workflow builder (es Cranium piece, spec separada)

## Contexto
**Lo que YA existe:**
- Engine: DSL, event sourcing, REST API, gRPC ✅
- Python SDK: `cerebelum-sdk` en GitHub, local + distributed ✅
- TypeScript SDK: `cerebelum-js` en GitHub ✅
- CLI: TypeScript, funcional ✅
- Thalamus: OAuth2, JWT, organizaciones, PAT ✅

**Lo que FALTA para cloud:**
- JWT validation en la REST API
- `organization_id` scoping en eventos/ejecuciones
- SDKs publicados en npm/PyPI (hoy solo GitHub)
- CLI instalable (`npx cerebelum`, `pip install cerebelum-cli`)
- Config de deploy cloud (Docker, env vars, health checks)
- Rate limiting, API keys

## Patrón a seguir (Thalamus)

```
Thalamus:
  - Repo: ZeaCl/thalamus
  - SDK: @zea.cl/auth (npm), thalamus-js
  - Auth: OAuth2 con JWT
  - Deploy: Docker + fly.io / VPS
  - CLI: npx zea-auth-init
  - API: REST con JWT Bearer token

Cerebelum Cloud debería seguir el mismo patrón:
  - SDK: @zea.cl/cerebelum (npm), cerebelum-sdk (PyPI)
  - Auth: Thalamus JWT (mismo token)
  - Deploy: Docker
  - CLI: npx cerebelum init, cerebelum run, cerebelum logs
  - API: REST + gRPC con JWT Bearer token
  - Scoping: organization_id en todas las operaciones
```

## Stakeholders
- Devs que quieren workflows sin infra
- Operadores de ZEA Platform
- Organizaciones con múltiples equipos
