# Astral Credit Protocol

![banner](./assets/banner.png)

Astral Credit Protocol es un mercado de crédito DeFi para EVM. El protocolo
permite aportar liquidez a vaults por activo, usar esos saldos como colateral,
abrir préstamos variables, acumular intereses con índices globales y sanear
posiciones mediante liquidaciones parciales.

El repositorio contiene contratos Solidity, adaptadores de precio, modelo de
tipos, motor de riesgo, tokens de recibo, vistas para integradores, scripts
locales y pruebas de Foundry.

## Características

- Vaults de colateral por activo con tokens de recibo ERC-20.
- Préstamos sobrecolateralizados con controles por mercado y por cuenta.
- Tipos variables de dos pendientes según utilización.
- Índices globales de deuda y suministro para acumular intereses.
- Oráculos configurables con control de staleness y precisión.
- Motor de riesgo externo para capacidad de borrow, health factor y
  liquidaciones.
- Liquidaciones parciales con close factor e incentivo configurable.
- Reservas del protocolo y reclamo por tesorería.
- Lenses para cuentas, mercados, tasas, capacidad y reportes operativos.
- Cola de gobernanza para cambios parametrizados.

## Componentes

```text
src/
  AstralCreditMarket.sol       Mercado principal y custodia
  access/                      Roles administrativos
  core/                        Protecciones comunes
  governance/                  Configuración batch y cola temporal
  interest/                    Modelo variable de dos pendientes
  interfaces/                  Superficies públicas
  lens/                        Consultas agregadas
  libraries/                   Matemáticas y tipos compartidos
  oracle/                      Router y sentinel de precios
  risk/                        Motor y políticas de riesgo
  tokens/                      Tokens de recibo de vault
  treasury/                    Controlador de reservas
```

## Modelo del protocolo

Cada mercado registra un activo de reserva. Los proveedores depositan el activo
y reciben un token de recibo que representa su participación en el vault. El
valor de esas participaciones evoluciona con los intereses pagados por
prestatarios y con el factor de reserva del mercado.

Los prestatarios pueden abrir deuda mientras el valor ajustado de su colateral
supere el valor ajustado de sus préstamos. Los parámetros relevantes son:

- loan-to-value;
- umbral de liquidación;
- incentivo de liquidación;
- close factor;
- supply cap y borrow cap;
- factor de reserva;
- antigüedad máxima del precio.

Las operaciones que modifican balances acumulan antes los intereses del mercado
afectado. La deuda individual se expresa mediante principal y checkpoint de
índice; el saldo actual se calcula contra el índice global vigente.

## Seguridad y operación

- Roles separados para gobierno, riesgo, pausa, tesorería y publicación de
  precios.
- Validación de oráculos por frescura, precisión y disponibilidad.
- Caps por mercado para suministro y deuda.
- Health factor y close factor calculados por el motor de riesgo.
- Vistas on-chain para integradores, dashboards y monitores operativos.

La política de seguridad está en [SECURITY.md](./SECURITY.md).

## Requisitos

- Foundry con `forge`, `cast` y `anvil`.
- Git para instalar `forge-std` cuando sea necesario.
- Bash o PowerShell para scripts auxiliares.

Comprueba el entorno:

```bash
forge --version
cast --version
anvil --version
```

## Instalación

```bash
git clone <repository-url>
cd AstralCreditProtocol
forge install foundry-rs/forge-std --no-git --shallow
forge build
```

## Pruebas

Suite completa:

```bash
forge test
```

Validación local equivalente a CI:

```bash
bash scripts/ci.sh
```

Las pruebas públicas cubren depósitos, retiradas, apertura de préstamos,
capacidad de borrow, amortización, acumulación de intereses, cambios de precio,
health factor y liquidaciones parciales.

## Desarrollo local

Ejecuta una cadena local:

```bash
anvil
```

Despliegue base:

```bash
forge script script/DeployAstral.s.sol:DeployAstral \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

Variables esperadas por el script:

```text
PRIVATE_KEY=<deployer-private-key>
ASTRAL_TREASURY=<treasury-address>
```

## CI

El flujo de CI ejecuta:

```bash
forge fmt --check
forge build
FOUNDRY_PROFILE=ci forge test
bash scripts/check-loc.sh
```

## Licencia

MIT. Consulta [LICENSE](./LICENSE).
