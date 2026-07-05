"""Cerebelum Workflow — análisis de ventas (demo).

Este workflow demuestra 3 steps encadenados con delays simulados.
Modificalo para construir el tuyo.
"""

from cerebelum import step, workflow
import asyncio


@step
async def obtener_datos(context):
    """Simula consultar una API o base de datos externa."""
    await asyncio.sleep(0.8)
    return {
        "usuarios": 1_250,
        "ventas": 34_500_000,
        "pais": "CL",
    }


@step
async def procesar_datos(context, obtener_datos):
    """Transforma y enriquece los datos del paso anterior."""
    await asyncio.sleep(1.2)
    datos = obtener_datos
    return {
        "ticket_promedio": round(datos["ventas"] / datos["usuarios"]),
        "moneda": "CLP",
        "timestamp": "2026-07-05T14:15:00Z",
    }


@step
async def notificar(context, procesar_datos):
    """Envía el resultado final (simulado)."""
    await asyncio.sleep(0.5)
    resultado = procesar_datos
    return {
        "enviado": True,
        "destino": "slack#general",
        "mensaje": (
            f"💰 Ticket promedio: ${resultado['ticket_promedio']:,} "
            f"{resultado['moneda']}"
        ),
    }


@workflow
def analisis_ventas(wf):
    wf.timeline(obtener_datos >> procesar_datos >> notificar)


# ── Ejecutar ────────────────────────────────────────────

async def main():
    result = await analisis_ventas.execute({})
    print(f"Status: {result.status}")

if __name__ == "__main__":
    asyncio.run(main())
