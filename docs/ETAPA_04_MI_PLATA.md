# Etapa 4 — Mi plata y planificación financiera

Rama de trabajo: `feat/etapa-4-mi-plata` (sale de `main` en `798a462`). Cada bloque se sube a esa
rama y a una PR hacia `main` **sin fusionar**: la fusión la decide David.

> Todas las capturas son **modo demostración** con datos sintéticos (usuario «Ana»). Nada se probó
> contra QA con sesión: falta una cuenta de prueba autorizada (ver «Backend y QA»).

## Resumen

| Bloque | Estado |
|---|---|
| 4A — Mi plata y perfil financiero («Cómo te entra la plata») | Hecho, probado y subido (ver «Git» del bloque) |
| 4B — Saldo, corregir saldo, plan y «¿De dónde sale?» | Pendiente |
| 4C — Pagos recurrentes | Pendiente |
| 4D — Continuidad bienvenida → Mi plata → Inicio | Pendiente (el bloqueo por bienvenida a medias ya está en 4A) |

---

## Bloque 4A — Mi plata y perfil financiero

Fecha: 23 de noviembre de 2026.

### Qué tenía React (rama `main` de la web)

| Pieza | Dónde está en la web | En la app |
|---|---|---|
| Pantalla `/app/mi-plata` (variante de celular) | `pages/app/MiPlata.jsx`, `components/money/MiPlataMobile.jsx` | `MyMoneyScreen`, se abre encima del Inicio. Por ahora solo con la sección de 4A |
| Tarjeta «Cómo te entra la plata»: frase, «Ver más» / «Configurar», meta del día | `components/money/IncomeOverview.jsx:132-245` | `IncomeOverviewCard` |
| Hoja en modo vista: fuentes, «Págate un sueldo», colchón, «Salud y pensión» con «Recordármelo cada mes» | `IncomeOverview.jsx:212-241` | `IncomeSheet` (vista) |
| Hoja en modo edición: las cinco fuentes, montos, días, «Guardar» (`PUT /money-profile/sources`) | `IncomeOverview.jsx:194-211`, `IncomeSourcesFields.jsx` | `IncomeSheet` (edición), con las mismas casillas de la bienvenida |
| Resúmenes por tipo y frase principal | `lib/incomeSources.js:112-130` | `income_rules.dart` (`incomeHeadline`, `sourceSummary`) |
| «Tu sueldo» (tipo heredado, `PUT /money-profile`) | `MiPlata.jsx:119-173`, vive en `/app/mi-plata/pagos` | **No entra en 4A:** va con Pagos (4C) y en solo lectura hasta que exista la versión del perfil |
| «Crear mi colchón» / «Aportar al colchón» | `POST /vacas`, `/app/metas/:id` | **Fuera de alcance:** son del módulo Metas. El colchón se muestra solo como texto |

### Qué se hizo

- **Base común de Mi plata** (`lib/features/money/`):
  - Modelos de solo lectura del contrato. Lo que falta queda `null`, nunca 0.
  - `MoneyRepository`, con versión real y versión demo.
  - Proveedores por cuenta (`perAccount`).
  - `afterMoneyChange`, que tras un cambio confirmado refresca Mi plata y todo el Inicio.
  - `MoneyWriter`, que escribe sin reintentos solos (detalle abajo).
  - `canWriteBalance`: se deja lista para 4B y hoy no se usa en pantalla.
- **`PushedFrame`**: el marco de las pantallas que se abren encima, sacado de Anotar y de «En desarrollo». Ahora lo comparten las tres.
- **`/app/mi-plata` deja de estar «En desarrollo».** Se abre desde la tarjeta grande del Inicio y desde el aviso del Inicio. Sin historial, «Atrás» lleva a `/app`, como `backPath` en la web. Pagos (`/pagos`) y Corregir saldo (`/corregir`) siguen «En desarrollo».
- **Tarjeta y hoja con todos sus estados:**
  - Cargando: esqueleto que se anuncia como «Cargando…».
  - Error: aviso con «Reintentar».
  - Recarga fallida: se ve lo último que llegó con «Lo que ves puede estar desactualizado…».
  - Vacío: «Cuéntanos cómo…» con «Configurar».
  - Además: halar para recargar y montos ocultos, también para el lector de pantalla.
