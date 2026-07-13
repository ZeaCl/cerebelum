# Thalamus — Auth & Identity

- **URL**: `http://thalamus:4000` (interno)
- **Uso en Cerebelum**: Validación JWT vía introspection

## Introspection

Cerebelum valida tokens llamando a Thalamus `/oauth/introspect`:

```elixir
# lib/cerebelum/api/plugs/jwt_auth.ex
POST http://thalamus:4000/oauth/introspect
Body: {"token": "..."}
Response: {"active": true, "user_id": "...", "organization_id": "..."}
```

## Configuración

```elixir
config :cerebelum, :thalamus,
  introspection_url: "http://thalamus:4000/oauth/introspect"
```

## Variables de entorno

- `THALAMUS_URL` — URL base de Thalamus
- `CORS_ORIGINS` — Dominios permitidos para CORS

## Tokens válidos

- OAuth2 client_credentials (M2M)
- OAuth2 authorization_code (PKCE, usuario)

## Debugging

- Token no introspecta → verificar que Thalamus esté corriendo
- `{"active": false}` → token expirado o issuer no coincide (local vs prod)
