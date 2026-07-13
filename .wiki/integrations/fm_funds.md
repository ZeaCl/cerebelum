# fm_funds — Fund Management

- **URL**: `http://fm_funds:4082` (interno)
- **Uso en Cerebelum**: Workflows de creación y gestión de fondos

## Workflows

Cerebelum ejecuta workflows que interactúan con fm_funds:
- `fund_create_workflow` — Creación de fondo con HITL approval
- Steps se comunican vía REST a fm_funds endpoints

## Plataforma

Ambos servicios comparten:
- Misma network (`zea_network_local`)
- Misma auth (JWT vía Thalamus)
- Misma DB host (postgres, schemas separados)

## Referencia

- Repo: `ZeaCl/zea/domains/fundmanagement_subdomains_libs/fm_funds`
