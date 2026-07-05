# Plan: Simplified Dev Experience

- **Hash**: `20260705-190431-acc9a63`
- **Engine**: ZeaCl/cerebelum @ acc9a63
- **SDK**: ZeaCl/cerebelum-python @ d62485d
- **Objetivo**: 3 comandos. `cerebelum run workflow.py` hace todo.

---

## J1. SDK: `python -m cerebelum.worker`

Worker genérico en el SDK. Auto-descubre steps del `workflow.py` en cwd.

- [ ] J1.1. Crear `cerebelum/worker.py` con `__main__` (poll loop genérico)
- [ ] J1.2. Auto-import: busca `workflow.py` en cwd, registra `@step` functions
- [ ] J1.3. Conexión mTLS usando certs de `~/.cerebelum/certs/`
- [ ] J1.4. Bump version, build, publish a PyPI

### Tests
- `python -m cerebelum.worker` en un dir con workflow.py → registra steps → poll loop
- Sin workflow.py → error claro

---

## J2. CLI: `cerebelum run workflow.py`

Reescribe `smart-run.ts`. Un solo comando, un solo argumento (el archivo).

- [ ] J2.1. `cerebelum run workflow.py` → login → certs → deploy → worker → execute → live logs
- [ ] J2.2. Usa `python -m cerebelum.worker` del SDK (no genera scripts custom)
- [ ] J2.3. `cerebelum run` sin argumentos → error: "usá: cerebelum run workflow.py"
- [ ] J2.4. `cerebelum logs` → última ejecución (sin --follow)
- [ ] J2.5. `cerebelum logs <id>` → comportamiento actual
- [ ] J2.6. `cerebelum status` → se mantiene igual

### Tests
- `cerebelum run workflow.py` → flujo completo ✅
- `cerebelum run` → error con ayuda ✅
- `cerebelum logs` → última ejecución ✅
- `cerebelum status` → estado ✅

---

## Dependencias

```
J1 (worker en SDK) → J2 (CLI usa python -m cerebelum.worker)
```
