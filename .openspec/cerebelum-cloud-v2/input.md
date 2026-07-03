# Input — Cerebelum Cloud: Full Developer Experience

## Propósito
Definir la experiencia completa de un desarrollador usando Cerebelum como servicio cloud en ZEA Platform, desde el primer `pip install` hasta workflows corriendo en producción con multi-tenancy y JWT auth.

## Alcance

**IN — Journey del desarrollador:**
1. Instalar SDK/CLI (`pip install cerebelum-sdk`, `npm i @zea.cl/cerebelum-cli`)
2. Crear workflow local en Python (sin engine, sin infra)
3. Autenticarse con ZEA (Thalamus OAuth2 → JWT)
4. Desplegar workflow al cloud (`cerebelum deploy`)
5. Ejecutar y monitorear desde CLI/SDK
6. Ver logs/eventos en tiempo real

**IN — Producción:**
- Cerebelum como servicio dentro de ZEA Platform (ya es dependencia en `mix.exs`)
- JWT auth via Thalamus (ya configurado en ZEA runtime)
- Multi-tenancy por `organization_id`
- Docker compose con Caddy reverse proxy
- Health checks y monitoreo

**OUT — Lo que NO cubre esta spec:**
- UI de workflow builder (es Cranium piece separada)
- Billing / pricing
- CI/CD pipelines específicos

## Contexto — Lo que YA existe en producción

### ZEA Platform (`/Users/dev/Documents/zea/zea`)
```elixir
# mix.exs
{:cerebelum_core, path: "../cerebelum-core"}
```
- Monolito Elixir/Phoenix con Caddy reverse proxy
- Thalamus corriendo como servicio separado (`THALAMUS_URL`)
- PostgreSQL compartido
- Docker + docker-compose para local
- Terraform + AWS para producción

### ZEA runtime config (ya existe)
```elixir
config :zea, :thalamus,
  url: System.get_env("THALAMUS_URL"),
  jwks_url: System.get_env("THALAMUS_URL") <> "/.well-known/jwks.json"
```

### Cerebelum Engine (lo que acabamos de construir)
- DSL, event sourcing, REST API, gRPC ✅
- Python distributed mode (blueprint → worker) ✅
- SDKs: Python (GitHub), TypeScript (GitHub) ✅
- CLI: TypeScript, funcional ✅

## Lo que FALTA para la experiencia cloud

### Developer Experience (Día 1)
1. **SDK Python publicable**: `pip install cerebelum-sdk` desde PyPI (hoy solo GitHub)
2. **CLI publicable**: `npx @zea.cl/cerebelum-cli` (hoy solo local)
3. **Auth en SDK/CLI**: leer `CEREBELUM_TOKEN` env var
4. **Deploy command**: subir blueprint al engine cloud
5. **Logs/streaming**: ver eventos en tiempo real

### Producción
1. **JWTAuth Plug**: validar JWT contra Thalamus JWKS
2. **Multi-tenancy**: `organization_id` en eventos y ejecuciones
3. **Caddy routing**: exponer cerebelum en `cerebelum.zea.localhost`
4. **Docker**: container listo para prod

## Stakeholders
- Devs Python/TypeScript que quieren workflows sin infra
- Equipo ZEA Platform (opera la infra)
- Organizaciones multi-tenant
