# Etapa 3 — Movimientos, idempotencia del backend y Rin opción B

Fecha: 22 y 23 de noviembre de 2026.
Estado: **terminado en código y pruebas, sin commit, sin push y sin despliegue.** Cada uno de esos
pasos espera la aprobación de David (ver la sección 11).

> Todo lo que se ve en las capturas es **modo demostración** con datos sintéticos (usuario «Ana»).
> No se probó nada contra el servidor de QA con sesión: falta una cuenta de prueba autorizada
> (sección 6).

## Resumen

| Tema | Estado |
|---|---|
| Rin opción B | Aplicada y probada; capturas 01 a 08 |
| Movimientos, bloque A: anotar, lista, buscar, filtros, detalle, editar, eliminar | Hecho |
| Movimientos, bloque B: texto rápido, voz, adjuntos | No hecho (sección 7). La sugerencia de categoría la da el servidor |
| Movimientos, bloque C: altas sin conexión y sin duplicar | Hecho para altas. Editar y eliminar piden conexión |
| Idempotencia de `POST /money-profile/welcome` | Hecha en el backend (rama aparte) y en la app |
| Pruebas Flutter | 938 de 938 (eran 818 al cerrar la etapa 2) |
| Pruebas backend | 706 de 706 (eran 695) |
| Revisión adversarial del código | 7 fallos confirmados; los 7 corregidos y cada uno con su prueba |
| Verificación del informe contra el código | 4 fallos más; los 4 corregidos, con prueba |
| QA real | Sin probar: falta la cuenta de prueba |

---

## 1. Rin opción B

Decidido por David el 22 de noviembre de 2026. El detalle y la evaluación están en
[`RIN_EN_MOBILE.md`](RIN_EN_MOBILE.md). El manual visual de Rinde Web y el código React no se tocaron.

| Pantalla | Rin | Captura |
|---|---|---|
| Saludo | Sí: grande, saluda una vez | [01](etapa-03/01-saludo-con-rin.jpg) |
| País, idioma y moneda | No | [02](etapa-03/02-pais-sin-rin.jpg) |
| «Cómo funciona» (5 escenas) | No | [03](etapa-03/03-como-funciona-sin-rin.jpg) |
| Ingresos | Sí, dentro de la nota que explica por qué se pregunta | [04](etapa-03/04-ingresos-con-rin.jpg) |
| Saldo | No (se conserva la nota, sin el dibujo) | [05](etapa-03/05-saldo-sin-rin.jpg) |
| Pagos | No (se conserva la nota, sin el dibujo) | [06](etapa-03/06-pagos-sin-rin.jpg) |
| Final real («¡Listo!») | Sí: celebra una vez (`CelebrationView`) | Sin captura: en la demo el cierre es «Demostración terminada» ([07](etapa-03/07-demo-terminada.jpg)) |
| Inicio | Solo en el estado vacío | [08](etapa-03/08-inicio-vacio-con-rin.jpg) |

Archivos:

- Se quitó Rin y sus gestos de `steps/country_step.dart`, `steps/tour_step.dart`,
  `steps/balance_step.dart` y `steps/payments_step.dart`.
- En `widgets/onboarding_shell.dart`, `RinNote.rin` ahora es opcional.

Pruebas que lo fijan: `tour_test`, `hello_country_test` y `balance_payments_test`.

## 2. Estado real de los cambios sin publicar

**Rinde Mobile** (`C:\Users\57317\Desktop\rinde`):

- Remoto: `https://github.com/fintrackcol-org/rinde-mobile.git`. Rama: `main`.
- Último commit: `38f99e4` (bienvenida completa), aprobado el 21 de noviembre.
- Encima, **sin commit**, están toda la etapa 2 (Inicio real) y toda la etapa 3.
- `git status` muestra 89 entradas: 62 archivos modificados y 27 nuevos (algunos son carpetas). No se
  descartó nada.
- Las etapas 2 y 3 comparten archivos (router, rutas, demo del Inicio, bienvenida). No se pueden subir
  por separado sin rehacer parte del trabajo. Hay dos caminos: un solo commit, o dos commits en orden
  (etapa 2 y después etapa 3) separando a mano los archivos compartidos. Lo decide David.

**Fintrack, web y backend** (`C:\Users\57317\Desktop\fintrack`):

- Remoto: `https://github.com/stife690/fintrack.git`.
- El checkout principal sigue en `fix/landing-contraste-pie` (`72643f7`).
- Tiene 41 archivos sin seguimiento de otros trabajos, 11 de ellos en `frontend/` (por ejemplo,
  `rin-lab` y `RinCard`). No se tocaron y no hay archivos modificados.
