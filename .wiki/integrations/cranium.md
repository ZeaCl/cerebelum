# Cranium — API Backend

- **URL**: `http://cranium:4000` (interno)
- **Uso en Cerebelum**: API backend de ZEA Platform

## Relación

Cranium es el API backend principal de ZEA. Cerebelum es un servicio independiente
que expone su propia REST API. No hay dependencia directa runtime — la integración
es a nivel de plataforma (misma network, mismo sistema de auth vía Thalamus).

## Similitudes

- Ambos usan Elixir/Phoenix
- Ambos validan JWT vía Thalamus
- Ambos están en `zea_network_local` y ruteados por Caddy

## Referencia

- Repo: `ZeaCl/cranium`
