# Log

## [2026-07-14] fix | #89, #90, #91 — Destrabar Südlich: create_fund 401 en producción
**Diagnóstico**: 3 bugs encadenados bloqueaban el wizard de creación de fondos. **(1) named_results atom/string mismatch**: el path remoto en `state_handlers.ex` reconstruía la timeline con strings desde el blueprint, pero `data.results` usa átomos → `Map.get(atom_results, string_key)` → nil. Fix: usar `data.timeline` (átomos) directamente. **(2) create_fund no extraía datos**: referenciaba `id_data`, `fin_data`, etc. sin definirlas. Fix: extraer de parámetros nombrados. **(3) auth_token no se propagaba**: el engine no pasaba el JWT del usuario al worker. Fix: `execution_controller.ex` extrae token del header → `context.metadata` → `Map.put(step_inputs, "auth_token", token)`. **Verificado en prod**: ejecución `446337e6` con token OAuth2 PKCE de `c@zea.cl` → 6/6 completado, fondo creado en `fm_funds.funds` ($50M USD, DRAFT). **Archivos**: `state_handlers.ex`, `step_executor_test.exs`, `jwt_auth.ex` (Logger.info), `sudlich/workflows/fund_create_workflow.py`. **Issues**: #89, #90, #91, #92, #93, #94, #95, #96.

## [2026-07-13] fix | #79 — GET /api/v1/executions no devuelve ejecuciones creadas vía REST
**Diagnóstico**: Ejecuciones de blueprint guardaban `workflow_module: "Elixir.Cerebelum.WorkflowDelegatingWorkflow"` en el ExecutionStartedEvent, haciendo imposible distinguirlas por nombre de blueprint en el listado. **Fix**: Agregado campo `blueprint_name` al ExecutionStartedEvent y query de listado usa `COALESCE(blueprint_name, workflow_module)`. Además se encontraron bugs pre-existentes: el controller no pasaba `workflow_name` a `EventStore.list_executions` y usaba `length(executions)` en vez del total real. **Archivos**: `events.ex`, `event_emitter.ex`, `event_store.ex`, `execution_controller.ex`. **Issues**: #79, #80, #81, #82, #83, #84, #85. **Validado**: filtro `?workflow=X` funciona, nuevo blueprint `demo_fix_79` aparece con su nombre real, `?workflow=no_existe` retorna 0.

## [2026-07-13] docs | Creado .wiki/ para memoria persistente del agente
Siguiendo el patrón LLM Wiki (Karpathy). Estructura: index.md, log.md, rules.md, features/, integrations/. Seed con features existentes (workflow engine, gRPC, HITL, event store, REST API, multi-tenancy, resurrection, blueprint registry) e integraciones (thalamus, cranium, fm_funds, postgres, redis, python-worker-sdk, docker).

## [2026-07-12] feat | REST API para executions con blueprint deploy
Endpoints CRUD de ejecuciones funcionando. POST /api/v1/executions crea ejecuciones desde blueprints registrados. GET por ID usa StateReconstructor para completed/failed. Auth vía JWT con introspection en Thalamus.

## [2026-07-10] feat | Fase G: Multi-tenancy & Rate Limiting (#37)
Organización A no ve ejecuciones de B. ETS table execution_orgs. Rate limiter con Hammer + Redis: 429 al exceder 1000 req/min. Issues: #65 (G1), #66 (G2).

## [2026-07-09] feat | Fase F: gRPC + Python Worker (#36)
Worker Python registrado en cerebelum vía gRPC. Workflow distribuido 5/5 steps completados. Eventos con organization_id en EventStore. Issues: #62 (F1), #63 (F2), #64 (F3).

## [2026-07-08] feat | Fase E: Validación Demo Cloud (#35)
Flujo completo OAuth2 → deploy blueprint → run workflow → logs streaming → doctor. Issues #54-#61.

## [2026-07-07] feat | Fase D: Validación REST API (#34)
Health check OK, JWT auth rechaza sin token (401), endpoints protegidos responden 200 con token válido. Issues #51-#53.

## [2026-07-06] feat | Fase C: Deploy en ZEA Platform (#33)
Docker compose up en EC2, Caddy routing cerebelum.zea.cl, Watchtower configurado. Terraform secrets + DNS. Issues #45-#50.

## [2026-07-05] feat | Fase B: Docker Image & CI/CD (#32)
Dockerfile multi-stage, GitHub Actions publish.yml, Release.migrate(). Issues #41-#44.

## [2026-07-04] feat | Fase A: Database Init (#31)
cerebelum_user + cerebelum_prod en init_aws.sh de ZEA. Issues #39-#40.