- El trabajo de backend vive en un worktree aparte (sección 3).
- No se tocó `frontend/` en ninguna parte.

**Puntos de partida:** antes de empezar se corrieron las dos suites. Dieron 818 de 818 en Flutter y
695 de 695 en el backend.

## 3. Dónde vive el backend

| Qué | Valor |
|---|---|
| Repositorio | El mismo de la web: `C:\Users\57317\Desktop\fintrack` |
| Worktree | `C:\Users\57317\Desktop\fintrack\.claude\worktrees\mobile-backend` |
| Rama | `feat/mobile-idempotencia`, creada desde `origin/main` (`dd0068a`) |
| Commits en la rama | Ninguno: los cambios están sin commit dentro del worktree |
| Base de datos de pruebas | Contenedor Docker `rinde-e3-db` (PostgreSQL 16, puerto 5440), creado desde `db/init` del worktree. Es desechable y ahora está detenido. No se usó la base del usuario ni ninguna remota |
| `backend/.env` del worktree | Solo para pruebas locales e ignorado por Git. No tiene credenciales reales |

**Ojo con la rama base:**

- `origin/main` tiene 17 commits que `develop` no tiene, casi todos de `frontend/` y la landing.
- En `backend/`, `db/` y `.github/` las dos ramas son idénticas.
- Por eso, antes de abrir una PR contra `develop` hay que pasar el cambio a una rama creada desde
  `origin/develop`. Entra sin conflictos. Si no, la PR arrastraría a QA esos 17 commits de la web.

Archivos tocados en el backend:

- `money-profile.repository.js`, `money-profile.service.js`, `money-profile.controller.js` y
  `money-profile.validator.js`.
- `app.js`, que expone `Idempotent-Replayed` por CORS.
- `config/migrations.js` y `db/init/01_schema.sql`.
- `i18n/locales/{en,pt}/06.json`.
- `docs/api/openapi.yaml`.
- `.github/workflows/ci.yml`: el conteo de tablas pasa de 44 a 45.

Nuevos: `backend/src/money-profile-idempotency.test.js`, `db/patches/038_idempotencia.sql` y
`docs/idempotencia-bienvenida.md`.

## 4. Idempotencia de la bienvenida

El contrato completo está en `docs/idempotencia-bienvenida.md` del worktree. En corto:

| Caso | Respuesta |
|---|---|
| Con cabecera `Idempotency-Key` (opcional; 8 a 128 caracteres `[A-Za-z0-9._:-]`) | Se aplica la bienvenida: `200` con el perfil |
| Misma llave y mismo cuerpo validado | No se aplica de nuevo: `200` con el perfil **actual** y `Idempotent-Replayed: true` |
| Misma llave y otro cuerpo | `409 IDEMPOTENCY_KEY_REUSED`; no se aplica nada |
| Llave mal formada | `400 VALIDATION_ERROR`; no se aplica nada |
| Sin cabecera (la web) | Igual que antes |
| Token vencido | `401` antes de mirar la llave; no se guarda nada |

Cómo lo garantiza:

- **Nombre.** `Idempotency-Key` es el del borrador del IETF. El backend no tenía otra convención.
- **Atómico.** La llave se reclama **dentro de la misma transacción** que guarda el perfil y los
  pagos. Si algo falla a mitad de camino se deshace todo, la llave incluida.
- **Por usuario y persistente.** La tabla `idempotency_keys` tiene llave primaria
  `(usuario_id, scope, clave)`. Sobrevive reinicios y varias instancias.
- **Qué protege `ON CONFLICT DO NOTHING`.** Solo que la misma llave se inserte dos veces. No ordena
  intentos distintos (ver «Límite conocido»).
- **Peticiones en curso.** Si llega una segunda petición con la misma llave mientras la primera
  sigue, su `INSERT` espera a que la primera confirme o se deshaga. Después responde como repetición.
  Mientras espera ocupa una conexión del pool, y no hay un tiempo máximo de espera configurado.
- **Respuesta de una repetición.** Es el perfil actual, no una copia de la primera respuesta. Si hubo
  cambios después, los incluye.
- **Huella.** Es el sha256 del cuerpo **después** de validarlo. No se guardan montos ni respuestas.
- **Retención.** Una llave con más de 30 días deja de contar. Se borra cuando ese mismo usuario
  reclama otra; no hay limpieza periódica. Como la bienvenida suele enviarse una sola vez, en la
  práctica la fila (pequeña y sin montos) queda hasta que se borra la cuenta.
