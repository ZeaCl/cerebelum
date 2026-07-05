# Plan: Publicar SDKs + create-cerebelum

- **Hash**: `20260705-122548-7ec618d`
- **Engine**: ZeaCl/cerebelum @ 7ec618d
- **Board**: https://github.com/orgs/ZeaCl/projects/6
- **Objetivo**: Publicar paquetes en PyPI/npm para que `npx create-cerebelum` funcione en cualquier máquina.

---

## H1. Python SDK → PyPI

`cerebelum-sdk` ya existe en `cerebelum-demo-cloud/.venv/lib/python3.14/site-packages/cerebelum/`.
Falta empaquetarlo y publicarlo.

- [ ] H1.1. Crear `pyproject.toml` y `setup.py` en un repo o directorio publishable
- [ ] H1.2. Build: `python -m build`
- [ ] H1.3. Publish: `twine upload dist/*`
- [ ] H1.4. Verificar: `pip install cerebelum-sdk` desde PyPI en entorno limpio

### Criterios de aceptación
- `pip install cerebelum-sdk` instala el paquete
- `from cerebelum import step, workflow` funciona
- `from cerebelum.distributed import Worker` funciona

---

## H2. CLI → npm

`@zea.cl/cerebelum-cli` ya tiene `package.json` y build listo en `cerebelum-core/cli/`.

- [ ] H2.1. Verificar `package.json` (name, version, bin, files)
- [ ] H2.2. Build: `npm run build`
- [ ] H2.3. Publish: `npm publish --access public`
- [ ] H2.4. Verificar: `npx @zea.cl/cerebelum-cli` muestra el help

### Criterios de aceptación
- `npx @zea.cl/cerebelum-cli` ejecuta el CLI
- `cerebelum login` funciona (OAuth2 PKCE)
- `cerebelum doctor` verifica conectividad

---

## H3. create-cerebelum → npm

Paquete scaffold que inicializa un proyecto Cerebelum desde cero.

- [ ] H3.1. Crear estructura del package:
  - `package.json` con bin `create-cerebelum`
  - `template/` con `workflow.py`, `README.md`
  - Script que: crea dir, copia template, `pip install cerebelum-sdk`, inicia `cerebelum login`
- [ ] H3.2. Publicar: `npm publish --access public`
- [ ] H3.3. Verificar: `npx @zea.cl/create-cerebelum my-project` crea el proyecto

### Criterios de aceptación
- `npx @zea.cl/create-cerebelum my-project` funciona en máquina limpia
- `cd my-project && python workflow.py` → `Status: completed`
- `cerebelum deploy workflow.py` → blueprint subido

---

## Dependencias entre fases

```
H1 (cerebelum-sdk en PyPI) ──┐
                              ├──→ H3 (create-cerebelum)
H2 (cerebelum-cli en npm) ───┘
```
