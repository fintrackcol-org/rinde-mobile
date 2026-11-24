# Etapa 5 — Tarjetas y deudas

Rama de trabajo: `feat/etapa-5-tarjetas-deudas` (sale de `main` en `a8f0541`, que ya contiene la
etapa 4 completa). Cada bloque se sube a esa rama y a una PR hacia `main` **sin fusionar**: la
fusión la decide David.

> Fuente de verdad: la rama `main` de la web (producción). Se comprobó que, en tarjetas y deudas,
> `develop` no tiene nada que `main` no tenga (el corte del Calendario ya está en `main` como
> `1a99cce`).

## 1. Resumen ejecutivo

| Bloque | Estado |
|---|---|
| 5A — Tarjetas, y tarjeta + cuotas en Movimientos | Terminado, probado y revisado; en PR sin fusionar (§17) |
| 5B — Deudas (pantalla «Cuentas») | Terminado, probado y revisado; en la misma PR sin fusionar (§17) |
| 5C — Integración con Inicio, Mi plata y Movimientos | Pendiente |

## 2. Estado heredado de la etapa 4

- La etapa 4 está **fusionada** en `main` (`a8f0541`, 23-nov-2026): la rama 5 la contiene completa
  (verificado con `git merge-base --is-ancestor`).
- La idempotencia de la bienvenida está en `main`/producción; **no** en `develop`/QA.
- La propuesta de versión del perfil (`PROPUESTA_BACKEND_VERSION_PERFIL.md`) **sigue sin aprobarse**:
  Corregir saldo y «Tu sueldo» continúan en solo lectura en cuentas reales. No se quitó ninguna
  protección.
- Los textos nuevos de la etapa 4 entraron a `main` sin revisión de David (decisión suya al fusionar).
- iOS sigue sin validarse.

## 3. Inventario de React (auditoría del 23-nov-2026)

Cinco estudios con archivo:línea más un plan verificado contra el código (20 correcciones de un
verificador independiente). Lo esencial:

### Tarjetas (existe y se migra)

- Rutas `/app/tarjetas` y `/app/tarjetas/:id`, con variante de celular (<768 px): «Debes en total»,
  acciones en círculos y filas compactas.
- 9 rutas en `/api/v1/cards`: lista, crear, detalle, editar, eliminar (lógico), pagar, eliminar un
  pago, «Actualizar con el banco» y los movimientos de la tarjeta.
- El servidor calcula todo lo financiero: lo usado, el disponible, el próximo pago, el estado del
  ciclo, el extracto y el vencimiento. El cliente solo calcula el porcentaje de la barra, la suma
  «Debes en total» y la vista previa del ajuste con el banco.
- **Regla de la plata:** la compra con tarjeta **no** resta de Mi plata; el pago de tarjeta **sí**
  resta pero no es un movimiento (va a `pagos_tarjeta`). «Actualizar con el banco» puede crear el
  gasto «Cargos del banco · {nombre}».
- Cuotas (1 a 48): solo se eligen en Anotar o al editar un movimiento, y son informativas (el monto
  completo cuenta en lo usado).
- Datos sensibles: solo los últimos 4 dígitos y el vencimiento MM/AA. Nunca el número completo ni
  el CVV.
- Avisos: push 3 días antes del pago y a 60/30 días del vencimiento del plástico, con un solo
  interruptor en Cuenta. El Inicio del celular muestra un único aviso de tarjeta.

### Deudas (existe y se migra)

- Una sola pantalla, `/app/cuentas` (`Debts.jsx`), pestañas «Me deben» y «Debo» con totales; todo lo
  demás en hojas: crear, editar, abonar, saldar y borrar. No hay pantalla de detalle.
- Datos: lado, persona (1-60), monto, fecha, nota (≤200) y plan de pago («De una vez» con fecha
  opcional, o 2-60 cuotas cada semana/quincena/mes). Estados guardados: pendiente o saldada; «vencida»
  y «con abonos» se calculan al mostrar.
- Abonos: «Registrar abono» crea por defecto el ingreso o gasto («Abono de/a X», categoría Otros);
  si cubre todo, salda sin segundo movimiento. «Ya me pagó todo» crea el movimiento por lo que
  faltaba y un segundo toque responde 409 sin duplicar. Borrar un abono borra su movimiento.
- **Trampa de contrato:** al crear o editar, `dueDate` es la **primera** cuota; al leer, es la
  **próxima** (el servidor la corre). Para editar se precarga `firstDueDate`. Comprobado contra QA.
- Lo que debo baja el saldo proyectado del Calendario y Próximos días; lo que me deben no suma.

### Lo que NO existe en React (no se implementa)

- Número completo de tarjeta, CVV, conexión real con bancos, intereses, pago mínimo, calendario de
  cuotas, saldo a favor, moneda por tarjeta, editar un pago de tarjeta, cola sin conexión de
  tarjetas, filtro de movimientos por tarjeta.
- Pantalla de detalle de una deuda, intereses o mora, contactos, historial de saldadas con deshacer,
  deudas en el bot de WhatsApp o en Exportar.
- `CardsSummary`, `QuickActions` y `DebtsSummary` del Inicio: código muerto o inexistente.
- El corte de la tarjeta no entra en ningún cálculo: solo se guarda y se muestra en el Calendario
  (módulo que sigue «En desarrollo» en la app).

## 4. Matriz React → Flutter

La matriz completa, verificada, está en el plan de la etapa (una fila por funcionalidad con pantalla,
endpoint, validaciones, importes, sin conexión, errores, relaciones y pieza Flutter). Resumen del
reparto:

- **5A:** `lib/features/cards/` (lista, detalle, crear, editar, eliminar, pagar, eliminar pago,
  ajustar con el banco, historial) + «Pagado con» y «Cuotas» en Anotar/Editar + `?tarjeta=` +
  la cola guarda la tarjeta.
- **5B:** `lib/features/debts/` (pestañas, crear/editar en dos pasos, abonar, saldar, borrar abono,
  borrar) sin el bloque «Avisarme» (la app no tiene push; el servidor avisa 1 día antes por defecto,
  igual que lo que la web manda).
- **5C:** el aviso de tarjeta del Inicio abre el detalle real; los accesos de «Más de tu plata»
  llevan a pantallas reales; refrescos tras cada escritura; montos ocultos, monedas, idiomas,
  aislamiento. Calendario, push, Por confirmar, Próximos días y Planear siguen «En desarrollo».

## 5. Bloque 5A — Tarjetas

**Estado:** terminado, probado y revisado. Subido a `feat/etapa-5-tarjetas-deudas` y en una PR hacia
`main` **sin fusionar** (ver §17).

### Qué tenía React (rama `main` de la web)