- **Errores de guardado:**
  - Un 422 se marca en su casilla (`sources[i].amount`, `low`, `high`, `lastMonths`).
  - El 401 y la falta de conexión salen en el aviso con el mensaje de siempre.
  - La hoja no se cierra con Atrás mientras guarda.
- **Demostración:**
  - Escenarios fijos («Plan listo», «Te faltan», «Estás en negativo», «Sin plan»): cifras calculadas a mano con la regla del servidor, y guardar da «Modo demostración: esta acción no llega a ningún servidor.».
  - Recorridos («Usuario nuevo», «Usuario con movimientos»): lo guardado persiste, la tarjeta calcula el mes normal y el flaco con la regla del servidor (`declaredMonth`) y el Inicio cambia.
  - El panel «DEMO» puede hacer fallar las tres llamadas nuevas.

### Escrituras y salvaguardas

| Escritura | Endpoint | Cuentas reales | Salvaguarda |
|---|---|---|---|
| Guardar fuentes | `PUT /money-profile/sources` | Sí | Ver la lista de abajo |
| «Recordármelo cada mes» (PILA) | `POST /money-profile/commitments` | Sí | El nombre es único: repetir da 409 y se muestra el mensaje del servidor. Si queda en duda, solo cuenta como hecho si coinciden el nombre, el día y el monto en centavos |
| Corregir saldo y «Tu sueldo» | `PUT /money-profile` | **No** (4B/4C) | Esperan la versión del perfil (propuesta de backend, pendiente de aprobación) |

Salvaguardas de «Guardar fuentes»:

- **Un envío a la vez** por operación y por cuenta: un segundo toque espera el mismo resultado y no manda otra petición.
- **En duda** (se venció la espera o el servidor respondió 5xx):
  - Se vuelve a leer `GET /income` y se compara por contenido.
  - Si ya está guardado, cuenta como hecho.
  - Si no se puede confirmar, se muestra el error y se refresca lo que se ve, por si el servidor lo aplicó después.
  - Nunca se reintenta solo.
- **Sin conexión o 4xx:** se devuelve tal cual. No salió o fue rechazado.
- **Bienvenida a medias:**
  - Si la bienvenida dejó fuentes sin guardar en este teléfono, Mi plata no envía nada y avisa «Primero terminemos de guardar tu bienvenida.».
  - Sin este bloqueo, al reabrir la app el reintento de la bienvenida pisaba lo guardado en Mi plata.
- **Después de guardar:** la hoja espera la relectura antes de volver a la vista. Así «Cambiar» nunca precarga lo de antes.

### Diferencias con la web y por qué

| Diferencia | Por qué |
|---|---|
| «Salud y pensión» solo se muestra con región Colombia y moneda COP | El servidor calcula la PILA con el salario mínimo colombiano sin mirar la moneda. Una cuenta en USD veía «aparta unos US$ 499.008» y el botón creaba ese pago. **Lo debe confirmar el equipo;** la otra salida es arreglarlo en el backend |
| «Págate un sueldo» no sale si el servidor manda 0 | El servidor redondea a 50 000 sin mirar la moneda. La web pinta un «0» suelto |
| La meta del día no sale si la meta es 0 | Evita «Llevas $ 0 de $ 0…» cuando las fuentes no tienen monto |
| El colchón sin meta y con sugerencia de 0 o menos no se muestra | La web diría «te sugerimos guardar $ 0» |
| Guardar refresca también el perfil y el Inicio | La web solo recargaba `/income`, aunque el servidor cambia `incomeType` y el plan |
| Mi plata se abre encima, sin barra de pestañas | La web muestra la barra con «Inicio» marcado. Pregunta abierta 13 del plan |
| Aviso bajo «Guardar» al quitar todas las fuentes | La web lo permite sin avisar y el plan pasa a «sin plan». **Texto nuevo** |

### Textos nuevos que requieren aprobación

| Español | Inglés | Portugués |
|---|---|---|
| Si guardas sin ninguna, dejamos de calcular cuánto tienes libre. | If you save with none, we stop calculating how much you have free. | Se salvar sem nenhuma, deixamos de calcular quanto você tem livre. |
| Primero terminemos de guardar tu bienvenida. | Let's finish saving your welcome first. | Primeiro vamos terminar de salvar suas boas-vindas. |
| {amount} cada quincena / {amount} cada semana (resumen de la mesada) | {amount} every two weeks / {amount} a week | {amount} por quinzena / {amount} por semana |

