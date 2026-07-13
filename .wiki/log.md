# Log

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
