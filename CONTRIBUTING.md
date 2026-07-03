# Contributing to Cerebelum

Thanks for your interest in contributing! Cerebelum is a deterministic workflow orchestration engine built with Elixir/OTP.

## Development Setup

```bash
git clone https://github.com/ZeaCl/cerebelum.git
cd cerebelum

# Install dependencies
mix deps.get

# Setup database
mix ecto.create
mix ecto.migrate

# Run tests
mix test

# Interactive shell
iex -S mix
```

### Requirements

- **Elixir** 1.18+
- **Erlang/OTP** 27+
- **PostgreSQL** 12+

## Project Structure

```
lib/cerebelum/
├── workflow/          # DSL, validators, versioning
│   └── dsl/           # timeline, branch, diverge parsers
├── execution/         # Engine, step executor, parallel executor
├── api/               # REST controllers, plugs (JWTAuth, RateLimiter)
├── infrastructure/    # Worker registry, task router, DLQ
├── persistence/       # Event store, workflow pauses
├── event/             # 18 event types
└── application.ex     # Supervision tree
```

## Workflow

1. **Fork** the repo
2. **Create** a feature branch: `git checkout -b feat/my-feature`
3. **Write tests** first (TDD)
4. **Make changes** and run: `mix test && mix format && mix credo`
5. **Commit** using [Conventional Commits](https://www.conventionalcommits.org/): `feat: add X`, `fix: resolve Y`, `docs: update Z`
6. **Push** and open a **Pull Request**

## Code Standards

- Follow Clean Architecture layers (domain → application → infrastructure → presentation)
- Public functions must have `@doc` and `@spec`
- Tests use ExUnit with property testing (StreamData) where appropriate
- Pass `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`

## Testing

```bash
mix test                    # All tests
mix test.clean              # With clean database
mix coveralls.html          # Coverage report
open cover/excoveralls.html
```

## Questions?

Open a [GitHub Discussion](https://github.com/ZeaCl/cerebelum/discussions) or issue.