Las etiquetas del panel «DEMO» van solo en español, como el resto del panel.

### Revisión adversarial

- Un agente implementó el bloque y tres revisores independientes lo revisaron en solo lectura:
  - paridad con la web y el backend;
  - escritura y aislamiento;
  - interfaz y pruebas.
- Otro agente corrigió lo confirmado. Después lo verifiqué en el emulador.

| # | Hallazgo | Resultado |
|---|---|---|
| 1 | «Págate un sueldo» con $ 0 | Corregido, con prueba |
| 2 | Una bienvenida a medias pisaba lo guardado en Mi plata | Corregido (bloqueo con aviso), con prueba |
| 3 | La meta del día pintaba solo ceros | Corregido, con prueba |
| 4 | El éxito de la PILA dice «Cambia el día» y Pagos sigue «En desarrollo» | No es de código: fusionar 4A junto con 4C o después |
| 5 | Después de guardar, la hoja mostraba las fuentes viejas y «Cambiar» las reenviaba | Corregido (espera la relectura y avisa si falla), dos pruebas |
| 6 | La PILA «en duda» se confirmaba solo por el nombre | Corregido (nombre, día y monto), con prueba |
| 7 | «En duda» sin confirmar no refrescaba nada | Corregido, con prueba |
| 8 | La llave de un envío a la vez no distinguía dos pagos distintos | Corregido, con prueba |
| 9 | La escritura de la demo no es atómica | Hoy no se puede reproducir; queda para 4C |
| 10 | Guardar el repositorio al empezar el envío | Descartado: el cliente HTTP siempre usa la sesión actual |
| 11 | La PILA en cuentas que no son de Colombia | Corregido, **se aparta de la web** (ver arriba) |
| 12 | La prueba de «cerrar descarta lo editado» era débil | Reforzada |
| 13 | Faltaba la prueba de «no se cierra mientras guarda» | Agregada |
| 14 | La demo en USD escondía el 0 del sueldo propio | Cubierto con la prueba del punto 1 |
| 15 | En el emulador: en los recorridos, después de guardar la hoja mostraba la fuente y la tarjeta seguía diciendo «Cuéntanos…» | Corregido: la demo calcula el mes normal y el flaco con `declaredMonth`. Prueba con las cifras de «Plan listo» y «Te faltan» |

### Pruebas

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Sin hallazgos |
| `flutter test` | 1017 de 1017 en verde (eran 938 al cerrar la etapa 3) |
| `dart format --line-length 110` | Sin cambios pendientes |
| `gitleaks` sobre `lib` y `test` | Sin fugas |
| `save_model_test.dart` (guardado de la bienvenida) | En verde |
| Compilación Android (`flutter build apk --debug`, con demo) | Compila |
| Emulador Android 16 (API 36) | Capturas abajo |

Qué cubren las pruebas nuevas (`test/features/money/`):

- Contratos de `GET /money-profile`, `GET /income`, `PUT /sources` y `POST /commitments` contra `FakeHttpAdapter`, con lo mal formado descartado.
- Reglas: la frase principal y el resumen de los cinco tipos.
- Escritor: un envío a la vez, en duda confirmada o no, bienvenida a medias, PILA por nombre, día y monto, y refresco del Inicio.
- Pantalla: estados, 422, 401, sin conexión, PILA 409 y montos ocultos.
- Visual: 320 px con letra al doble en tema claro y oscuro.
- Cuentas separadas.
- Demo: escenarios fijos y recorridos.

### Capturas (`docs/etapa-04/`)

