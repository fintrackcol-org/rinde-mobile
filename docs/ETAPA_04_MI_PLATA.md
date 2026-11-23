# Etapa 4 — Mi plata y planificación financiera

Rama de trabajo: `feat/etapa-4-mi-plata` (sale de `main` en `798a462`). Cada bloque se sube a esa
rama y a una PR hacia `main` **sin fusionar**: la fusión la decide David.

> Todas las capturas son **modo demostración** con datos sintéticos (usuario «Ana»). Nada se probó
> contra QA con sesión: falta una cuenta de prueba autorizada (ver «Backend y QA»).

## Resumen

| Bloque | Estado |
|---|---|
| 4A — Mi plata y perfil financiero («Cómo te entra la plata») | Hecho, probado y subido (ver «Git» del bloque) |
| 4B — Saldo, corregir saldo, plan y «¿De dónde sale?» | Hecho, probado y subido. Corregir saldo en solo lectura en cuentas reales hasta que el backend tenga versión |
| 4C — Pagos recurrentes | Hecho, probado en el emulador y subido. «Tu sueldo» en solo lectura en cuentas reales hasta que el backend tenga versión |
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
- Commit: `75ec515` «feat: Mi plata con «Cómo te entra la plata» (etapa 4, bloque 4A)».
- PR: [fintrackcol-org/rinde-mobile#1](https://github.com/fintrackcol-org/rinde-mobile/pull/1), hacia `main`, **sin fusionar**.
- Respaldo: verificado en GitHub. `git ls-remote` devuelve el mismo `75ec515` que la rama local.

### Lo que falta o no se comprobó en 4A

- «Tu sueldo» y la barra de avance del colchón: van con 4C, el primero en solo lectura.
- El aviso de bienvenida pendiente sale al tocar «Guardar», no antes, y todavía no tiene la acción «Terminar». Se completa en 4D.
- El bloqueo solo ve el borrador de **este** teléfono: una bienvenida a medias en otro dispositivo no se detecta (pregunta 2 del plan).
- La demo de los recorridos no imita la base «history» del servidor (2 meses completos con ingresos), ni el colchón ni la PILA.
- No probado en iOS, con lector de pantalla real, en un teléfono físico ni contra QA con sesión.

---

## Bloque 4B — Saldo y disponibilidad

Fecha: 23 de noviembre de 2026.

### Qué tenía React (rama `main` de la web)

| Pieza | Dónde está en la web | En la app |
|---|---|---|
| «¿Hasta cuándo te alcanza?» y la tarjeta «Lo que te queda · {mes}»: fecha hasta la que alcanza, ritmo, ingresos y gastos | `components/money/MiPlataMobile.jsx`, `lib/runway.js` | `MoneyLeftSection`, con `buildMyMoneyView` |
| Nota de negativo y «¿No es tu plata real? Corrígela» | `MiPlataMobile.jsx` | Igual; la nota va bajo la tarjeta, como en el Inicio de la app |
| «Ojo con el…»: el primer pago fijo que no alcanza | `firstUncovered` en `MiPlataMobile.jsx` | `domain/commitment_rules.dart` |
| Los 3 primeros presupuestos | `MiPlataMobile.jsx` | `TopBudgets`. Sus filas llevan a Presupuestos, que sigue «En desarrollo» |
| «Más de tu plata»: 9 accesos | `MORE_OF_YOUR_MONEY` en `MiPlataMobile.jsx` | `MoneyShortcuts`. Los 6 destinos que no existen en la app van a «En desarrollo» con el título de su página web |
| Corregir saldo, `/app/mi-plata/corregir` | `pages/app/FixBalance.jsx` | `FixBalanceScreen` |
| «¿De dónde sale?» | Pastilla de la tarjeta del Inicio que lleva a Mi plata | Ya existía; ahora tiene prueba |
| Ajustes de saldo en Movimientos (`GET /adjustments`) | `components/money/AdjustmentRow.jsx`, `withAdjustments` en `MovementList.jsx` | `presentation/list/adjustment_row.dart` |

«Libre para gastar», lo apartado y lo que falta siguen saliendo del servidor (`/money/plan`). La app
no los calcula. La web en el celular tampoco los desglosa en Mi plata: viven en la tarjeta del Inicio.

### Qué se hizo

- **Mi plata completa en el orden de la web:**
  1. «¿Hasta cuándo te alcanza?», con la tarjeta, la nota de negativo, «Corrígela» y «Ojo con el…»;
  2. los presupuestos;
  3. «Cómo te entra la plata» (4A);
  4. «Más de tu plata».
  - Quedan dos huecos marcados para 4C: el aviso de pagos pendientes y «Pagos fijos del mes».
- **La cifra** sale de `plan.money` si el plan está listo y vigente; si no, de `profile.money`. Un dato
  que falta se muestra como «—» con la razón, nunca como $ 0. Halar hacia abajo recarga todo.
- **Corregir saldo**:
  - En la demo y cuando el servidor mande `version`, se puede escribir.
  - En cuentas reales de hoy queda **en solo lectura**: muestra la plata y un aviso de que se corrige
    en la web. No hay ningún camino que haga el PUT.
- **Ajustes en Movimientos:** fila gris «Ajuste de saldo · no es un gasto» (o «no es un ingreso») y
  su hoja. Se esconden con filtros o búsqueda, como en la web. Si `/adjustments` falla, la lista sigue.
- **Refrescos:** guardar, editar o borrar un movimiento y terminar la bienvenida ahora también
  vuelven a pedir el perfil de Mi plata, `/income` y los ajustes, no solo el Inicio.
- **Rutas:** `/app/transacciones/exportar` y los otros destinos «En desarrollo» van antes de
  `/app/transacciones/:id`, para que «exportar» no se abra como un movimiento.

### Escritura del saldo y salvaguardas

`PUT /money-profile` reemplaza todo el perfil y gana el último que escribe (ver la propuesta de
backend). Por eso:

1. Solo escribe si `canWriteBalance`: en la demo o con `version`.
2. Primero espera que no haya una bienvenida a medias (bloqueo de 4A).
3. Vuelve a leer el perfil. Si cambió el saldo, su fecha, el tipo de ingreso, los días de pago o la
   versión, no manda nada y dice «Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar.».
4. Si otra cuenta entró mientras leía, no manda nada.
5. Manda lo recién leído con `resetBalance: true`, y `expectedVersion` solo si llegó `version`.
6. Si el PUT queda en duda (se venció o el servidor dio 5xx), lo da por guardado solo si cambió
   `balanceAt` y el saldo es el enviado. Si no puede confirmarlo dice «No pudimos confirmar si se
   guardó. Revisa antes de intentarlo otra vez.» y recarga.
7. Un envío a la vez: dos toques dan un solo PUT.
8. Al terminar: recarga el Inicio, Mi plata y los ajustes, y vuelve a Mi plata.

### Diferencias con la web y por qué

- **Corregir saldo** usa el campo de montos de la app. Corrige tres defectos de la web:
  - no dejaba guardar 0;
  - no aceptaba decimales;
  - la primera tecla borraba el monto.
- «Guardar saldo» nunca se apaga: si falta el monto, lleva al campo y dice «Escribe cuánta plata tienes.».
- Corregir saldo **vuelve a leer el perfil al abrir**, como la web. Mientras lee muestra el esqueleto
  un instante.
- **Después de guardar desde Mi plata** se vuelve a Mi plata sin dejar dos seguidas en el historial.
  La web sí deja dos.
- **Estados que la web no tiene:** esqueletos al cargar, aviso de datos viejos, error con
  «Reintentar» en presupuestos y en Corregir saldo. La web se queda en «Cargando…».
- **Nombres de los meses** en el idioma de la app; la web los tiene fijos en español.
- **«Ojo con el 31 de noviembre»** pasa a ser el último día del mes, como lo cuenta el servidor.
- **Letra grande:** «Más de tu plata» pasa a una columna cuando la etiqueta más larga no cabe
  entera. El monto del ajuste baja de línea.
- **Montos ocultos:** también se tapan para el lector de pantalla en la fila y la hoja del ajuste.

### Textos nuevos que requieren aprobación

| Español | Inglés | Portugués |
|---|---|---|
| Por ahora corrige tu saldo en la web de Rinde, con tu misma cuenta. En la app llega pronto. | For now, fix your balance on the Rinde website, with the same account. It's coming to the app soon. | Por enquanto, corrija seu saldo no site do Rinde, com a mesma conta. Em breve chega ao app. |
| Tu plata cambió en otro dispositivo. Revisa y vuelve a guardar. | Your money changed on another device. Check it and save again. | Seu dinheiro mudou em outro dispositivo. Confira e salve de novo. |
| No pudimos confirmar si se guardó. Revisa antes de intentarlo otra vez. | We couldn't confirm whether it was saved. Check before trying again. | Não conseguimos confirmar se foi salvo. Confira antes de tentar de novo. |
| no es un gasto / no es un ingreso | not an expense / not income | não é um gasto / não é uma receita |

Los dos últimos ya están en español en `AdjustmentRow.jsx`, pero sin `t()`: la web no los traduce.

### Revisión adversarial

Mismo ciclo que en 4A:

- un agente implementó;
- tres revisores independientes revisaron en solo lectura (paridad con la web y el backend, escritura del saldo, interfaz y pruebas);
- otro agente corrigió lo confirmado. Cada prueba nueva se comprobó fallando sin su corrección.

| # | Hallazgo | Resultado |
|---|---|---|
| 1 | Corregir saldo, y Mi plata sin plan, mostraban la plata de antes del último movimiento o de la bienvenida. Con `version`, guardar esa cifra borraría los gastos recientes | Corregido: Corregir saldo relee al abrir, y movimientos y bienvenida refrescan Mi plata. Con pruebas |
| 2 | Movimientos pintaba ajustes sueltos mientras cargaba o si fallaba la lista | Corregido, con prueba |
| 3 | Si otra cuenta entraba durante la lectura previa, el PUT salía con el token de la nueva | Corregido, con prueba |
| 4 | Con «en duda» y la relectura fallida, no se veía «No pudimos confirmar…» | Corregido, con prueba |
| 5 | Al guardar desde Mi plata quedaban dos Mi plata seguidas | Corregido, **se aparta de la web**. Con prueba |
| 6 | «Presupuestos» se partía a media palabra con la letra un poco agrandada | Corregido (mide la etiqueta), con prueba |
| 7 | Faltaban pruebas en inglés con USD y en portugués con BRL | Agregadas (4) |
| 8 | El informe del implementador decía que la app manda el `ledger` exacto | No es del código: el servidor ya lo redondea. No se copió aquí |
| 9 | Los revisores no corrieron la suite completa | No aplica: la corrí al final (abajo) |

### Pruebas

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Sin hallazgos |
| `flutter test` | 1111 de 1111 en verde (eran 1017 al cerrar 4A) |
| `dart format --line-length 110` | Sin cambios pendientes |
| `gitleaks` sobre `lib`, `test`, `docs`, `tool` y `assets/l10n` | Sin fugas |
| `save_model_test.dart` (guardado de la bienvenida) | En verde: `onboarding_controller.dart` cambió |
| Compilación Android (`flutter build apk --debug`, con demo) | Compila |
| Emulador Android 16 (API 36) | Capturas abajo, antes y después de las correcciones |

Qué cubren las pruebas nuevas:

- `money_view_test.dart`: qué cifra se muestra según el plan y el perfil, «—» con su razón, `firstUncovered` y el ritmo.
- `fix_balance_test.dart`:
  - solo lectura sin `version`;
  - comprobación previa y conflicto 409;
  - en duda confirmada o no;
  - cambio de cuenta, bienvenida pendiente y dos toques;
  - relectura al abrir y regreso a Mi plata;
  - inglés con USD y portugués con BRL.
- `my_money_screen_test.dart`: secciones, «Más de tu plata», letra grande, idiomas y monedas.
- `list_adjustments_test.dart`: la fila, su hoja, filtros, error de `/adjustments` y lista cargando.
- `controller_test.dart`: la bienvenida refresca Mi plata.

### Capturas (`docs/etapa-04/`)

| # | Qué muestra |
|---|---|
| [12](etapa-04/12-mi-plata-recorrido.jpg) | Mi plata en el recorrido «movimientos»: «Lo que te queda», presupuestos vacíos, «Cómo te entra la plata» |
| [13](etapa-04/13-mas-de-tu-plata.jpg) | «Más de tu plata» con los 9 accesos |
| [14](etapa-04/14-corregir-saldo.jpg) | Corregir saldo con la plata precargada |
| [15](etapa-04/15-mi-plata-tras-corregir.jpg) | Mi plata después de guardar $ 520.000 |
| [16](etapa-04/16-inicio-tras-corregir.jpg) | El Inicio ya dice «Libre para gastar · estimado $ 520.000» |
| [17](etapa-04/17-ajuste-en-movimientos.jpg) | Movimientos: fila «Ajuste de saldo · no es un gasto» por −$ 130.000 |
| [18](etapa-04/18-hoja-del-ajuste.jpg) | Hoja del ajuste |
| [19](etapa-04/19-mi-plata-negativo-ojo-con.jpg) | Escenario «negativo»: −$ 35.000, nota de negativo y «Ojo con el 27 de noviembre» |
| [20](etapa-04/20-corregir-vacio.jpg) | Guardar sin monto: «Escribe cuánta plata tienes.» |
| [21](etapa-04/21-corregir-demo-fija.jpg) | Guardar en un escenario fijo: «Modo demostración…» |

Después de las correcciones de la revisión, con la demo recompilada:

| # | Qué muestra |
|---|---|
| [22](etapa-04/22-corregir-usar-movimientos.jpg) | Corregir saldo con $ 480.000 escritos y «Usar lo que dicen mis movimientos» |
| [23](etapa-04/23-vuelve-a-mi-plata.jpg) | Al guardar vuelve a Mi plata, ya con $ 480.000 y «Alcanza hasta el 28 nov» |
| [24](etapa-04/24-atras-al-inicio.jpg) | Un solo «Atrás» lleva al Inicio, que ya dice $ 480.000 (antes quedaban dos Mi plata) |
| [25](etapa-04/25-dos-ajustes.jpg) | Movimientos con los dos ajustes, el más nuevo primero |
| [26](etapa-04/26-mi-plata-oscuro.jpg) | Mi plata en tema oscuro |
| [27](etapa-04/27-mas-de-tu-plata-oscuro.jpg) | «Más de tu plata» en oscuro con la letra a 1,3×: dos columnas, «Presupuestos» entera |

### Archivos

Nuevos:

- `lib/features/money/domain/money_view.dart` y `commitment_rules.dart`
- `lib/features/money/presentation/fix_balance_screen.dart` y `widgets/{money_left_card,top_budgets,money_shortcuts}.dart`
- `lib/features/movements/presentation/list/adjustment_row.dart`
- `assets/icons/{target,calendar-days,hand-coins,credit-card,sparkles,download,landmark,scale}.svg` (lucide)
- `test/features/money/{money_view,fix_balance}_test.dart` y `test/features/movements/list_adjustments_test.dart`
- `docs/PROPUESTA_BACKEND_VERSION_PERFIL.md`

Modificados:

- Rutas: `lib/app/{routes,router,pending_modules}.dart`.
- `lib/core/network/api_exception.dart` (`profileChanged`, `unconfirmed`).
- Mi plata: `lib/features/money/` (modelos, repositorio real y demo, proveedores, escritor, pantalla).
- Inicio: `home_models.dart` (`ledger`), `runway.dart` (`pace`), `hero_card.dart` (piezas públicas para reusarlas; el Inicio no cambia).
- Movimientos: `movement_saver.dart` (refresca Mi plata) y `movements_screen.dart` (ajustes).
- Bienvenida: `onboarding_controller.dart` (refresca Mi plata), `demo_onboarding_repository.dart` y `demo_panel.dart`.
- `lib/design/widgets/rinde_icon.dart`.
- `tool/l10n_mobile/{en,pt}.json` y `assets/l10n/{en,pt}.json`. Los de `assets` salen del generador.
- Pruebas: `test/support/fake_money_repository.dart` y las de router, Inicio, Mi plata, demo y bienvenida.

React y el backend no se tocaron.

### Git

- Rama: `feat/etapa-4-mi-plata` en `fintrackcol-org/rinde-mobile`.
- Commit: `892f3ba` «feat: saldo y disponibilidad en Mi plata (etapa 4, bloque 4B)».
- PR: [fintrackcol-org/rinde-mobile#1](https://github.com/fintrackcol-org/rinde-mobile/pull/1), la misma de 4A, **sin fusionar**.
- Respaldo: verificado en GitHub. `git ls-remote` devuelve el mismo `892f3ba` que la rama local.

### Lo que falta o no se comprobó en 4B

- El aviso de pagos pendientes («Ya lo pagué») y «Pagos fijos del mes» van con 4C.
- En cuentas reales, Corregir saldo sigue en solo lectura hasta que el backend mande `version` (propuesta pendiente).
- El modo solo lectura solo está probado en pruebas: en la demo nunca aparece.
- En el campo de Corregir saldo, la cifra precargada no se oculta aunque los montos estén ocultos (pregunta 12 del plan).
- El acceso «Consejos · Tu semana y la IA» es el mismo de la web y lleva a «En desarrollo». No se implementó nada de IA.
- La relectura del perfil después de un movimiento solo se ve con una cuenta real: en la demo la plata del perfil no cambia con los movimientos. Está cubierta con pruebas.
- No probado en iOS, con lector de pantalla real, en un teléfono físico ni contra QA con sesión.

---

## Bloque 4C — Pagos recurrentes

Fecha: 23 de noviembre de 2026.

- El código se subió primero en `0448eb5`, cuando David pidió pausar.
- Al retomar se terminó la prueba en el emulador y se arregló el botón «Ya lo pagué» de las filas (ver «Lo que se encontró en el emulador»).

### Qué se hizo

- **Pagos del mes** (`/app/mi-plata/pagos`, como `MoneyPayments.jsx`). Deja de estar «En desarrollo»; sin historial, Atrás va a Planear.
  - Lee `GET /money-profile/calendar?month=`, solo los eventos de compromisos.
  - Totales «Falta por pagar», «Ya pagaste» y «Suscripciones».
  - Grupos «Por pagar», «Pagados» y «En otros meses», y «· atrasado» con texto.
- **Formulario del pago** (como `CommitmentDialog`):
  - Pago fijo o suscripción, nombre, monto, día, cada mes o una vez al año y el mes del cobro.
  - Valida con los cuatro mensajes de la web y lleva el foco al campo.
  - Los dos 409 van a su lugar y un 404 al editar cierra la hoja.
- **Escrituras** por `MoneyWriter`, con un envío a la vez, el bloqueo por bienvenida pendiente y el refresco del Inicio, Mi plata y el calendario:
  - **Crear:** `POST` con `kind`, `frequency` y `month`.
  - **Editar:** `PUT` completo, con comprobación previa.
  - **Eliminar:** con confirmación; un 404 cuenta como éxito.
  - **Nunca se manda `reminder`:** el aviso guardado se conserva.
- **«Ya lo pagué»:**
  - Anota un gasto con el nombre exacto y la fecha de hoy, con un `localId` por toque.
  - Solo sale para lo del mes en curso (`payableNow`). Mientras guarda, todos los botones esperan.
  - El botón no se suelta hasta que llegan el calendario y el plan nuevos.
  - Sin conexión no deja anotar el mismo pago dos veces en el mes.
  - En la demo responde «Modo demostración…».
- **«Tu sueldo»** en Pagos:
  - En cuentas reales queda en solo lectura con el texto nuevo.
  - En la demo de recorrido se puede cambiar. Manda el saldo recién leído y sin `resetBalance`, así no reinicia nada.
- **Mi plata:** el aviso de pagos pendientes con «Ya lo pagué» y la X (avisos cerrados por cuenta y solo en este teléfono), y «Pagos fijos del mes».
- **Demo:**
  - En los escenarios fijos, «Falta por pagar» es igual a lo apartado del plan, y las fechas ya no se salen del mes.
  - En los recorridos, los pagos se guardan por cuenta y el Inicio cambia.

### Textos nuevos que requieren aprobación

| Español | Inglés | Portugués |
|---|---|---|
| ¿Eliminar {name}? | Delete {name}? | Excluir {name}? |
| Se borra el pago y su aviso. Los gastos que ya anotaste no cambian. | The payment and its reminder are deleted. Expenses you already recorded don't change. | O pagamento e o aviso dele são apagados. Os gastos que você já anotou não mudam. |
| Por ahora cámbialo en la web de Rinde, con tu misma cuenta. | For now, change it on the Rinde website, with the same account. | Por enquanto, mude no site do Rinde, com a mesma conta. |

También se tradujo «Modo demostración: esta acción no llega a ningún servidor.», que ya existía solo en español.

### Diferencias con la web y por qué

- Eliminar pide confirmación; la web borra sin preguntar.
- No hay bloque «Avisarme» (no hay notificaciones en la app): un pago creado en la app nace sin aviso.
- «Ya lo pagué» no se puede anotar dos veces, ni sin conexión ni con la red lenta; en la web sí.
- No se ofrece «Ya lo pagué» para un pago del mes siguiente; la web sí, y lo resta dos veces.
- Los montos ocultos se respetan en Pagos; la web no lo hace.
- «Eliminar» usa un rojo más oscuro en modo oscuro para que el texto blanco se lea (contraste de 5,3:1). Se corrigió igual en borrar movimiento.

### Revisión adversarial

- Un agente implementó y cuatro revisores independientes revisaron en solo lectura:
  - paridad con la web y el backend;
  - escrituras;
  - consistencia de las cifras y la demo;
  - interfaz y pruebas.
- Otro agente corrigió lo confirmado.

| # | Hallazgo | Resultado |
|---|---|---|
| 1 | Con la red lenta, «Ya lo pagué» se podía tocar otra vez mientras recargaba y anotaba dos gastos | Corregido, con pruebas |
| 2 | Sin conexión más de un día, el mismo pago entraba dos veces a la cola | Corregido: se compara el mes, como el servidor |
| 3 | Falso «Tu plata cambió en otro dispositivo» al reabrir un pago justo después de guardarlo | Corregido, con prueba |
| 4 | Demo: el calendario de noviembre traía pagos de diciembre | Corregido: las fechas no se salen del mes. Se ajustó una prueba del Inicio |
| 5 | «Ya lo pagué» no respetaba la bienvenida pendiente | Corregido, con prueba |
| 6 | Un cambio de cuenta a mitad de «Ya lo pagué» anotaba el gasto en la otra cuenta | Corregido, con prueba |
| 7 | Editar en duda: el reintento culpaba a «otro dispositivo» | Corregido, con prueba |
| 8 | El error de un aviso se quedaba pegado al siguiente | Corregido, con prueba |
| 9 | La hoja del pago se cerraba arrastrándola mientras guardaba | Corregido, con prueba. Mismo arreglo en la hoja de 4A |
| 10 | «Tu sueldo» aceptaba cambios mientras guardaba | Corregido |
| 11 | Contraste de 2,5:1 en «Eliminar pago» en modo oscuro | Corregido, con prueba |
| 12 | La demo respondía en español en inglés y portugués | Corregido |
| 13 | Demo: cerrar un aviso dura solo un día | Descartado: es solo de la demo, anotado en el código |
| 14 | Pruebas débiles o faltantes | Reforzadas |

### Pruebas

| Comprobación | Resultado |
|---|---|
| `flutter analyze` | Sin hallazgos |
| `flutter test` | 1205 de 1205 en verde (eran 1111 al cerrar 4B) |
| `dart format --line-length 110` | Sin cambios pendientes |
| `gitleaks` sobre `lib`, `test`, `docs`, `tool` y `assets/l10n` | Sin fugas |
| `save_model_test.dart` | En verde (cambió `commitments.dart` de la bienvenida) |
| Compilación Android con demo | Compila e instala |
| Emulador Android 16 (API 36) | Recorrido completo, capturas 28 a 48 |

### Lo que se encontró en el emulador

| Qué | Resultado |
|---|---|
| En las filas de Pagos, «Ya lo pagué» se partía en dos líneas y se veía tosco | **Corregido:** la fila usa la letra y el relleno del botón pequeño, como el `size="sm"` de la web, y conserva los 44 px de alto para tocarlo. Con prueba. Las capturas 31 a 33 son de antes del arreglo; la 42 es de después |
| El primer guardado tardó unos 5 s | Pasó justo después de despertar el emulador. Los siguientes tardaron menos de 2 s; no es del código |
| Te quedan $ 480.000, el arriendo de $ 850.000 vence el 28 y no sale «Ojo con el…» | Es la regla de la web: solo avisa de pagos que caen **después** del día en que se acaba la plata según el ritmo, y ese día es el 28. El Inicio sí lo dice: «Te faltan $ 370.000» |
| «Suscripciones: $ 5.000 al mes» sin «(1)» | Igual que la web: el número solo sale con más de una |
| El texto de vacío sigue visible con una suscripción de marzo | Igual que la web: sale cuando no hay pagos en este mes |

### Capturas (`docs/etapa-04/`)

En el recorrido «movimientos»:

| # | Qué muestra |
|---|---|
| [28](etapa-04/28-pagos-fijos-vacio.jpg) | Mi plata: «Pagos fijos del mes» vacío con «Agregar» |
| [29](etapa-04/29-pagos-del-mes-vacio.jpg) | Pagos del mes vacío: «Tu sueldo» con «Cambiar», totales y «Agregar pago» |
| [30](etapa-04/30-nuevo-pago.jpg) | Hoja «Nuevo pago». Guardar sin nombre muestra «Escribe el nombre del pago.» y lleva el foco al campo |
| [31](etapa-04/31-pago-guardado.jpg) | Arriendo de $ 800.000, día 5: «· atrasado» y «Falta por pagar $ 800.000» |
| [32](etapa-04/32-ya-lo-pague-demo.jpg) | «Ya lo pagué» en la demo: «Modo demostración…», no resta nada |
| [33](etapa-04/33-pago-editado.jpg) | Editado a $ 850.000, día 28: ya no está atrasado |
| [34](etapa-04/34-mi-plata-aviso-y-pagos-fijos.jpg) | Mi plata: aviso «Arriendo vence el 28 de noviembre» y «Pagos fijos del mes» |
| [35](etapa-04/35-inicio-con-el-pago.jpg) | Inicio: «Te faltan $ 370.000 para tus pagos. Tienes $ 480.000 y vencen $ 850.000.» y «Lo próximo» |
| [36](etapa-04/36-confirmar-eliminar.jpg) | «¿Eliminar Arriendo?» con los textos nuevos |
| [37](etapa-04/37-pago-eliminado.jpg) | Pago eliminado: vuelve el vacío |
| [38](etapa-04/38-suscripcion-anual-sin-mes.jpg) | Suscripción anual sin mes: «Elige en qué mes se cobra Dominio.» |
| [39](etapa-04/39-suscripcion-en-otros-meses.jpg) | «Dominio · cada año, el 10 de marzo · suscripción» en «En otros meses» y «Suscripciones: $ 5.000 al mes» |
| [40](etapa-04/40-tu-sueldo-editar.jpg) | «Tu sueldo» en edición |
| [41](etapa-04/41-tu-sueldo-guardado.jpg) | «Con fecha fija, los días 5, 15 y 30». El saldo siguió en $ 480.000, sin ajuste nuevo en Movimientos |

En el escenario fijo «Plan listo»:

| # | Qué muestra |
|---|---|
| [42](etapa-04/42-pagos-plan-listo.jpg) | «Falta por pagar $ 338.000», igual a lo apartado del Inicio, con «Ya lo pagué» ya arreglado |
| [43](etapa-04/43-aviso-plan-listo.jpg) | Mi plata: «1 de 3 · Plan celular vence el 26 de noviembre» |
| [44](etapa-04/44-aviso-cerrado-siguiente.jpg) | Después de la X: «1 de 2 · PILA vence el 29 de noviembre» |
| [45](etapa-04/45-pagos-oscuro-letra-grande.jpg) | Pagos en tema oscuro con la letra a 1,3× |
| [46](etapa-04/46-eliminar-oscuro.jpg) | Confirmación en oscuro: el rojo se lee |
| [47](etapa-04/47-eliminar-demo-fija.jpg) | Eliminar en un escenario fijo: «Modo demostración…» dentro de la confirmación |
| [48](etapa-04/48-calendario-con-error.jpg) | Recarga fallida: lo último que llegó y «Lo que ves puede estar desactualizado…» |

### Git

- Rama: `feat/etapa-4-mi-plata` en `fintrackcol-org/rinde-mobile`.
- Commits: `0448eb5` (el bloque, subido al pausar) y `8d60a42` (botón de las filas, capturas e informe).
- PR: [fintrackcol-org/rinde-mobile#1](https://github.com/fintrackcol-org/rinde-mobile/pull/1), la misma de 4A y 4B, **sin fusionar**.
- Respaldo: verificado en GitHub. `git ls-remote` devuelve el mismo `8d60a42` que la rama local.

### Lo que falta o no se comprobó en 4C

- En cuentas reales, «Tu sueldo» sigue en solo lectura hasta que el backend mande la versión del perfil (propuesta pendiente).
- «Ya lo pagué» real (con servidor) solo está probado en pruebas: en la demo responde «Modo demostración…» a propósito.
- La pregunta 3 del plan sigue abierta: «Ya lo pagué» usa la fecha del teléfono, como la web; cerca de la medianoche o fuera de Colombia podría no coincidir con el «hoy» del servidor.
- Los pagos creados en la app nacen sin aviso, porque no hay bloque «Avisarme» (pregunta 6 del plan).
- No probado en iOS, con lector de pantalla real, en un teléfono físico ni contra QA.

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
- **Versión del perfil** (para Corregir saldo y «Tu sueldo»): la propuesta está en [`PROPUESTA_BACKEND_VERSION_PERFIL.md`](PROPUESTA_BACKEND_VERSION_PERFIL.md) y **espera aprobación**. No se tocó el backend.
