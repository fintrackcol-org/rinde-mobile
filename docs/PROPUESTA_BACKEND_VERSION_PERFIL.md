# Propuesta de backend: versión del perfil financiero

Estado: **propuesta, NO aplicada. Necesita la aprobación de David antes de tocar el backend.**
Fecha: 23 de noviembre de 2026. Repositorio afectado: `fintrackcol-org/fintrack` (backend y PWA).

## Qué se pide aprobar

1. Agregar una columna `version` a `perfiles_financieros` y aceptar un `expectedVersion` opcional en las escrituras del perfil (opción A).
2. Que la bienvenida se aplique una sola vez por cuenta (opción E).
3. Fusionar el cambio en `develop` **y** en `main`.
   - En `develop` despliega QA y en `main` despliega producción.
   - Hoy la idempotencia de la etapa 3 solo está en `main`.

Mientras no se apruebe, en la app **Corregir saldo y «Tu sueldo» quedan en solo lectura en cuentas reales**. La regla está en `canWriteBalance`, en `lib/features/money/application/money_writer.dart`, y se activa sola cuando el servidor empiece a mandar `version`.

## El problema

`PUT /money-profile` y `POST /money-profile/welcome` **reemplazan** el saldo, el tipo de ingreso y los días de pago.

- Si el saldo llega distinto, el servidor reinicia `saldo_at = now()` (`backend/src/repositories/money-profile.repository.js:44-45`).
- Desde `saldo_at` se cuentan los gastos y los ingresos.
- La tabla no tiene versión, así que **gana el último que escribe**, aunque escriba con datos viejos.

Casos concretos:

| Caso | Qué pasa hoy |
|---|---|
| David corrige su saldo en el celular. Una pestaña vieja de la web guarda «Tu sueldo» con el saldo que tenía al abrirse | El saldo vuelve al viejo, `saldo_at` se reinicia y los gastos anotados entre medio dejan de contar. **No queda fila en `ajustes_saldo`**: nadie ve qué pasó |
| La app corrige el saldo con `resetBalance`, la respuesta se pierde (Render tarda) y se repite | Se crea un segundo ajuste y lo anotado entre los dos envíos queda absorbido |
| Una bienvenida terminada tarde en otro dispositivo, con otra llave | Pisa una corrección más nueva |
| El saldo «antes» del ajuste se lee fuera de la transacción (`money-profile.service.js:68-71`) | Con un gasto simultáneo, la diferencia del ajuste puede no cuadrar |

La web ya tiene este riesgo hoy, porque «Tu sueldo» manda el saldo cargado al abrir. La app no lo hereda gracias a la regla de solo lectura.

## Alternativas estudiadas

| Opción | Qué cubre | Decisión |
|---|---|---|
| **A. Columna `version` y `expectedVersion` opcional en el cuerpo** | Saldo, tipo, días y reintentos | **Recomendada** |
| A′. Lo mismo con `If-Match` y ETag | Igual | No: el ETag automático de Express cambia con cada movimiento, y uno propio podría responder 304 con la plata vieja |
| B. `expectedBalanceAt` | Solo el saldo | No: pierde los microsegundos y no ve los cambios de tipo ni de fuentes |
| C. `updated_at` | Toda la fila | No: el tutorial lo sube y daría conflictos falsos |
| D. `If-Unmodified-Since` | — | No: su resolución es de un segundo |
| **E. La bienvenida se aplica una sola vez** | Bienvenida tardía y «omitir» con una copia vieja | **Complemento**, sin migración |
| F. `Idempotency-Key` en el PUT | Solo reintentos | Innecesaria con A |
| G. PUT parcial | Borrados accidentales | No hace falta: el cliente manda siempre los tres campos |

## Cambio propuesto

1. **Migración** `db/patches/039_perfil_version.sql`:
   ```sql
   ALTER TABLE perfiles_financieros ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 1;
   ```
   - En PostgreSQL 11 o más nuevo no reescribe la tabla.
   - Se registra en `backend/src/config/migrations.js`, después de la 038, y en `db/init/01_schema.sql`.
   - No cambia el conteo de tablas del CI (45).