| # | Qué muestra |
|---|---|
| [01](etapa-04/01-mi-plata-plan-listo.jpg) | Mi plata en «Plan listo»: frase del mes normal y del flaco |
| [02](etapa-04/02-hoja-como-te-entra.jpg) | Hoja en vista: fuente, «Págate un sueldo», colchón y «Salud y pensión» |
| [03](etapa-04/03-editar-fuentes.jpg) | Hoja en edición con los meses de proyectos precargados |
| [04](etapa-04/04-guardar-demo-fija.jpg) | Guardar en un escenario fijo: «Modo demostración…» |
| [05](etapa-04/05-hoja-tema-oscuro.jpg) | Hoja en tema oscuro |
| [06](etapa-04/06-recarga-fallida.jpg) | Recarga fallida: se ve lo último que llegó con el aviso |
| [07](etapa-04/07-mi-plata-vacio.jpg) | Sin fuentes: «Cuéntanos…» y «Configurar» |
| [08](etapa-04/08-configurar-sin-fuentes.jpg) | Configurar sin ninguna marcada: aviso nuevo bajo «Guardar» |
| [09](etapa-04/09-sueldo-fijo-editando.jpg) | Sueldo fijo de $ 1.800.000, días 15 y 30 |
| [10](etapa-04/10-guardado-recorrido.jpg) | Después de guardar en el recorrido: la tarjeta ya dice cuánto te entra |
| [11](etapa-04/11-inicio-actualizado.jpg) | El Inicio pasó de «Mi plata · noviembre» a «Libre para gastar» |

### Archivos

Nuevos:

- `lib/features/money/data/money_models.dart`, `money_repository.dart`, `demo_money_repository.dart`
- `lib/features/money/domain/income_rules.dart`
- `lib/features/money/application/money_providers.dart`, `money_writer.dart`
- `lib/features/money/presentation/my_money_screen.dart`, `widgets/income_overview_card.dart`, `widgets/income_sheet.dart`
- `lib/features/shell/presentation/pushed_frame.dart`
- `test/features/money/` (5 archivos) y `test/support/fake_money_repository.dart`
- `docs/ETAPA_04_MI_PLATA.md` y `docs/etapa-04/`

Modificados:

- `lib/app/router.dart` y `lib/app/pending_modules.dart` (Mi plata deja de estar «En desarrollo»).
- `lib/core/network/api_exception.dart` (`ApiCodes.welcomePending`).
- `lib/features/movements/presentation/record/record_screen.dart` y `lib/features/shell/presentation/pending_module_screen.dart` (usan `PushedFrame`).
- `lib/features/onboarding/domain/income_sources.dart` (`IncomeSourceForm.fromServer`) y `presentation/income/income_source_tile.dart` (errores por casilla; la bienvenida no lo usa).
- `lib/features/onboarding/data/demo_onboarding_repository.dart`, `presentation/demo_panel.dart` y `lib/features/home/data/demo_home_repository.dart` (demo).
- `tool/l10n_mobile/{en,pt}.json` y `assets/l10n/{en,pt}.json`. Los de `assets` salen del generador, no se editaron a mano.
- `test/app/router_test.dart` y `test/features/shell/pending_module_screen_test.dart`.

React y el backend no se tocaron.

### Git

- Rama: `feat/etapa-4-mi-plata` en `fintrackcol-org/rinde-mobile`.
- Commit: COMMIT_4A.
- PR: PR_4A (hacia `main`, sin fusionar).
- Respaldo: RESPALDO_4A.

### Lo que falta o no se comprobó en 4A

- «Tu sueldo» y la barra de avance del colchón: van con 4C, el primero en solo lectura.
- El aviso de bienvenida pendiente sale al tocar «Guardar», no antes, y todavía no tiene la acción «Terminar». Se completa en 4D.
- El bloqueo solo ve el borrador de **este** teléfono: una bienvenida a medias en otro dispositivo no se detecta (pregunta 2 del plan).
- La demo de los recorridos no imita la base «history» del servidor (2 meses completos con ingresos), ni el colchón ni la PILA.
- No probado en iOS, con lector de pantalla real, en un teléfono físico ni contra QA con sesión.

---

## Backend y QA

- **Idempotencia de la bienvenida:** está en `main` del backend (`7665c1e`, PR fintrackcol-org/fintrack#239) y en producción.
  - Señal: la API responde `Access-Control-Expose-Headers` con `Idempotent-Replayed`.
  - **No** está en `develop` ni en QA.
- **QA** (`https://44.193.22.247.sslip.io`, revisada el 23 de noviembre de 2026):
  - `/health` responde 200 y el certificado vence el 14 de febrero de 2027.
  - CORS acepta la PWA de `develop`.
  - `Expose-Headers` solo trae `Content-Disposition`: sin idempotencia.
  - `GET /api/v1/money-profile` sin sesión da 401.
  - **No hay cuenta de prueba:** hace falta autorización para crearla.
- **Versión del perfil** (para Corregir saldo y «Tu sueldo»): la propuesta va con el bloque 4B y **espera aprobación**. No se tocó el backend.
