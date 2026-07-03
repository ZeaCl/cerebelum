# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 0.1.x   | ✅ Active          |

## Reporting a Vulnerability

**Do not open a public issue.** Report security vulnerabilities privately to:

📧 **c@zea.cl**

We respond within 48 hours. Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Security Model

Cerebelum uses the following security mechanisms:

### Authentication
- **JWT Bearer tokens** validated against Thalamus OAuth2 provider
- JWKS endpoint for public key verification
- Token introspection for active session validation
- All API endpoints require authentication (except `/health`)

### Multi-tenancy
- Every execution and event is scoped to an `organization_id` from the JWT
- Cross-organization data access is blocked at the database query level
- Organization ID is extracted from the JWT claims and never from client input

### Rate Limiting
- Default: 1000 requests/minute per organization
- Configurable via `config :cerebelum, rate_limit_per_minute: N`
- Returns HTTP 429 with `Retry-After` header

### Environment
- All secrets via environment variables (never in code)
- `SECRET_KEY_BASE` required for production
- `DATABASE_URL` with connection string (supports SSL)
- CORS origins explicitly configured

## Best Practices

- Rotate `SECRET_KEY_BASE` regularly
- Use separate database users for production (as configured in `init_aws.sh`)
- Keep Thalamus JWKS URL behind internal network (not publicly routable)
- Monitor rate limit logs for abuse patterns