- `/app/tarjetas` (`Cards.jsx`): «Debes en total», «Próximo pago», los círculos «Anotar» y «Agregar
  tarjeta», y en celular filas compactas «{Franquicia} ••{últimos 4}» con lo usado, cuándo se paga,
  la barra de uso y «Disponible {x} de {cupo}». Sin tarjetas: una tarjeta de ejemplo y «Agregar mi
  primera tarjeta».
- `/app/tarjetas/:id` (`CardDetail.jsx`): lo que debes, cuándo se paga, la barra, el extracto, el
  aviso de vencimiento; los círculos «Anotar» (con `?tarjeta=`), «Abonar», «Actualizar saldo» y
  «Editar»; «Compras y pagos» (compras con cuotas, pagos que se pueden eliminar y ajustes del banco);
  «Eliminar tarjeta» con confirmación en línea.
- Hojas: `CardForm` (franquicia y nivel, últimos 4, vence MM/AA, cupo total, cupo disponible solo al
  crear, día de pago; nombre y día de corte en «Más detalles»), `PayCardForm` («Ya pagué») y
  `BankSyncForm` («Actualizar con el banco», con la vista previa del cargo).
- En Anotar y en Editar movimiento: «Pagado con» (efectivo o débito, o una tarjeta) y «Cuotas» (1 a
  48, informativas). El detalle del movimiento muestra la tarjeta o «Tarjeta eliminada».

### Qué se hizo

- **Pantallas:** `lib/features/cards/` con la lista, el detalle y las tres hojas, con los mismos
  textos, el mismo orden y los mismos estados que la web (cargando, vacío, error sin datos, datos
  viejos con aviso, montos ocultos, claro y oscuro, letra grande, inglés y portugués).
- **Entradas:** «Tarjetas» en «Más de tu plata» (Mi plata) ya no dice «En desarrollo», y el aviso de
  tarjeta del Inicio abre el detalle real. La lista se abre empujada, como Mi plata, con su botón de
  volver.
- **Movimientos:** «Pagado con» y «Cuotas» en Anotar (dentro de «Más detalles», que resume «· Tarjeta»
  o «· Efectivo o débito») y en Editar (después de la categoría, como `TransactionForm.jsx`).
  `?tarjeta=` preselecciona la tarjeta. Al editar se manda solo lo que cambió, y si se pasa a otra
  tarjeta las cuotas viajan con ella.
- **Sin conexión:** la cola de Anotar guarda la tarjeta y las cuotas. Si al reenviar la tarjeta ya no
  existe, se reenvía una sola vez, con el mismo `localId`, sin tarjeta ni cuotas, y la fila lo dice
  sin hablar de un error de sincronización.
- **Íconos** nuevos (de la misma familia Lucide que la web): `calendar-clock`, `circle-dollar-sign`,
  `refresh-cw` y `trash-2`; y el componente común `RindeCircleActions` (los círculos de la web).

### Escrituras y salvaguardas

`CardsWriter` sigue el patrón de `MoneyWriter` de la etapa 4:

- **Un envío a la vez** por operación y cuenta (`_once`): dos toques en «Agregar tarjeta», «Registrar
  pago» o «Actualizar» mandan **una** sola petición (probado también en el emulador con doble toque).
- **Cuenta y bienvenida:** la cuenta se lee antes de todo y se vuelve a comprobar antes de enviar; si
  otra cuenta entró a mitad, no se envía nada. Con la bienvenida a medias no se escribe.
- **En duda** (se venció la espera o el servidor respondió 5xx): el pago de tarjeta y el ajuste con el
  banco **no son idempotentes** en el servidor, así que nunca se reintentan solos.
  - Pago: antes de enviar se guardan los ids de los pagos; en duda solo se da por hecho si aparece un
    id **nuevo** con el mismo monto y la misma fecha. Si no, «No pudimos confirmar si se guardó.
    Revisa antes de intentarlo otra vez.», la hoja se cierra y el aviso queda sobre «Compras y pagos».
  - Ajuste con el banco: solo se da por hecho si lo leído coincide con lo enviado (disponible y, si se
    mandó, el extracto).
- **Borrar** (tarjeta o pago) con 404 cuenta como hecho, como la web.
- **Refrescos:** pagar o borrar un pago vuelve a pedir Mi plata y el plan (el pago sí resta); anotar
  o editar con tarjeta vuelve a pedir las tarjetas, el detalle y el aviso del Inicio (la compra **no**
  resta de Mi plata); el ajuste con el banco vuelve a pedir también Movimientos (puede crear «Cargos
  del banco»); editar o borrar la tarjeta refresca Movimientos.
- **Datos sensibles:** solo últimos 4 y MM/AA; esos campos van sin autocorrección, sin sugerencias y
  sin autollenado. Nunca el número completo ni el CVV.

### Textos nuevos que requieren aprobación

| Español | Inglés | Portugués | Por qué |
|---|---|---|---|
| «Monto pagado ({currency})» | «Amount paid ({currency})» | «Valor pago ({currency})» | La web lo deja fijo en «(COP)»; en COP se ve igual |
| «Próximo pago {when}» | «Next payment {when}» | «Próximo pagamento {when}» | La web hace un `.replace()` sin traducir (`Cards.jsx:172`) |
| «, vence {expiry}» | «, expires {expiry}» | «, vence {expiry}» | En la web va sin traducir (`CreditCardArt.jsx:17`) |

Las correcciones de las dos rondas no agregaron textos nuevos.

Texto de la web que conviene revisar (no se tocó): «Se paga {v1}» está traducido como «Paid {v1}» en
`en/07.json`, que en inglés se lee como «ya pagada» («Paid in 2 days»). Sugerencia para la web: «Due
{v1}». La app usa la misma traducción que la web.

### Revisión adversarial

1. **Primera ronda (4 revisores independientes):** paridad con la web, escrituras y plata,
   consistencia de la demo, e interfaz y pruebas. **16 hallazgos, todos corregidos**, cada uno con una
   prueba que falla sin la corrección. Los de más peso:
   - Las filas del historial no tenían llave: con la confirmación de «Eliminar pago» abierta, si
     llegaba otra fila arriba, se podía borrar **otro** pago.
   - Con `?tarjeta=` y la lista de tarjetas vieja en caché, la compra se guardaba en efectivo y
     bajaba Mi plata: ahora «Anotar» del detalle vuelve a pedir la lista y, mientras carga, la tarjeta
     se manda (el servidor la valida).
   - Un ajuste con el banco en duda con diferencia 0 se daba por hecho sin comprobar el extracto.
   - En 4 de las 6 escrituras la cuenta se leía tarde.
   - Editar o borrar una tarjeta no refrescaba Movimientos; al cambiar de tarjeta en la edición se
     perdían las cuotas.
   - Accesibilidad: botones de la confirmación de 37 px (ahora 48), la pregunta de la confirmación no
     llegaba al lector, el historial se desbordaba con letra grande.
