# Requirements — Cerebelum Cloud

## R1: SDK Python instalable desde PyPI
**User Story:** As a Python developer, I want `pip install cerebelum-sdk` and start building workflows in 30 segundos.

- WHEN `pip install cerebelum-sdk` THEN the latest version SHALL be installed from PyPI
- WHEN `CEREBELUM_URL` env var is set THEN the SDK SHALL connect to that endpoint
- WHEN `CEREBELUM_TOKEN` env var is set THEN the SDK SHALL send `Authorization: Bearer <token>` in all requests
- IF no env vars are set THEN the SDK SHALL default to localhost:50051 (dev mode)

## R2: CLI instalable desde npm
**User Story:** As any developer, I want `npx @zea.cl/cerebelum-cli` and manage workflows from the terminal.

- WHEN `npx @zea.cl/cerebelum-cli` is run THEN help text SHALL display all commands
- WHEN `cerebelum init my-project` is run THEN a project template SHALL be scaffolded
- WHEN `cerebelum login` is run THEN the CLI SHALL open browser for OAuth2 and store token
- WHEN `cerebelum whoami` is run THEN the CLI SHALL show current user and org
- WHEN `cerebelum deploy workflow.py` is run THEN the blueprint SHALL be uploaded

### Workflow management
- WHEN `cerebelum workflow list` is run THEN registered workflows SHALL be displayed
- WHEN `cerebelum workflow show <id>` is run THEN details and code SHALL be shown
- WHEN `cerebelum workflow delete <id>` is run THEN the workflow SHALL be removed
- WHEN `cerebelum workflow run <id> --input '{}'` is run THEN the workflow SHALL execute

### Execution management
- WHEN `cerebelum execution list` is run THEN recent executions SHALL be displayed
- WHEN `cerebelum execution status <id>` is run THEN current state SHALL be shown
- WHEN `cerebelum execution logs <id> --follow` is run THEN events SHALL stream live
- WHEN `cerebelum execution stop <id>` is run THEN the execution SHALL be cancelled
- WHEN `cerebelum execution resume <id>` is run THEN a paused execution SHALL resume
- WHEN `cerebelum execution approve <id>` is run THEN HITL step SHALL be approved

### Operations
- WHEN `cerebelum worker list` is run THEN registered Python workers SHALL be displayed
- WHEN `cerebelum doctor` is run THEN health checks SHALL run against the engine

## R3: Auth via Thalamus JWT
**User Story:** As a developer, I use the same ZEA credentials for everything.

- WHEN a request arrives with `Authorization: Bearer <JWT>` THEN the engine SHALL validate it against Thalamus JWKS
- IF the JWT is valid THEN the engine SHALL extract `sub` and `organization_id`
- IF the JWT is invalid/expired THEN the engine SHALL return HTTP 401
- WHERE no auth header is present on protected routes THEN the engine SHALL return HTTP 401

## R4: Multi-tenancy con organization_id
**User Story:** As a platform operator, Org A cannot see Org B's workflows.

- WHEN a workflow is executed THEN `organization_id` SHALL be stored in the execution and all events
- WHEN listing executions THEN results SHALL be filtered by the caller's `organization_id`
- IF a request tries to access another org's execution THEN the engine SHALL return HTTP 403
- WHERE a blueprint is stored THEN it SHALL be scoped to the organization

## R5: Deploy en ZEA Platform
**User Story:** As a platform operator, Cerebelum corre como un servicio más del ecosistema ZEA.

- WHEN `docker compose up` is run THEN cerebelum SHALL start alongside postgres, caddy, thalamus
- WHEN cerebelum starts THEN it SHALL expose `/health` with DB and gRPC status
- WHERE Caddy is configured THEN `cerebelum.zea.localhost` SHALL route to the engine
- WHEN the engine starts THEN it SHALL read `THALAMUS_URL` and `DATABASE_URL` from env vars

## R6: Crear workflow en 3 pasos (Día 1)
**User Story:** As a new developer, I want to go from zero to a running workflow in under 5 minutos.

- WHEN a dev follows the quickstart THEN step 1 SHALL be `pip install cerebelum-sdk`
- WHEN a dev follows the quickstart THEN step 2 SHALL be writing a `.py` file with `@step` + `@workflow`
- WHEN a dev follows the quickstart THEN step 3 SHALL be `cerebelum run` (local or cloud)
- IF running locally THEN no auth or infra SHALL be required
- IF running in cloud THEN only `CEREBELUM_TOKEN` SHALL be needed

## R7: Rate limiting por organización
**User Story:** As a platform operator, I want to protect the service from abuse.

- WHEN an org exceeds 1000 requests/minute THEN the system SHALL return HTTP 429
- WHERE a PAT is provided THEN the system SHALL apply the token's configured rate limit
- IF rate limit is exceeded THEN the response SHALL include `Retry-After` header

## R8: Documentación para devs y AI agents
**User Story:** As a new developer (or AI agent), I want to discover Cerebelum from ZEA docs and start building immediately.

- WHEN a dev reads `zea/README.md` THEN Cerebelum SHALL appear in the services table
- WHEN `llms.txt` is accessed THEN it SHALL include Cerebelum API endpoints, auth, and quickstart
- WHEN `zea/docs/index.html` is accessed THEN Cerebelum SHALL be listed with port and URL
- WHERE SDK links are provided THEN they SHALL point to npm and PyPI
