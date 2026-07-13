# Blueprint Registry

Registro en memoria (ETS) de workflow blueprints deployados vía gRPC.

## Funcionamiento

- Workers Python deployan blueprints vía gRPC `DeployWorkflow`
- Se almacenan en ETS table `:blueprint_registry`
- Clave: workflow name (string)
- Valor: mapa con `language`, `steps`, `version`, `definition`

## API

```elixir
# Almacenar
BlueprintRegistry.store_blueprint("my_workflow", %{language: "python", steps: [...]})

# Recuperar
{:ok, blueprint} = BlueprintRegistry.get_blueprint("my_workflow")

# Eliminar
BlueprintRegistry.delete_blueprint("my_workflow")
```

## Uso en REST API

Cuando se crea una ejecución vía `POST /api/v1/executions`:
1. Busca el blueprint en BlueprintRegistry
2. Si existe → ejecuta vía WorkflowDelegatingWorkflow
3. Si no → busca módulo Elixir compilado

## Archivo clave

- `lib/cerebelum/infrastructure/blueprint_registry.ex`
