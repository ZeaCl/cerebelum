# Requirements — Cerebelum Cloud

## Introduction
Cerebelum Cloud permite a desarrolladores ejecutar workflows en infraestructura ZEA sin montar servidores propios. Autenticación vía Thalamus JWT, multi-tenancy por organización, y SDKs públicos para Elixir, Python y TypeScript.

---

## Requirements

### R1: Autenticación vía Thalamus JWT
**User Story:** As a developer, I want to use my ZEA credentials to access Cerebelum, so that I don't need separate auth.

#### Acceptance Criteria
1. WHEN a request arrives at the REST API THEN the system SHALL validate the JWT Bearer token against Thalamus JWKS endpoint
2. IF the JWT is valid THEN the system SHALL extract `sub`, `organization_id`, and `scopes` from the claims
3. IF the JWT is expired or invalid THEN the system SHALL return HTTP 401 with `{"error": "unauthorized"}`
4. WHERE a gRPC request is received THEN the system SHALL validate the JWT from gRPC metadata headers

### R2: Multi-tenancy por organización
**User Story:** As a platform operator, I want each organization's workflows isolated, so that client A cannot see client B's data.

#### Acceptance Criteria
1. WHEN a workflow is executed THEN the system SHALL store `organization_id` in the execution context and all events
2. WHEN listing executions THEN the system SHALL filter results by the caller's `organization_id`
3. IF a user is not a member of the organization THEN the system SHALL return HTTP 403
4. WHERE a blueprint is submitted THEN it SHALL be scoped to the caller's organization

### R3: SDKs públicos instalables
**User Story:** As a Python developer, I want to `pip install cerebelum-sdk` and start building workflows immediately.

#### Acceptance Criteria
1. WHEN a developer runs `pip install cerebelum-sdk` THEN they SHALL get the latest stable version from PyPI
2. WHEN a developer runs `npm i @zea.cl/cerebelum` THEN they SHALL get the TypeScript SDK from npm
3. WHEN `CEREBELUM_URL` env var is set THEN the SDK SHALL connect to that endpoint instead of localhost
4. IF `CEREBELUM_TOKEN` env var is set THEN the SDK SHALL include it as `Authorization: Bearer` header

### R4: CLI instalable
**User Story:** As a developer, I want to manage workflows from the terminal without writing code.

#### Acceptance Criteria
1. WHEN a developer runs `npx cerebelum` THEN the CLI SHALL display available commands
2. WHEN `cerebelum run OrderWorkflow --input '{"order":{...}}'` is executed THEN the CLI SHALL submit the workflow and show results
3. WHEN `cerebelum logs <execution_id>` is executed THEN the CLI SHALL stream execution events in real-time
4. IF the CLI cannot connect THEN it SHALL show a clear error message with the configured URL

### R5: Deploy cloud listo para producción
**User Story:** As a platform operator, I want to deploy Cerebelum with one command.

#### Acceptance Criteria
1. WHEN `docker compose up -d` is executed THEN the system SHALL start the engine, API, and database
2. WHEN the service starts THEN it SHALL expose a `/health` endpoint that returns database and gRPC status
3. IF the database is unreachable THEN the health endpoint SHALL return status `degraded`
4. WHERE JWKS URL is configured THEN the system SHALL validate tokens against Thalamus

### R6: Rate limiting y API keys
**User Story:** As a platform operator, I want to protect the service from abuse.

#### Acceptance Criteria
1. WHEN an organization exceeds 1000 requests/minute THEN the system SHALL return HTTP 429
2. WHERE a PAT (Personal Access Token) is provided THEN the system SHALL apply the token's configured rate limit
3. IF rate limit is exceeded THEN the response SHALL include `Retry-After` header