2. **Segunda ronda (3 verificadores nuevos, con lentes distintos: las correcciones, la plata, y
   seguridad y alcance):**
   **6 hallazgos, todos corregidos** con su prueba (cada una falla sin la corrección):
   - **Pago doble posible:** después de «Abonar», mientras recargaba, el detalle seguía mostrando la
     deuda de antes y «Abonar» volvía a sugerir lo ya pagado. Ahora, al pagar o borrar un pago, la
     lista y el detalle muestran el esqueleto de carga en vez de la cifra vieja, como Mi plata.
   - **`?tarjeta=` sin señal:** si la recarga de la lista fallaba, la compra salía en efectivo y
     bajaba Mi plata. Ahora una lista en error se trata como desconocida: la tarjeta del enlace se
     manda y el servidor la valida.
   - **Ajuste con el banco en duda con el detalle viejo:** se daba por hecho y anunciaba un cargo que
     no existía. Ahora se toma una foto de la tarjeta antes de enviar y la duda se resuelve con ella;
     sin foto, queda «sin confirmar».
   - **Borrar un pago de una tarjeta ya eliminada** decía «Pago eliminado.» aunque el pago seguía
     restando. Ahora un 404 se comprueba: si la tarjeta ya no existe, se muestra el error.
   - **Datos de la tarjeta en el disco:** la cola sin conexión guardaba el nombre y los últimos 4 de
     la tarjeta. Ahora en el disco solo quedan el id de la tarjeta y las cuotas.
   - **Lector de pantalla:** la X que borra la fecha límite se anunciaba «Cancelar»; ahora dice
     «Quitar Fecha límite (opcional)» (texto que ya existía).
3. **Emulador (revisión mía):** dos errores que ninguna prueba atrapaba, ambos corregidos con su
   prueba (que falla sin la corrección):
   - **La barra de uso salía vacía** (con 30 % usado no se veía el relleno): el relleno quedaba de 0
     de alto dentro del `Stack`. Captura del antes: `06a-barra-vacia-antes-del-arreglo.jpg`.
   - **El aviso de la acción anterior seguía ahí** al volver de «Anotar» («Pago eliminado.» encima de
     una compra nueva).

### Lo que se vio en el emulador (demo, Android 16)

- Crear con doble toque → una sola tarjeta; validación con el foco en «Últimos 4»; MM/AA y montos con
  formato al escribir.
- Abonar 300.000 con doble toque → un solo pago, «Pago de este mes al día»; eliminarlo → lo usado
  vuelve a subir.
- «Anotar» desde la tarjeta → «Pagado con: Visa ••4242» ya elegida, 6 cuotas; el detalle suma la
  compra («a 6 cuotas*» con la nota de intereses), el aviso del Inicio pasa a $ 2.100.000 y la plata
  **no** baja. Gastos del mes sí la cuenta (como el servidor: solo Mi plata excluye las compras con
  tarjeta).
- Editar la compra a «Efectivo o débito» → la tarjeta vuelve a $ 900.000.
- «Actualizar saldo» con un disponible menor → vista previa «Se registrará un gasto de $ 50.000 en
  Cargos del banco.», un solo cargo con doble toque, y aparece en Movimientos.
- Error del servidor simulado al pagar → aviso «No pudimos confirmar si se guardó…», nada se da por
  guardado.
- Montos ocultos en Inicio, detalle e historial; tema oscuro; letra al 130 %; inglés con USD.
- Eliminar la tarjeta → vuelve al Inicio sin el aviso; sus compras dicen «Tarjeta eliminada».
- Escenario fijo «Plan listo» → abonar responde «Modo demostración: esta acción no llega a ningún
  servidor.» y no muestra nada como guardado.

### Lo que falta o no se comprobó en 5A

- **No se probó la app contra la API de QA**: los contratos sí se verificaron contra QA el 23-nov
  (§8), pero el recorrido de la app fue en la demo. Probarla contra QA exige iniciar sesión con la
  cuenta sintética en el emulador; queda para cuando David lo pida.
- **Riesgo de pago doble** si un pago queda en duda y tampoco se puede releer: la app avisa y no
  reintenta, pero la garantía real es la llave de reintento en el backend (propuesta B1, sin aprobar).
- **Demo:** pagar una tarjeta o anotar en efectivo no baja Mi plata en la demo (su plata sale de
  valores fijos desde la etapa 4); en cuentas reales la calcula el servidor y la app la vuelve a
  pedir (probado).
- iOS, un teléfono real y un lector de pantalla real (TalkBack o VoiceOver).

## 6. Bloque 5B — Deudas

**Estado:** terminado, probado y revisado. Subido a `feat/etapa-5-tarjetas-deudas`, en la misma PR
hacia `main`, **sin fusionar** (ver §17).

### Qué tenía React (rama `main` de la web)

- `/app/cuentas` (`Debts.jsx`): una sola pantalla, «Me deben» | «Debo» con el total de cada lado,
  tarjetas por cuenta (persona con iniciales, lo que falta, línea de avance, «Pagado {x} de {y} · {n}
  de {m} cuotas», próxima cuota o vencida, último abono), «Registrar abono», «Ya me pagó todo» / «Ya
  pagué todo», sección «Saldadas» con «ver el movimiento». Vacío por lado y «Todo está saldado.».
- `DebtForm.jsx`: tres pasos («Quién y cuánto», «Cómo se paga», «Cuándo avisar»); al editar, la
  sección «Abonos» y «Borrar cuenta».
- `PaymentForm.jsx`: monto que propone la próxima cuota o lo que falta, «Todo lo que falta», fecha y
  la casilla para anotar el movimiento.
- `lib/debts.js` y `lib/debtSchedule.js`: textos de cada lado, fechas cortas y el calendario de
  cuotas (copia del servidor, solo para la vista previa).

### Qué se hizo

- **Pantalla:** `lib/features/debts/` con la lista, las dos pestañas con su total, las tarjetas de
  cada cuenta, «Saldadas» y todos los estados (cargando, vacío por lado, todo saldado, error sin
  datos, datos viejos con aviso y «Reintentar»).
- **Hojas:** crear y editar en **dos pasos** («Paso 1 de 2 · Quién y cuánto», «Cómo se paga»), con
  la vista previa «{n} cuotas de {monto} · la última el {fecha}» y la nota «Esto no cambia lo que
  tienes en Mi plata hasta que registres un abono.»; «Registrar abono»; «Ya me pagó todo» / «Ya pagué
  todo»; borrar un abono y borrar la cuenta con confirmación en línea.
- **Entrada:** «Cuentas» en «Más de tu plata» (Mi plata) ya no dice «En desarrollo».
- **Componente común:** `ConfirmInline` pasó de `cards/` a `lib/design/widgets/` para usarlo en las
  dos pantallas.
