# Changelog

All notable changes to Cerebelum will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-07-03

### Added
- Deterministic workflow execution engine with event sourcing
- Graph-based workflow DSL (timeline, branch, diverge, cycles, back_to)
- REST API with Phoenix (health, workflows, executions, workers)
- gRPC server for multi-language worker support (protobuf)
- JWT authentication via Thalamus JWKS + token introspection
- Multi-tenancy with `organization_id` scoping
- Rate limiting per organization (ETS-based, 1000 req/min default)
- Workflow resurrection and hibernation for long-running workflows
- Dead Letter Queue (DLQ) for failed workflow steps
- Event store with PostgreSQL partitioning and 640K+ events/sec throughput
- 18 event types: ExecutionStarted, StepExecuted, BranchTaken, etc.
- Time-travel debugging via state reconstruction from events
- Python SDK (`cerebelum-sdk`) with local + distributed mode
- TypeScript/Node.js CLI (`@zea.cl/cerebelum-cli`) — 16 commands
- Multi-stage Dockerfile with GitHub Container Registry publishing
- Integration with ZEA Platform (docker-compose, Caddy, Watchtower)
- Terraform infrastructure (AWS EC2, Cloudflare DNS, secrets)

### SDKs
- Python: `@step` + `@workflow` decorators, local mode, gRPC distributed mode
- TypeScript: Workflow builder, gRPC client, CLI tooling

[0.1.0]: https://github.com/ZeaCl/cerebelum/releases/tag/v0.1.0
