# Integración

## Lecturas tipadas

`AstralCreditClient` recibe un transporte mínimo compatible con cualquier RPC o
cliente EVM. No impone una librería de firma.

```typescript
const client = new AstralCreditClient(transport, market, riskEngine);
const markets = await client.marketCount();
const debt = await client.borrowBalance(asset, account);
```

## Unidades

Las cantidades contractuales usan unidades nativas. El SDK usa `bigint` en toda
operación económica. No conviertas a `number`; la precisión de JavaScript no es
suficiente para WAD o ray.

## Confirmación de estado

Los eventos sirven para indexar, pero una decisión debe leer almacenamiento.
Después de una transacción, confirma receipt, bloque y nuevo estado. Un keeper
debe recalcular su lote cuando cambia precio, índice, cash o parámetros.

## Errores habituales

| Error | Acción |
| --- | --- |
| `ProtocolPaused` | Detener reintentos automáticos |
| `MarketFrozen` | Mostrar estado y esperar gobierno |
| `SupplyCapExceeded` | Reducir importe o seleccionar mercado |
| `BorrowCapExceeded` | Refrescar capacidad |
| `StaleOrInvalidPrice` | Detener operación económica |
| `InsufficientLiquidity` | Esperar repay/supply o reducir importe |
| `UnauthorizedRole` | Corregir identidad; no reintentar |

## Seguridad del integrador

Valida chain ID, direcciones, selectors, decimales y slippage. Simula antes de
firmar. No almacenes claves o RPC privados en el repositorio ni logs.