- **De paso, en Tarjetas (5A):** la lista y el detalle vuelven a pedir los datos cada vez que se
  entra. Antes, si se pagaba desde la web, «Abonar» podía sugerir una deuda vieja (hallazgo de la
  segunda verificación del 5B, que aplicaba igual a 5A).

### Escrituras y salvaguardas

`DebtsWriter` sigue el patrón de `CardsWriter`:

- **Un envío a la vez** por operación y cuenta; la cuenta se lee antes de todo y se comprueba antes
  de enviar; con la bienvenida a medias no se escribe.
- **Crear y abonar no son idempotentes** en el servidor. Antes de enviar se toma una foto (ids de las
  cuentas o de los abonos de esa cuenta). Si queda en duda, solo se da por hecho si aparece un id
  **nuevo** con lo mismo que se mandó; si no, «No pudimos confirmar si se guardó. Revisa antes de
  intentarlo otra vez.» y nunca se reintenta solo.
- **Saldar:** un 409 solo cuenta como hecho si antes hubo una duda **y** la cuenta quedó saldada con
  lo que se pide ahora (con o sin movimiento). Si no, se recarga y se muestra el mensaje del servidor.
- **Borrar un abono:** un 404 o una duda obligan a releer; nunca se dice «borrado» si la cuenta quedó
  saldada.
- **Editar:** con cuotas se manda la **primera** cuota (`firstDueDate`), no la próxima que devuelve el
  servidor (la trampa de contrato verificada contra QA el 23-nov).
- **Refrescos:** la lista siempre vuelve a cargar mostrando la carga (no la cifra vieja, para que
  «Registrar abono» no sugiera lo ya abonado). Solo cuando hay movimiento de por medio (abono o saldo
  con la casilla, o borrar un abono que tenía uno) se vuelven a pedir Movimientos y Mi plata.
- **Lista vieja:** si la recarga falla y se ve lo último que llegó, «Registrar abono», «Ya me pagó
  todo» y el lápiz quedan desactivados hasta «Reintentar».

### Decisiones tomadas con la recomendación del plan (David no las ha contestado)

1. Se llama **«Cuentas»**, como el título de la web.
2. La fecha por defecto del abono y del préstamo es **la del teléfono**, como la web.
3. El paso **«Avisarme» no se porta**: la app no tiene notificaciones. El servidor igual avisa 1 día
   antes por defecto, y al editar se conserva el aviso que se eligió en la web.
4. **Borrar una cuenta** usa el texto de la web tal cual (la web no dice que los movimientos de sus
   abonos se quedan).
5. **B4 en la app:** no se deja guardar un monto **menor o igual** a lo ya abonado (en la web eso
   deja la cuenta trabada y saldar da 500). Necesita un texto nuevo.
6. En la demo se puede abonar y saldar aunque la plata de la demo no cambie.

### Textos nuevos que requieren aprobación

| Español | Inglés | Portugués | Por qué |
|---|---|---|---|
| «Tiene que ser mayor que lo que ya se abonó ({paid})» | «It has to be more than what has already been paid ({paid})» | «Tem que ser maior do que o que já foi pago ({paid})» | B4 (decisión 5) |
| «¿Cuánto? ({currency})» | «How much? ({currency})» | «Quanto? ({currency})» | La web deja «(COP)» fijo |
| «{tab}: pendientes» | «{tab}: pending» | «{tab}: pendentes» | En la web va sin traducir (`Debts.jsx:198`) |
| «{tab}: saldadas» | «{tab}: settled» | «{tab}: quitadas» | En la web va sin traducir (`Debts.jsx:218`) |

Traducciones de la web que conviene revisar (no se tocaron; la app usa las mismas): «Borrar cuenta»
→ «Delete account» (suena a borrar la cuenta de usuario), «· cuota» → «· share», «Cuentas» →
«Debts» y «el» → «the» («Last payment: $20 the Nov 9»).

### Revisión adversarial

1. **Primera ronda (4 revisores independientes):** paridad con la web, escrituras y plata, demo y
   fechas, interfaz y pruebas. **12 hallazgos: 11 corregidos y 1 que queda como limitación**, cada
   corrección con una prueba que falla sin ella. Los de más peso:
   - Saldar tomaba **cualquier** 409 como hecho, también en el primer intento.
   - En la demo, si no se podía leer el almacén de movimientos, abonar o saldar **borraba todos los
     movimientos de la demo**.
   - La casilla «anotar en Movimientos» se podía cambiar mientras guardaba.
   - Accesibilidad: «Todo lo que falta» sin acción para el lector; el botón de fecha sin el nombre
     del campo.
   - Septiembre salía «sep» y la web dice «sept».
   - **Limitación (no corregida):** los movimientos que crea la demo quedan en español aunque la app
     esté en inglés o portugués (en 5A pasa igual con «Cargos del banco»).
2. **Segunda ronda (3 verificadores nuevos):** **4 hallazgos, todos corregidos:**
   - Un 409 al saldar tras una duda se daba por hecho aunque el reintento pidiera otra cosa con la
     casilla (Mi plata quedaba sin el movimiento pedido).
   - Guardar y borrar a la vez en «Editar cuenta» sacaban a la persona de Cuentas.
   - **Al volver a entrar a Cuentas no se pedían los datos otra vez**: si se abonaba desde la web,
     «Registrar abono» sugería otra vez la cuota ya pagada (abono doble). Corregido también en
     Tarjetas.
3. **Emulador (revisión mía):** en inglés, la misma tarjeta decía «due dec 9» y «the 9 Nov». Ahora el
   mes va primero y con mayúscula («due Dec 4», «Nov 12»), con prueba que falla sin la corrección.

### Lo que se vio en el emulador (demo, Android 16)

- «Plan listo»: Laura (me debe, 3 cuotas, un abono) y Tío Jorge (le debo, de una vez), con sus
  totales.
- Recorrido «Usuario con movimientos»: vacío por lado → crear «Ana Pérez», 300.000 en 4 cuotas
  mensuales desde el 30 nov → vista previa «4 cuotas de $ 75.000 · la última el 28 feb 2027» (el fin
  de mes bien) → guardar con doble toque = **una** cuenta.
- Abonar 75.000 con doble toque → **un** abono, próxima cuota el 30 dic, y el ingreso «Abono de Ana
  Pérez» en Movimientos.
- Editar con monto 75.000 → «Tiene que ser mayor que lo que ya se abonó ($ 75.000)».
- «Ya me pagó todo» → saldada, con «ver el movimiento» que abre «Ana Pérez me pagó» por **solo**
  $ 225.000 (lo que faltaba). Ingresos del mes pasa de 2,5 a 2,8 millones.