- **Logs.** El código nuevo no escribe cuerpos, montos, tokens ni llaves.

**Pruebas del backend.** Son 11 nuevas en `money-profile-idempotency.test.js`, todas contra la base
desechable:

| Pedido en el prompt | Prueba |
|---|---|
| Repetición exacta | «repetir la misma llave no aplica nada otra vez y avisa que es repetición» |
| Repetición concurrente | «5 peticiones iguales a la vez: se aplica una sola y todas responden 200» |
| Respuesta perdida | «respuesta perdida: el reintento tardío no pisa lo que el usuario cambió después» |
| Falla a mitad del guardado | «si falla a mitad de camino no queda la llave y el reintento funciona» |
| Misma llave, otro cuerpo | «la misma llave con otros datos responde 409 y no aplica nada» |
| Otro usuario | «la misma llave en otro usuario es independiente» |
| Reinicio | «la repetición funciona tras reiniciar el servidor (otro proceso y otro pool)» |
| Token vencido | «con el token vencido responde 401 y no guarda la llave» |
| Compatibilidad con la web | «sin la cabecera se comporta como siempre (la web no la manda)» |
| Retención | «las llaves de más de 30 días se borran» |
| Llave inválida | «una llave mal formada responde 400 y no aplica nada» |

La compatibilidad con la web se probó **solo en el backend**, con una petición sin la cabecera. No se
corrió la PWA contra esta rama ni las pruebas de `frontend/`, que no cambió.

**En la app:**

- La llave (`w-` seguido de 128 bits al azar) y la huella de lo enviado se guardan en el borrador
  (`welcomeKey`) **antes** de enviar.
- Un reintento idéntico manda la misma llave. Si cambia el saldo o los pagos, se genera otra.
- Si el almacenamiento cifrado del teléfono falla al guardar el borrador, la llave queda solo en
  memoria. Si además la app se cierra, el reintento saldría con otra llave.
- El caso «cerrar la app y reintentar» no tiene prueba propia. Las pruebas reintentan sin cerrar.
- Un `409 IDEMPOTENCY_KEY_REUSED` no se trata como «seguro no se guardó». Se suelta la llave y se
  consulta el estado, como cuando se pierde la respuesta.
- Pruebas en `controller_test.dart`:
  - misma llave en el reintento del mismo envío;
  - otra llave tras cambiar el saldo;
  - el caso 409.

**Límite conocido (decisión pendiente):**

- Un envío viejo con **otra** llave que llega tarde todavía puede pisar un saldo más nuevo. La llave
  evita aplicar dos veces el mismo intento, pero no ordena intentos distintos.
- Arreglarlo exige cambiar el contrato, con una versión del perfil o `If-Match`. Eso toca también a
  la web. No se hizo.

## 5. Qué se comprobó y dónde

| Dónde | Qué |
|---|---|
| Backend local con base desechable | Las 706 pruebas del backend, incluidas las 11 de idempotencia. Lint con 0 errores |
| Flutter, pruebas automáticas | 938 pruebas con repositorios falsos y con la demo |
| Emulador Android 16 (API 36), modo demo | Ver la tabla de la sección 10 |
| QA real | Solo lectura sin sesión (sección 6). Nada con cuenta |

**La app no se conectó al backend local.** No se hizo en esta etapa: haría falta compilar la app
apuntando al backend local desde el emulador y crear una cuenta en la base desechable.

El contrato del lado del móvil se probó contra repositorios falsos que imitan las respuestas del
backend, y el backend se probó por su lado. Quedan **sin validar de punta a punta**:

- el cuerpo real de `POST` y `PUT /transactions` que arma Dart;
- que el servidor real reconozca el `localId`;
- que la cabecera `Idempotency-Key` salga de la app y llegue al servidor;
- cómo lee la app el `409 IDEMPOTENCY_KEY_REUSED` y la cabecera `Idempotent-Replayed` reales.

## 6. API de QA

- **Endpoint confirmado:** `https://44.193.22.247.sslip.io`.
  - Lo despliega el CI (job `deploy-qa`) en AWS cada vez que hay un push a `develop`.
  - Se tomó del registro público de ese job; no se inventó.