2. **`GET /money-profile`** devuelve `version`, o `0` si no hay perfil.
3. **`PUT /money-profile`, `POST /money-profile/welcome` y `PUT /money-profile/sources`** aceptan `expectedVersion` (entero, opcional).
   - SQL: `… DO UPDATE SET …, version = p.version + 1 WHERE $n::int IS NULL OR p.version = $n RETURNING version`.
   - Si no vuelve ninguna fila, responde `409 PROFILE_CHANGED` con «Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.» y no aplica nada.
   - En la bienvenida el orden es: primero la llave (una repetición responde 200), después la versión. Ante un 409 se libera la llave.
   - Cambiar las fuentes sube la versión; el tutorial y la alerta de liquidez no.
4. **El saldo «antes» del ajuste** se lee dentro de la transacción, con `SELECT … FOR UPDATE`.
5. **Bienvenida una sola vez (E).**
   - Si `bienvenida_at` ya existe y no es una repetición de la misma llave, no toca nada.
   - Responde 200 con el perfil y la cabecera `Welcome-Already-Done: true`, que se agrega a `exposedHeaders` (`backend/src/app.js:65`).
   - «Omitir» pasa a ser solo `bienvenida_at = COALESCE(bienvenida_at, now())`.
6. **Textos y documentación:**
   - El mensaje nuevo, en `backend/src/i18n/locales/{en,pt}`.
   - `openapi.yaml` documenta `version`, `expectedVersion` y `PROFILE_CHANGED`.
   - Ojo: el `openapi.yaml` de `main` hoy no es YAML válido, y eso ya estaba así.

## Compatibilidad

- `expectedVersion` es opcional. **Un cliente que no lo manda funciona igual que hoy**: la PWA actual y la app actual. Ningún otro servicio del backend escribe el perfil.
- El campo nuevo de `GET` no rompe a nadie: los clientes ignoran lo que no conocen.
- Orden de despliegue:
  1. Backend, en `develop` (QA) y `main` (producción).
  2. La PWA manda `expectedVersion`.
  3. La app se activa sola al ver `version`.

## Impacto

**PWA** (sin tocar hasta aprobar):

- Mandar `expectedVersion: data.version` en:
  - `MiPlata.jsx` («Tu sueldo»)
  - `MoneyPayments.jsx`
  - `FixBalance.jsx`
  - `Welcome.jsx`
  - el guardado de fuentes de `IncomeOverview.jsx`
- Ante un 409: recargar el perfil y mostrar el mensaje.
- Actualizar el mock `frontend/src/mocks/handlers.js` y el typedef de `moneyProfileService.js`.
- De paso se corrige el riesgo que **la web ya tiene hoy** con «Tu sueldo».

**Rinde Mobile:**

- `MoneyProfile.version` ya se lee (llega `null` mientras el servidor no lo mande).
- Faltaría:
  - mandar `expectedVersion` en el saldo, la bienvenida y las fuentes;
  - ante `PROFILE_CHANGED`, volver a leer y mostrar el texto, sin reintentar.

## Pruebas del backend que llevaría

- `GET` devuelve `version` (0 sin perfil).
- Dos `PUT` con la misma `expectedVersion`: uno da 200 y el otro 409, sin ajuste ni cambio de `saldo_at` en el segundo.
- `PUT` sin `expectedVersion`: se comporta igual que hoy.
- Reintento de una corrección con la versión vieja: 409, y lo anotado entre medio sigue contando.
- Bienvenida con otra llave después de una corrección: no toca nada y responde `Welcome-Already-Done`. Con la misma llave: 200 con `Idempotent-Replayed`.
- Un 409 por versión en la bienvenida deja la llave libre.
- `PUT /sources` sube la versión; el tutorial no.
- Con un gasto concurrente, el ajuste cuadra.
- Las pruebas de hoy (`money-profile.test.js`, `money-profile-idempotency.test.js`) siguen en verde.

## Riesgos y reversa

- **Más 409 en pestañas viejas de la web.** Es lo que se busca, pero hay que explicarlo al equipo.
- **E cambia el significado de «omitir»** cuando la bienvenida ya se hizo. Hoy ningún flujo de la PWA lo usa así.
- **Liberar la llave en un 409** hay que probarlo con concurrencia.
- **No cubre los pagos fijos** (`compromisos`), que tienen su propia tabla. Sería otra propuesta.
- **Reversa:** los clientes dejan de mandar `expectedVersion` y la columna se ignora. Si hiciera falta quitarla, se borra con `DROP COLUMN` en un parche posterior.

## Lo que NO se hizo

No se tocó el backend, no se corrió ninguna migración y no se cambió producción ni QA. Este documento es solo la propuesta.