- Error del servidor simulado al abonar → «No pudimos confirmar si se guardó…», nada guardado.
- Montos ocultos en pestañas, tarjetas y hojas; tema oscuro; letra al 130 %; inglés con USD.
- Borrar un abono (el abono y su gasto desaparecen) y borrar la cuenta → vacío de «Debo».

### Lo que falta o no se comprobó en 5B

- **No se probó la app contra la API de QA** (los contratos de deudas sí se verificaron el 23-nov).
- **Abono doble** si un abono queda en duda y tampoco se puede leer: la app avisa y no reintenta; la
  garantía real es la llave de reintento en el backend (propuesta B2, sin aprobar).
- Con la pantalla abierta, un abono hecho desde la web no se ve hasta salir y volver a entrar o tocar
  «Reintentar».
- Si la app se cierra entre una duda al saldar y su reintento, se pierde el registro de la duda: el
  409 sale como «Esta cuenta ya está saldada» y la lista la muestra saldada (no se pierde plata).
- iOS, un teléfono real y un lector de pantalla real.

## 7. Bloque 5C — Integración

Pendiente.

## 8. Contratos de backend

- Verificados leyendo el código del backend (`cards.*`, `debts.*`) y, el 23-nov-2026, **contra la
  API de QA con la cuenta sintética autorizada**: crear tarjeta (201), lista y detalle (200), pagar
  (201), eliminar el pago (204), ajustar con el banco (200), movimientos de la tarjeta (200); crear
  deuda en cuotas (201, con `dueDate` como primera cuota), abonar (201), saldar (200) y saldar
  repetido (**409, no duplica**). Las formas JSON exactas quedaron capturadas para las pruebas.
- `POST /cards/:id/payments` y `/sync-with-bank` **no** son idempotentes: la app mitiga con un envío
  a la vez y, en duda, releyendo los ids antes de dar nada por guardado. La propuesta de backend
  (llave `localId` reutilizando `idempotency_keys`, que ya está en `main`) queda documentada para
  aprobación; no bloquea la etapa.
- `openapi.yaml` sigue desactualizado (faltan `cardDates` y campos de cuotas y avisos de `/debts`);
  los contratos de esta etapa salen del código.

## 9. Seguridad y consistencia financiera

- Solo se piden los últimos 4 dígitos y el vencimiento MM/AA; nunca el número completo ni el CVV.
- Nada de tarjetas o deudas se guarda en disco en cuentas reales (la web sí guarda su copia en
  IndexedDB sin cifrar; esa copia no se porta). La única excepción es la cola sin conexión de Anotar,
  que ya existía y va en el almacenamiento seguro: guarda el **id** de la tarjeta y las cuotas, nunca
  el nombre ni los últimos 4 (corregido en la segunda revisión del 5A, con prueba).
- Doble conteo que la web arrastra y la app **no** imita: confirmar en «Por confirmar» un gasto que
  fue con crédito lo resta dos veces (al confirmarlo y al pagar la tarjeta). «Por confirmar» sigue
  «En desarrollo» en la app; queda documentado para cuando se migre.

## 10. Modo demo

### 5A

- La demo sigue fuera de las versiones de tienda: `AppConfig.demoMode` exige `DEMO_MODE=true` **y**
  que no sea una compilación de lanzamiento (`!kReleaseMode`).
- Las tarjetas de la demo van en un almacén propio por cuenta sintética
  (`rinde.demo.tarjetas.<id>`), aparte del resto del estado; «Reiniciar demostración» las borra.
- **Recorridos** (Usuario nuevo, Usuario con movimientos, Sin plan): crear, editar, pagar, borrar
  pagos, ajustar con el banco y borrar la tarjeta se guardan en el teléfono. Lo usado sigue la regla
  del servidor (la base más las compras con la tarjeta y los cargos del banco), el extracto se borra
  como en `cards.logic.js` y los días se cuentan en UTC.
- **Escenarios fijos** (Plan listo, Te faltan, Estás en negativo): solo leen. La «Visa ••4242» de
  Plan listo es la misma del aviso del Inicio. Cualquier escritura responde «Modo demostración: esta
  acción no llega a ningún servidor.» y nada se muestra como guardado (visto en el emulador).
- **Panel:** tres fallas nuevas para simular «Sin conexión» o «Error del servidor»: «Tarjetas: leer
  la lista», «Tarjetas: leer el detalle» y «Tarjetas: guardar».
- **Limitación:** en la demo, pagar una tarjeta (o anotar en efectivo) no baja Mi plata, porque su
  plata sale de valores fijos desde la etapa 4. En cuentas reales la calcula el servidor y la app la
  vuelve a pedir después de cada escritura (con prueba).

### 5B

- Las cuentas de la demo van en su propio almacén por cuenta sintética (`rinde.demo.cuentas.<id>`);
  «Reiniciar demostración» lo borra.
- **Plan listo** trae dos cuentas: «Laura» (me debe 60.000 en 3 cuotas mensuales, con un abono de
  20.000) y «Tío Jorge» (le debo 120.000 de una vez, con fecha). Sus abonos no dicen venir de ningún
  movimiento, para que cuadren con Movimientos. Como todo escenario fijo, **no guarda**.
- **Recorridos:** crear, editar, abonar, saldar, borrar abonos y borrar cuentas se guardan, con el
  calendario de cuotas de la web (fin de mes y quincena = 15 días). Con la casilla marcada, el
  movimiento («Abono de X», «Abono a X», «X me pagó», «Le pagué a X») entra a los Movimientos de la
  demo; borrar el abono lo borra.
- **Panel:** «Cuentas: leer» y «Cuentas: guardar» para simular «Sin conexión» o «Error del servidor».
- **Limitaciones:** la plata de la demo no cambia al abonar o saldar (igual que en 5A), y los
  movimientos que crea la demo quedan en español aunque la app esté en inglés o portugués.

## 11. Pruebas

Etiquetas: **lógica real** (el código de la app con repositorios falsos), **contrato QA** (respuestas
reales capturadas de la API de QA), **demo** (emulador con la demo), **QA** (contra el servidor de
QA), **pendiente iOS**.

### 5A