- **Comprobado el 23 de noviembre sin sesión, solo lectura:**
  - TLS válido (Let's Encrypt).
  - `GET /health` responde `200`.
  - `GET /api/v1/money-profile` responde `401`, como debe; `/api/v1` a secas responde `404`.
- **Estabilidad de la URL.** Usa una IP elástica del stack de QA (`AWS::EC2::EIP` en
  `infra/aws/template.yaml`). No cambia aunque se reemplace la instancia; solo si se borra y se vuelve
  a crear el stack. Para tener un nombre fijo existe `infra/aws/aws.sh domain api-qa.<dominio>`.
- **La PWA de QA en Vercel no es la API** y no se usó como `baseUrl`. No se revisó si esa PWA apunta a
  esta misma API: su configuración está detrás del inicio de sesión de Vercel.
- **Cómo apuntar la app a QA** (no se probó): copiar `config/example.json` a `config/qa.json`, que
  está ignorado por Git. Poner `"APP_ENV": "qa"` y `"API_BASE_URL": "https://44.193.22.247.sslip.io"`.
  Después, correr `flutter run --dart-define-from-file=config/qa.json`.
- **CORS** no aplica a la app nativa.
- **Falta una cuenta de prueba en QA,** de correo y contraseña. Crearla es crear una cuenta, y eso
  necesita la autorización de David. El inicio con Google sigue apagado en la app (etapa 1).
- **No se usó** ninguna credencial de nadie ni producción.
- **El código nuevo y la migración 038 no están en QA**, porque `develop` no los tiene. Mientras
  tanto, QA ignora la cabecera `Idempotency-Key`: la bienvenida funciona, pero sin la garantía.

## 7. Movimientos: bloques A, B y C

### Bloque A — hecho

- **Anotar un gasto o un ingreso** (`/app/anotar` y `/app/anotar?tipo=ingreso`):
  - monto en la moneda principal, sin selector de moneda;
  - descripción;
  - categoría: «Que la elija la IA» por defecto, o una del catálogo;
  - fecha: Hoy, Ayer u Otra fecha, nunca futura;
  - «¿Podías evitarlo?» (Kakeibo), solo en gastos;
  - aviso ante un monto muy alto.
- **Lista** (`/app/movimientos`):
  - por semana, mes o año, con flechas para cambiar de periodo;
  - buscador y filtros (Todos, Gastos, Ingresos, Categoría);
  - agrupada por día y paginada de a 20;
  - los pendientes de sincronizar van arriba.
- **Detalle** (`/app/transacciones/:id`), **editar** (`/app/transacciones/:id/editar`) y **eliminar**
  con confirmación. Son las mismas rutas de la web.
- **Editar manda solo lo que cambió** respecto al movimiento con que se abrió el formulario
  (`MovementInput.changesFrom`, como `changedFields` en la web).
  - Si se mandara la categoría sin cambiarla, el servidor la volvería a decidir y se perdería
    «sugerida por la IA».
  - Si el movimiento sigue siendo un gasto, se conservan la tarjeta, las cuotas, la emoción y el
    Kakeibo. Si pasa a ingreso, se quitan, como hace el servidor.
  - El monto en otra moneda se conserva solo si no se cambia el monto. Si se cambia, queda en la
    moneda principal, igual que en la web, y el formulario lo avisa.
- **Sobre «Que la elija la IA».** Con el servidor real, si las palabras clave no alcanzan, el backend
  manda la descripción del movimiento a un proveedor externo de IA (Gemini o Anthropic, según su
  configuración). Nunca manda el monto. La web hace lo mismo. En la demo no sale nada del teléfono.
  Queda por decidir si en el móvil la IA debe ser la opción por defecto.

### Bloque B — no hecho

| Función | Estado | Por qué |
|---|---|---|
| Sugerencia de categoría | La da el servidor: «Que la elija la IA» manda el movimiento sin categoría | Es lo mismo que hace la web |
| Texto rápido («almuerzo 12000») | No | La web lo interpreta en el navegador (`voiceEntry.js`) y no hay endpoint. Hay que portar ese archivo a Dart, con sus pruebas |
| Voz | No | Ya existe `POST /api/v1/voice/transcribe`, que recibe el audio y lo transcribe con Groq, un proveedor externo. Al móvil le falta grabar audio: un plugin de micrófono y su permiso. Antes de portarlo hay que decidir si es aceptable mandar el audio a un servicio externo |
| Adjuntos (soportes) | No | **Subir:** la API recibe el archivo en bruto, con la cabecera `X-File-Name`, y el móvil necesita un plugin de cámara o de archivos con sus permisos. **Ver y borrar:** los endpoints existen y no necesitan plugins, pero no se hicieron. Hoy el detalle del móvil no muestra los soportes adjuntados desde la web |

### Bloque C — hecho para altas

- **Sin duplicados.**
  - Cada movimiento nuevo lleva un `localId` (`m-` seguido de 128 bits al azar). Se genera al abrir
    el formulario y se repite en cada reintento.
  - El servidor ya reconoce el `localId` (FT-0009). Si el primer envío sí llegó, devuelve el mismo
    movimiento y **no duplica**.
- **Cola sin conexión.**
  - Sin conexión, el movimiento queda en una cola cifrada por usuario (`rinde.pendientes.<id>`).
  - En la lista se ve como «Pendiente de sincronizar».
  - Se reenvía al abrir la app, al entrar al Inicio, al volver a la app con el Inicio abierto, al
    tocar «Reintentar» y al deslizar para recargar en Movimientos.
- **Tope de 50 pendientes.** Con 50 en la cola, un movimiento nuevo sin conexión no se guarda y se
  muestra el error de red. Está cubierto por una prueba; no se probó en el emulador.
- **Rechazos.** Si el servidor rechaza un pendiente (por ejemplo, porque la categoría se borró desde
  la web), se queda guardado con el mensaje hasta que la persona lo descarte. No se pierde aunque la
  app se cierre.
- **Editar y eliminar piden conexión** y no tienen cola. Aquí la app **se aparta de la web**: la web
  los encola y los envía por `POST /sync/batch`, que resuelve conflictos (`server_wins` o
  `client_wins`). El móvil no usa `/sync/batch` y no tiene estado de «conflicto»: solo «pendiente» y
  «rechazado». Falta decidir si se porta.

### Fuera de alcance, como pide el prompt

Presupuestos, tarjetas, deudas, vacas, coach, ML y gamificación quedan fuera.

- Presupuestos, Tarjetas y la pestaña Planear muestran «En desarrollo».
- Deudas, vacas, coach, ML y gamificación todavía no tienen ruta ni pantalla en la app.

## 8. Diferencias con la web (React) y por qué

| Diferencia | Motivo |
|---|---|
| Editar y eliminar sin conexión: la web los encola; la app pide conexión | Ver el bloque C. Falta decidir si se porta `/sync/batch` |
| Tarjeta y cuotas no se eligen ni al anotar ni al editar | Tarjetas está fuera de alcance. Al editar se conserva la que ya tenía |
| Anotar en otra moneda (modo viaje, con tasa): la app no lo tiene | Se dejó para después. La app anota en la moneda principal y conserva el monto en otra moneda que ya tenía el movimiento |
| Crear una categoría desde Anotar: la app no lo tiene | Se dejó para después. Solo se usan las del catálogo |
| Emoción («¿cómo te sentiste?») después de guardar, y emoción o Kakeibo desde el detalle | La app solo pide el Kakeibo al anotar. Se dejó para después |
| Pantalla final de Anotar con saldo y presupuesto restante | La app cierra el formulario con un aviso corto. Mostrar el presupuesto está fuera de alcance |
| La alerta de presupuesto tras guardar no se muestra | Presupuestos está fuera de alcance. El servidor la manda (`alert`) y por ahora se ignora |
| Sin acciones al deslizar una fila, sin totales en la lista y sin «Exportar» | Se dejó la lista simple: editar y eliminar están en el detalle. Exportar está fuera de esta etapa |
| Sin texto rápido, voz ni soportes | Ver el bloque B |
| La demo no recalcula «Libre para gastar» ni el saldo | El prompt prohíbe inventarlos. Lo anotado solo suma en ingresos y gastos del mes (captura 11) |

## 9. Integridad del dinero, aislamiento de cuentas y sincronización

**Garantías del backend para movimientos.** Se investigaron; no se cambiaron.

| Operación | Qué garantiza |
|---|---|
| Alta (`POST /transactions`) | No duplica: hay un índice único `(usuario_id, local_id)` y `ON CONFLICT DO NOTHING`. Si el mismo `localId` llega con otro cuerpo, devuelve el original sin avisar |
| Edición (`PUT /transactions/:id`) | Gana la última escritura. No hay versión ni `If-Match`, así que una edición desde la web y otra desde el móvil se pisan |
| Borrado (`DELETE /transactions/:id`) | Es lógico. Un segundo borrado responde `404`. La app trata ese `404` como borrado, para cuando se pierde la respuesta del primero |
| `POST /sync/batch` | Existe, con resolución de conflictos. El móvil no lo usa |

**En la app:**

- **Sin cifras inventadas.**
  - En la demo, la lista de Movimientos solo muestra lo anotado.
  - En el Inicio demo, «Este mes» suma lo anotado a las cifras sintéticas del escenario elegido.
    Esas cifras valen cero solo en el escenario «Usuario nuevo».
  - Lo apartado (`ahorro_inversion`) no cuenta como gasto, igual que en el servidor.
  - Los montos se suman en centavos.
- **Aislamiento por cuenta.** La cola de pendientes, la demo y los borradores van por usuario. Si la
  cuenta cambia mientras un envío va en camino, ese movimiento **no** entra en la cola de la otra
  persona.
- **Nada se pisa al leer mal.** Si el almacenamiento cifrado no responde, la cola no se sobrescribe.
  En la demo, la operación falla en vez de borrar lo anotado.
- **Edición.** Si mientras se edita el detalle se refresca (por ejemplo, porque otra pantalla de
  edición guardó), el cambio se sigue calculando contra el movimiento que se abrió. Así no se
  reenvían valores viejos.
- **Algo que ya no existe.** Si el servidor responde `404` al pedir el detalle, se muestra el error,
  también cuando el detalle ya estaba cargado. No queda una copia vieja con «Editar» y «Eliminar».

**Riesgo abierto:** la bienvenida conserva el riesgo del envío tardío (sección 4) y la edición de
movimientos funciona con «gana la última escritura». No hay ninguna garantía verificada para esos dos
casos. Según el criterio de calidad del prompt, no deberían llegar a usuarios reales hasta que David
decida el contrato con versión.

## 10. Pruebas, capturas, archivos y Git

### Pruebas

- **Flutter:** `flutter analyze` sin hallazgos; `flutter test` con **938 de 938**, 120 más que en la
  etapa 2.
- **Backend:** `npm test` con **706 de 706**. Lint con 0 errores (47 avisos que ya existían). La
  cobertura no se midió: la suite usa `node --test` sin cobertura, así que solo se compara el número de
  pruebas.
- **Revisión adversarial del código.** Tres revisores (datos, pantallas e idempotencia), más una
  verificación de cada hallazgo. Se confirmaron 7 fallos, todos corregidos y con prueba:
  1. Un pendiente rechazado vivía solo en memoria y se perdía al cerrar la app
     (`data_saver_test`).
  2. Un cambio de cuenta durante el envío metía el gasto en la cola de la otra cuenta
     (`data_saver_test`).
  3. En la demo, un almacenamiento ilegible borraba lo anotado en la siguiente escritura
     (`data_demo_test`).
  4. Tocar el tipo ya elegido borraba la categoría, y al editar el servidor la reclasificaba
     (`record_screen_test`).
  5. Editar podía reenviar valores viejos si el detalle se refrescaba durante la edición
     (`record_screen_test`).
  6. Un `404` en el detalle mostraba una copia con «Editar» y «Eliminar» (`detail_screen_test`).
  7. Un `409` por llave reusada dejaba la bienvenida atascada (`controller_test`).
- **Verificación de este informe contra el código.** Cuatro revisores compararon cada afirmación con
  el código. Encontraron 4 fallos más, ya corregidos con prueba:
  - los arreglos 5 y 6 estaban incompletos;
  - deslizar para recargar no reenviaba los pendientes;
  - un `404` al borrar, tras perder la respuesta, se mostraba como error.

  También corrigieron varias afirmaciones de este informe que eran inexactas.

### Emulador

Android 16 (`Medium_Phone_API_36`), con un APK de depuración compilado con `DEMO_MODE=true`. Las
capturas están en [`etapa-03/`](etapa-03/).

| Prueba | Resultado | Capturas |
|---|---|---|
| Bienvenida con Rin B | Rin solo donde corresponde | 01 a 08 |
| Anotar un gasto y un ingreso | Se guardan; «Este mes» suma; «Libre» no cambia | 09 a 12 |
| Lista, detalle, editar y eliminar | Bien | 13 a 18 |
| Sin conexión → pendiente → conexión de vuelta | Se envía una sola vez | 19, 20 |
| Buscar | Filtra | 21 |
| Reinstalar encima y volver a abrir | Se conserva lo anotado | 22 |
| 320 de ancho y letra al doble | Sin desbordes; los filtros se desplazan | 23 a 25 |
| Portugués, reales y tema oscuro | Textos traducidos y validación visible | 26, 27 |

- El emulador mostró un defecto: el ícono de búsqueda salía enorme, porque se estiraba a todo el alto
  del campo. Ya está corregido; la captura 13 es posterior al arreglo.
- Monedas vistas en el emulador: dólares en las capturas 09 a 25 (la demo arrancó con Estados Unidos)
  y reales en la 27.
- Idiomas vistos en el emulador: español y portugués.

**No se probó:**

- **En el emulador:**
  - inglés;
  - pesos colombianos y otras monedas (las cubren las pruebas automáticas de formato de la etapa 2);
  - el teclado en pantalla (tipo de teclado del monto, que no tape «Guardar», paso entre campos);
    el emulador usaba un teclado flotante;
  - listas de más de 20 movimientos (la paginación la cubre `list_screen_test`);
  - el tope de 50 pendientes, el pendiente rechazado, los errores 5xx y 401 y el 404 del detalle
    (están solo en pruebas automáticas);
  - el modo oscuro del sistema: la app usa su propio ajuste de tema, que se probó desde el panel de
    la demo.
- **Accesibilidad:** se probó la semántica en las pruebas de widgets. No se probaron TalkBack
  encendido, el tamaño de los objetivos táctiles ni el contraste. El selector segmentado en tema
  oscuro (componente de la etapa 2) marca la opción elegida con poco contraste.
- **Sesión y fechas:**
  - token vencido durante un reintento: el pendiente se conserva (`data_saver_test`), pero la
    renovación real del token no se probó;
  - cambio de cuenta: solo en pruebas automáticas;
  - cambios de mes y año en la lista: cubiertos por `list_dates_test`;
  - cambiar la fecha del teléfono o pasar la medianoche con la app abierta: no se probó.
- **Pagos:** la relación entre Movimientos y los pagos de la bienvenida.
- **Otros:** iOS (exige un Mac), un teléfono físico, la red real, QA con cuenta y el APK *release*.
  El *release* no se compiló: necesita `API_BASE_URL`, y en *release* la demo se apaga sola.

### Archivos de la etapa 3 en Mobile

Se tomó como etapa 3 todo lo modificado después del informe de la etapa 2 (22 de noviembre, 12:47).
Varios archivos los tocaron las dos etapas.

**Modificados respecto a `38f99e4`:**

- `.gitignore`: se agregó `graphify-out/`.
- `assets/l10n/en.json` y `assets/l10n/pt.json`: textos nuevos.
- `lib/app/router.dart` y `lib/app/routes.dart`.
- `lib/core/network/api_client.dart`: cabeceras opcionales en `post` y un método `delete` nuevo.
- `lib/core/region/region_data.g.dart`: regenerado desde `region.js` de la web; agrega el prefijo
  negativo de 5 monedas.
- Bienvenida, en `lib/features/onboarding/`:
  - `application/onboarding_controller.dart`;
  - `data/demo_onboarding_repository.dart` y `data/onboarding_repository.dart`;
  - `domain/onboarding_draft.dart`;
  - `presentation/steps/{balance,country,payments,tour}_step.dart`;
  - `presentation/widgets/onboarding_shell.dart`.
- Pruebas de la bienvenida en `test/features/onboarding/`: `balance_payments_test.dart`,
  `controller_test.dart`, `hello_country_test.dart` y `tour_test.dart`.

**Nuevos desde `38f99e4` y tocados en la etapa 3:**

- Documentos: `docs/ETAPA_03_MOVIMIENTOS.md`, `docs/RIN_EN_MOBILE.md` y `docs/etapa-03/` (27
  capturas).
- `lib/app/pending_modules.dart`.
- `lib/features/home/data/demo_home_repository.dart` y
  `lib/features/home/presentation/home_screen.dart`.
- `lib/features/movements/`, completa:
  - `domain/movement.dart`;
  - `data/movements_repository.dart`, `data/demo_movements_repository.dart` y
    `data/json_list_store.dart`;
  - `application/movements_controller.dart` y `application/movement_saver.dart`;
  - `presentation/record/{record_screen,movement_form}.dart`;
  - `presentation/list/{movements_screen,movement_row,movement_dates}.dart`;
  - `presentation/detail/movement_detail_screen.dart`.
- Pruebas de Movimientos, en `test/features/movements/`: `data_controller_test`, `data_demo_test`,
  `data_repository_test`, `data_saver_test`, `detail_screen_test`, `integration_test`,
  `list_dates_test`, `list_screen_test`, `record_form_test` y `record_screen_test`.
- Otras pruebas:
  - `test/app/router_test.dart` y `test/features/shell/pending_module_screen_test.dart`: Movimientos
    y Anotar dejan de estar «En desarrollo»;
  - `test/features/home/{demo_home_repository,home_screen,tour_controller}_test.dart` y
    `test/features/onboarding/{demo_panel,save_model}_test.dart`: firma nueva de la bienvenida y
    almacenamiento de Movimientos.
- `test/support/fake_movements_repository.dart`.
- `tool/l10n_mobile/en.json` y `tool/l10n_mobile/pt.json`.

### Secretos

`gitleaks` no encontró secretos en lo que se subiría. Dio dos avisos falsos:

- La caché de graphify en Mobile. Solo la ignoraba el `.gitignore` global de este equipo; ahora
  también la ignora el del proyecto.
- Una clave de prueba antigua en `frontend/src/lib/push.test.js`, que no es de esta etapa.

`.env`, `config/*.json` (salvo el ejemplo) y `build/` (donde queda el APK) están ignorados.

### Git

Ver la sección 2. No se hizo commit, push, merge ni despliegue en ningún repositorio.

## 11. Cambios de backend que necesitan aprobación

| Paso | Riesgo | Cómo se revierte |
|---|---|---|
| Commit de `feat/mobile-idempotencia` y PR | El código nuevo no cambia nada para quien no manda la cabecera. La rama sale de `main`: para una PR a `develop`, hay que crear antes una rama desde `origin/develop` y pasar ahí el mismo cambio (sección 3) | Cerrar la PR antes de fusionar |
| Fusionar en `develop` | Dispara `deploy-qa`, que despliega en QA y aplica la migración 038 al arrancar | Revertir el commit completo y desplegar. Cerrar la PR ya no alcanza |
| Migración 038 | Baja: crea una tabla nueva y no toca las existentes | Primero revertir el código (incluida la 038 en `migrations.js` y `01_schema.sql`, y el conteo del CI de vuelta a 44) y desplegar. **Solo después** `DROP TABLE idempotency_keys;` |
| Pasar a producción | Igual que en QA. Render despliega solo al fusionar en `main` | Igual que en QA |
| Contrato con versión del perfil (límite de la sección 4) | Toca a la web | **No hecho**; solo propuesto |

Cuidados:

- **No borrar la tabla mientras el código nuevo siga desplegado.** `runMigrations` vuelve a correr en
  cada arranque y la crearía de nuevo.
- **Un servidor con el código nuevo y sin la tabla** (por ejemplo, si `runMigrations` falló al
  arrancar, que el servidor tolera) responde `500` a toda bienvenida que traiga la cabecera. A la web
  no la afecta, porque no la manda.
- **Un servidor sin el código nuevo** simplemente ignora la cabecera.

Riesgos que ya existían y conviene conocer:

- El manejador general de errores del backend imprime el error completo de PostgreSQL en un `500`, y
  puede incluir la fila con montos.
- Sigue sin resolver la miniatura de apps recientes, que muestra montos (de la etapa 2).
- `docs/api/openapi.yaml` ya no era YAML válido en `main`: un ejemplo del chat tiene `¿En qué gasto
  más?` sin comillas, cerca de la línea 3200. Un generador de clientes fallaría con él. No se corrigió
  porque no es de esta etapa.

El plan de reversa completo está en `docs/idempotencia-bienvenida.md` del worktree.

## 12. Siguiente módulo recomendado (sin implementar)

**Mi plata:** el perfil de ingresos y «De dónde sale» el libre para gastar.

- Ya existe en la web y en el backend (`/money-profile`, fuentes y plan), así que cumple «solo lo que
  existe hoy».
- La bienvenida ya escribe esos datos, pero en el móvil todavía no se pueden ver ni corregir.
  «Corregir saldo», «Ingresos» y «Pagos del mes» siguen «En desarrollo», y son los enlaces más
  visibles del Inicio.
- Reusa lo hecho: la tabla de llaves de idempotencia, con otro `scope` y sin cambiar la tabla, y el
  patrón de guardado de esta etapa.

Antes de empezarlo conviene cerrar tres cosas:

1. La cuenta de prueba en QA, para probar Movimientos de verdad.
2. El contrato con versión del perfil (sección 4), porque Mi plata edita el saldo.
3. Si editar y eliminar sin conexión se portan con `/sync/batch` (sección 7).

Después, lo más pedido del bloque B es el texto rápido (portar `voiceEntry.js`), que no necesita
plugins.