| Comprobación | Resultado | Tipo |
|---|---|---|
| `flutter analyze` | Sin hallazgos | — |
| `dart format --line-length 110` | 0 archivos cambiados | — |
| `flutter test` completo | **1342 de 1342 en verde** (antes de la etapa: 1218) | Lógica real |
| Contratos de los 9 endpoints de tarjetas (formas, montos como números, PUT sin `available`, ajuste sin opcionales vacíos, 204/404 al borrar) | En verde | Contrato QA |
| Doble envío, pago y ajuste en duda, cuenta que cambia a mitad, bienvenida a medias | En verde | Lógica real |
| Refrescos de Mi plata, plan, Movimientos, Inicio y detalle tras cada escritura | En verde | Lógica real |
| Movimientos con tarjeta y cuotas: diff de edición, cola, cardDropped, nada sensible en disco | En verde | Lógica real |
| 320 px con la letra al doble, claro y oscuro, montos ocultos, inglés y portugués con USD y BRL | En verde | Lógica real |
| Recorrido completo en el emulador (Android 16, Medium Phone API 36) | Bien, con 2 errores encontrados y corregidos | Demo |
| APK de depuración con la demo | Compila e instala | — |
| `gitleaks` en `lib`, `test`, `docs`, `tool` y `assets/l10n` | Sin hallazgos | — |
| La app contra la API de QA | **No se hizo** (los contratos sí, el 23-nov) | QA pendiente |
| iOS | Sin compilar ni probar (no hay Mac) | Pendiente iOS |

Pruebas nuevas en `test/features/cards/`: `card_rules_test.dart` (reglas y cuerpos que se envían),
`cards_writer_test.dart` (escrituras, duda, doble envío, aislamiento), `cards_screen_test.dart`
(pantallas y hojas) y `demo_cards_test.dart` (la demo). Ajustadas o ampliadas: `router_test`,
`pending_module_screen_test`, `demo_home_repository_test`, `record_form_test`, `record_screen_test`,
`data_saver_test` y `list_screen_test`.

### 5B

| Comprobación | Resultado | Tipo |
|---|---|---|
| `flutter analyze` | Sin hallazgos | — |
| `dart format --line-length 110` | Sin cambios pendientes | — |
| `flutter test` completo | **1466 de 1466 en verde** (después de 5A: 1342) | Lógica real |
| Contratos de `/debts` (POST sin `reminder`, PUT sin `kind`, `dueDate` = primera cuota al editar, saldar sin fecha, montos como número) | En verde | Contrato QA |
| Validaciones de la web, B4 y el calendario de cuotas (fin de mes, quincena, casos de `debtSchedule.test.js`) | En verde | Lógica real |
| Doble envío, abono y cuenta en duda, saldar con 409, 404 de abono en cuenta saldada | En verde | Lógica real |
| Refrescos: con casilla vuelven a pedir Movimientos y Mi plata; sin casilla, no; tras escribir, la lista muestra la carga | En verde | Lógica real |
| Volver a entrar a Cuentas y a Tarjetas vuelve a pedir los datos | En verde | Lógica real |
| 320 px con letra al doble y datos extremos (nombre de 60, nota de 200, 60 cuotas, 30 cuentas por lado), claro y oscuro, montos ocultos, inglés y portugués | En verde | Lógica real |
| Recorrido completo en el emulador | Bien, con 1 error de fechas en inglés encontrado y corregido | Demo |
| `gitleaks` en `lib`, `test`, `docs`, `tool` y `assets/l10n` | Sin hallazgos | — |
| La app contra la API de QA | **No se hizo** (los contratos sí, el 23-nov) | QA pendiente |
| iOS | Sin compilar ni probar | Pendiente iOS |

Pruebas nuevas en `test/features/debts/`: `debt_rules_test.dart`, `debts_writer_test.dart`,
`debts_screen_test.dart` y `demo_debts_test.dart`, con `test/support/debt_fixtures.dart` (formas
reales de QA) y `fake_debts_repository.dart`. Ajustadas: `router_test`, `pending_module_screen_test`,
`demo_home_repository_test` y `cards_screen_test` (volver a entrar).

## 12. Capturas

### 5A (`docs/etapa-05/`, demo en el emulador)

| Archivo | Qué muestra |
|---|---|
| `01-tarjetas-vacia.jpg` | Lista sin tarjetas: tarjeta de ejemplo e invitación |
| `02-agregar-tarjeta.jpg` | Hoja «Agregar tarjeta»: franquicia y nivel |
| `03-agregar-validacion.jpg` | Validación al guardar vacío, foco en «Últimos 4» |
| `04-agregar-lleno.jpg` | Formulario lleno (MM/AA y montos con formato) |
| `05-mas-detalles.jpg` | «Más detalles»: nombre y día de corte |
| `06a-barra-vacia-antes-del-arreglo.jpg` | **Error encontrado:** la barra de uso vacía |
| `06-lista-con-barra.jpg` | Lista con la barra corregida |
| `07-inicio-aviso-tarjeta.jpg` | Aviso de tarjeta en el Inicio |
| `08-detalle.jpg` | Detalle de la tarjeta |
| `09-abonar.jpg` | Hoja «Ya pagué» |
| `10-detalle-tras-abono.jpg` | Un solo pago tras doble toque, «Pago de este mes al día» |
| `11-eliminar-pago-confirmar.jpg` | Confirmación en línea de «Eliminar pago» |
| `12-pago-eliminado.jpg` | Lo usado vuelve a subir |
| `13-anotar-con-tarjeta.jpg` | Anotar abierto desde la tarjeta |
| `14-anotar-pagado-con-cuotas.jpg` | «Pagado con» y «Cuotas» en «Más detalles» |
| `15-inicio-tras-compra.jpg` | La plata no baja; el aviso de la tarjeta sube |
| `16-editar-pagado-con.jpg` | Editar movimiento con «Pagado con» |
| `17-inicio-tras-pasar-a-efectivo.jpg` | La tarjeta vuelve a su deuda al pasar la compra a efectivo |
| `18-actualizar-saldo.jpg` | Hoja «Actualizar con el banco» |
| `19-actualizar-vista-previa.jpg` | Vista previa del cargo del banco |
| `20-tras-actualizar.jpg` | Un solo cargo «Cargos del banco» |
| `21-editar-tarjeta.jpg` | Hoja «Editar tarjeta» |
| `22-detalle-oscuro.jpg` | Detalle en tema oscuro |
| `23-pago-en-duda-oscuro.jpg` | Pago en duda: «No pudimos confirmar si se guardó…» |
| `24-detalle-montos-ocultos.jpg` | Montos ocultos en el detalle |
| `25-eliminar-tarjeta-confirmar.jpg` | Confirmación de «Eliminar tarjeta» |
| `26-tras-eliminar-tarjeta.jpg` | Vuelve al Inicio sin el aviso |
| `27-compra-tarjeta-eliminada.jpg` | La compra dice «Tarjeta eliminada» |
| `28-planlisto-inicio-letra-130.jpg` | Escenario Plan listo, letra al 130 % |
| `29-planlisto-detalle-letra-130.jpg` | Detalle con letra al 130 % |
| `30-escenario-fijo-no-guarda.jpg` | Escenario fijo: la escritura no llega a ningún servidor |
| `31-detalle-en-usd.jpg` | Detalle en inglés con USD |

### 5B (`docs/etapa-05/`, demo en el emulador)

| Archivo | Qué muestra |
|---|---|
| `40-cuentas-me-deben.jpg` | «Plan listo»: Laura, con cuotas y un abono |
| `41-cuentas-debo.jpg` | «Plan listo»: Tío Jorge, de una vez |
| `42-cuentas-vacia.jpg` | Vacío de «Me deben» |
| `43-agregar-paso-1.jpg` | Paso 1 de 2: quién y cuánto |
| `44-agregar-validacion.jpg` | Validación con el foco en el nombre |
| `45-agregar-paso-2.jpg` | Paso 2 de 2: cómo se paga |
| `46-agregar-cuotas-vista-previa.jpg` | En cuotas, con la vista previa (fin de mes) |
| `47-cuenta-creada.jpg` | Una sola cuenta tras doble toque |
| `48-registrar-abono.jpg` | «Registrar abono» con la casilla marcada |
| `49-tras-abono.jpg` | Un solo abono; próxima cuota |
| `50-editar-cuenta.jpg` | «Editar cuenta» con «Abonos» y «Borrar cuenta» |
| `51-validacion-b4.jpg` | B4: el monto tiene que ser mayor que lo abonado |
| `52-ya-me-pago-todo.jpg` | «Ya me pagó todo» |
| `53-cuenta-saldada.jpg` | «Saldadas» con «ver el movimiento» |
| `54-ver-el-movimiento.jpg` | El ingreso solo por lo que faltaba |
| `55-movimientos-abono-y-saldo.jpg` | El abono y el saldo en Movimientos, uno de cada uno |
| `56-abono-en-duda-oscuro.jpg` | Abono en duda (tema oscuro) |
| `57-cuentas-montos-ocultos.jpg` | Montos ocultos en la lista |
| `58-abono-montos-ocultos.jpg` | Montos ocultos en la hoja de abono |
| `59-borrar-abono-confirmar.jpg` | Confirmación de «Borrar abono» |
| `60-tras-borrar-abono.jpg` | El abono ya no está |
| `61-borrar-cuenta-confirmar.jpg` | Confirmación de «Borrar cuenta» |
| `62-tras-borrar-cuenta.jpg` | Vacío de «Debo» |
| `63-cuentas-letra-130.jpg` | Letra al 130 % |
| `64-cuentas-ingles-usd.jpg` | Inglés con USD, «due Dec 4» |

## 13. QA y pendientes

- API de QA revisada el 23-nov-2026: `/health` 200, CORS correcto, certificado hasta el 14-feb-2027.
- **Cuenta de prueba sintética creada con autorización de David** (23-nov-2026): alias del correo del
  dueño, contraseña en un archivo local fuera de Git. Sin datos financieros reales. Con ella se
  verificaron los contratos de arriba.
- El backend de QA sigue sin la idempotencia de la bienvenida y sin la versión del perfil.
- El `appUrl` del backend de QA es `https://qa.rindecol.online` (lo mostró el correo de verificación).
- **5A y 5B:** la app no se probó contra QA; su recorrido fue en la demo. Los contratos de tarjetas
  y deudas sí se verificaron contra QA (§8).

## 14. iOS y pendientes

Sin cambios: no hay Mac disponible; iOS sigue sin compilar ni probar.

## 15. Diferencias justificadas con la web

### 5A

1. **Sin barra de pestañas en Tarjetas.** La web la muestra con «Planear» marcado; la app abre la
   lista empujada, como Mi plata, con su botón de volver (Planear sigue «En desarrollo»).
2. **«Pago atrasado» con deuda 0 no se muestra**, para no avisar algo falso (sigue el criterio del
   aviso del Inicio).
3. **«Debes en total» se suma en centavos**; la web suma decimales y puede arrastrar residuos.
4. **Editar tarjeta manda solo lo que cambió**; la web manda el formulario entero.
5. **El 409 de «últimos 4 repetidos» sale en su campo**; en la web sale abajo como texto suelto.
6. **«Monto pagado» lleva la moneda de la persona**; la web lo deja fijo en «(COP)».
7. **«Reintentar» también en el detalle con datos viejos**, con «Lo que ves puede estar
   desactualizado: es lo último que llegó.»; la web solo muestra el error.
8. **`?tarjeta=` cuando la lista no carga o falla: la tarjeta se manda igual** y el servidor la
   valida. La web la pasa a efectivo sin avisar y baja Mi plata por error.
9. **«Te avisamos 2 meses antes para que pidas la nueva.» no se muestra**: promete un aviso push
   que la app todavía no recibe.
10. **Últimos 4 y vencimiento sin autollenado ni sugerencias** (la web usa `cc-exp`).
11. **La tarjeta dibujada no crece con la letra del sistema** (es un dibujo de tamaño fijo); su
    contenido va completo en la etiqueta del lector.
12. **«Agregar tarjeta» siempre visible**: la app no detecta la conexión; sin red, la escritura falla
    con el mensaje de red y la hoja no se cierra.
13. **Al eliminar una tarjeta se vuelve a donde se vino** (lista o Inicio); la web va siempre a la
    lista.
14. **El aviso de éxito respeta los montos ocultos**, también para el lector.
15. **Día de pago de 1 a 31**, como la validación de la web y el servidor.
16. **Fechas del historial con el formato de la app.**
17. **Al cambiar de tarjeta en la edición, las cuotas viajan con ella**; la web solo manda la tarjeta
    y el servidor guarda 1 cuota aunque el formulario muestre otra cifra.
18. **«Anotar» desde el detalle vuelve a pedir la lista de tarjetas** (con una lista vieja, la compra
    iría en efectivo).
19. **Pago en duda sin confirmar:** la hoja se cierra y el aviso queda sobre «Compras y pagos», para
    revisar antes de repetir.
20. **Tras pagar o borrar un pago, la lista y el detalle muestran la carga**, no la cifra vieja (evita
    un pago doble por una sugerencia vieja).
21. **Borrar un pago con 404 se comprueba**: si la tarjeta ya no existe, se muestra el error en vez de
    «Pago eliminado.».
22. **Botones de la confirmación en línea con 48 de alto táctil**, con el aspecto pequeño de la web.

### 5B

1. **Dos pasos en vez de tres:** sin «Cuándo avisar» (la app no tiene notificaciones; el servidor
   igual avisa 1 día antes y conserva el aviso elegido en la web).
2. **Sin barra de pestañas:** la pantalla se abre empujada y «atrás» va a Planear, como Tarjetas.
3. **«Agregar» va bajo la descripción**, no en el encabezado, y siempre visible (la app no detecta
   la conexión).
4. **Pestañas propias** con dos líneas y el total, para que el lector oiga «Monto oculto» y no la
   máscara.
5. **Meses en el idioma de la app** (la web los deja en español), con el mes primero en inglés.
6. **«¿Cuánto?» lleva la moneda de la persona.**
7. **B4:** el monto al editar tiene que ser mayor que lo abonado.
8. **Montos ocultos** también en la vista previa del plan y en los errores con montos.
9. **Escrituras con salvaguardas:** sin confirmar, 409 o 404 cierran la hoja y dejan el aviso en la
   lista; un 409 al saldar solo es «hecho» si coincide con lo que se pidió; con la lista vieja no se
   puede escribir sobre esos datos.
10. **Volver a entrar recarga** la lista (también en Tarjetas), para no sugerir una cuota ya pagada.
11. **Botones del formulario apilados** («Siguiente/Guardar» arriba, «Atrás» abajo) para que no se
    desborden con la letra grande.

## 16. Archivos

### 5A

Nuevos:

- `lib/features/cards/application/`: `cards_providers.dart`, `cards_writer.dart`.
- `lib/features/cards/data/`: `card_models.dart`, `cards_repository.dart`,
  `demo_cards_repository.dart`, `demo_cards_store.dart`.
- `lib/features/cards/domain/card_rules.dart`.
- `lib/features/cards/presentation/`: `cards_screen.dart`, `card_detail_screen.dart` y en
  `widgets/`: `bank_sync_sheet`, `card_history`, `card_row`, `card_sheet`, `confirm_inline`,
  `credit_card_art`, `expiry_badge`, `pay_card_sheet`.
- `lib/design/widgets/rinde_circle_actions.dart`.
- `assets/icons/`: `calendar-clock.svg`, `circle-dollar-sign.svg`, `refresh-cw.svg`, `trash-2.svg`.
- `test/features/cards/`: `card_rules_test`, `cards_screen_test`, `cards_writer_test`,
  `demo_cards_test`; `test/support/`: `card_fixtures.dart`, `fake_cards_repository.dart`.
- `docs/ETAPA_05_TARJETAS_DEUDAS.md` y `docs/etapa-05/` (32 capturas).

Modificados:

- `lib/app/router.dart` (rutas de tarjetas y `?tarjeta=`), `lib/app/pending_modules.dart`.
- `lib/design/widgets/rinde_icon.dart`, `lib/design/widgets/rinde_text_field.dart`
  (`enableSuggestions`).
- `lib/features/movements/`: `application/movement_saver.dart`, `data/demo_movements_repository.dart`,
  `domain/movement.dart`, `presentation/list/movements_screen.dart`,
  `presentation/record/movement_form.dart`, `presentation/record/record_screen.dart`.
- `lib/features/home/data/demo_home_repository.dart`,
  `lib/features/onboarding/data/demo_onboarding_repository.dart`,
  `lib/features/onboarding/presentation/demo_panel.dart`.
- `tool/l10n_mobile/{en,pt}.json` y `assets/l10n/{en,pt}.json` (regenerados).
- Pruebas: `router_test`, `pending_module_screen_test`, `demo_home_repository_test`,
  `record_form_test`, `record_screen_test`, `data_saver_test`, `list_screen_test`.

No se tocó: el backend, la web (React), producción, ni la cuenta de QA fuera de lo descrito en §13.

### 5B

Nuevos:

- `lib/features/debts/data/`: `debt_models.dart`, `debts_repository.dart`,
  `demo_debts_repository.dart`, `demo_debts_store.dart`.
- `lib/features/debts/domain/`: `debt_schedule.dart`, `debt_rules.dart`.
- `lib/features/debts/application/`: `debts_providers.dart`, `debts_writer.dart`.
- `lib/features/debts/presentation/`: `debts_screen.dart` y en `widgets/`: `side_switch`,
  `debt_card`, `debt_sheet`, `debt_payment_sheet`, `settle_sheet`, `debt_date_field`.
- `lib/design/widgets/confirm_inline.dart` (movido desde `cards/presentation/widgets/`).
- `test/features/debts/`: `debt_rules_test`, `debts_writer_test`, `debts_screen_test`,
  `demo_debts_test`; `test/support/`: `debt_fixtures.dart`, `fake_debts_repository.dart`.
- `docs/etapa-05/` 40 a 64 (25 capturas).

Modificados:

- `lib/app/router.dart`, `lib/app/pending_modules.dart`.
- `lib/features/cards/presentation/`: `cards_screen.dart` y `card_detail_screen.dart` (volver a
  pedir al entrar), `widgets/card_history.dart` (import de `ConfirmInline`).
- `lib/features/onboarding/data/demo_onboarding_repository.dart`,
  `lib/features/onboarding/presentation/demo_panel.dart`.
- `tool/l10n_mobile/{en,pt}.json` y `assets/l10n/{en,pt}.json` (regenerados).
- Pruebas: `router_test`, `pending_module_screen_test`, `demo_home_repository_test`,
  `cards_screen_test`.

## 17. Commits y PR

### 5A

- Rama: `feat/etapa-5-tarjetas-deudas` (sale de `main` en `a8f0541`).
- Commit del bloque: `c5ef34b` (verificado en GitHub con `git ls-remote`).
- PR: [fintrackcol-org/rinde-mobile#2](https://github.com/fintrackcol-org/rinde-mobile/pull/2) hacia `main`, **sin fusionar** (la fusión la decide David).

### 5B

- Rama: la misma, `feat/etapa-5-tarjetas-deudas`.
- Commit del bloque: <<COMMIT5B>>.
- PR: la misma, [fintrackcol-org/rinde-mobile#2](https://github.com/fintrackcol-org/rinde-mobile/pull/2),
  **sin fusionar**.

## 18. Riesgos abiertos

- Pagos de tarjeta y abonos sin idempotencia en el backend (mitigado en el cliente; propuesta
  pendiente de aprobación).
- `PUT /debts` acepta un monto menor o igual que lo ya abonado y deja la cuenta trabada (saldar
  da 500): la app lo validará en el cliente; el arreglo de backend queda propuesto.
- La web tiene textos sin traducir y la moneda fija en «Monto pagado (COP)»: la app los corrige y lo
  documenta como diferencia.
- En inglés, la web traduce «Se paga {v1}» como «Paid {v1}» («Paid in 2 days»), que se lee como ya
  pagada. La app usa la misma traducción; conviene corregirla en la web («Due {v1}»).

- **Abono doble** si un abono queda en duda y tampoco se puede leer (sin idempotencia en el backend;
  propuesta B2 sin aprobar). Lo mismo al crear una cuenta, aunque esa no toca la plata.
- Con Cuentas abierta, un abono hecho desde la web no se ve hasta volver a entrar o tocar
  «Reintentar».
- Traducciones de la web que se leen mal en inglés y la app hereda: «Delete account» (borrar cuenta
  de deuda), «· share» (cuota), «the» (fecha del último abono).

## 19. Recomendación para la siguiente etapa

Pendiente de cerrar los tres bloques.
