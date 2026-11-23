# Rinde Mobile · Etapa 2: cierre del onboarding e Inicio financiero

Fecha: 22 de noviembre de 2026
Base: `main` en `38f99e4`. **Sin commit ni push: todo espera revisión.**
Fuente de verdad: Rinde Web `origin/main` en `dd0068a`, solo lectura.

> **La app no se ha conectado a ningún servidor.** No hay URL de QA. Todo lo que se ve con datos en
> las capturas es MODO DEMOSTRACIÓN, con respuestas sintéticas. Nada de esto prueba que la integración
> con el backend funcione.

| Afirmación | Estado |
|---|---|
| Implementado y probado en Flutter | Sí: pruebas automáticas y emulador Android |
| Probado solo con datos simulados | Todo lo que lee o guarda plata |
| Pendiente de backend QA | Integración completa (sección L) |
| Pendiente de validación en iOS | Todo: no se puede probar desde Windows |

---

## A. Estado de la implementación

| Objetivo | Estado |
|---|---|
| 1. Onboarding cerrado y consistente | Hecho. Falta tu decisión de marca sobre Rin |
| 2. Inicio real | Hecho: reemplaza el provisional |
| 3. Identidad visual | Hecho con tokens, fuente, logo e íconos existentes. Sin dependencias nuevas |
| 4. Rin con criterio | En el Inicio, solo en el estado vacío |
| 5. Cifras coherentes | Las calcula el servidor. Un dato que falta nunca se pinta como cero |
| 6. Carga, error y sin datos | Hecho, cada bloque por separado |
| 7. Navegación honesta | Inicio funcional. 14 destinos dicen «En desarrollo» |
| 8. Demostración segura | 6 escenarios y fallas simuladas. Apagada en builds de tienda |
| 9. Pruebas y emulador | 818 pruebas y 48 capturas |
| 10. Lista para QA | Contratos y repositorio real escritos. **Sin probar contra un servidor** |

No se implementó: registrar movimientos, Movimientos, Planear, Mi plata, Cuenta, calendario,
notificaciones ni sincronización sin conexión. Están fuera de esta etapa.

### Qué tiene el Inicio de React y dónde quedó

| Elemento | Dónde vive en la web | En Flutter | Depende de |
|---|---|---|---|
| Logo, campana con no leídos, ocultar montos | celular | Hecho | Notificaciones (destino) |
| Libre para gastar / Te faltan / Negativo | celular | Hecho | Mi plata (destino) |
| Mi plata con «te alcanza N días» | celular | Hecho | Mi plata (destino) |
| Lo próximo (2 pagos) | celular | Hecho | Pagos del mes (destino) |
| Este mes: ingresos y gastos | celular | Hecho | Ingresos, Gastos (destinos) |
| Por confirmar | celular | Hecho | Por confirmar (destino) |
| Un solo aviso | celular | Hecho | Tarjetas, Presupuestos (destinos) |
| Invitación o acceso a configurar | celular | Hecho | Las preguntas ya existen |
| Estado vacío | celular y escritorio | Hecho | Anotar, WhatsApp (destinos) |
| Barra de pestañas | celular | Hecho | Movimientos, Planear, Cuenta |
| Tutorial `CoachTour` | ambos | Hecho, con una compuerta (sección H) | Los mismos módulos |
| Últimos 6 movimientos, 3 presupuestos, calendario, gráficos | **solo escritorio** | No se porta | — |

---

## B. Cierre del onboarding

### Los dos hallazgos que quedaron a medias

| Hallazgo original | Causa verificada | Estado |
|---|---|---|
| #26: el idioma saltaba al del país sugerido | El borrador nuevo tomaba el idioma del país | Corregido: arranca en el idioma que se ve y solo cambia si la persona elige |
| #28: «millones» en español en inglés y portugués | Palabra escrita a mano, sin plurales | Corregido con tabla por idioma y singular del portugués («1,5 milhão») |

También se completaron tres que habían quedado con arreglo mínimo: anuncio del paso al lector (#14),
selector que se apila con letra grande (#21) y margen del teclado según el tamaño de letra (#22).

### Defectos nuevos que aparecieron al conectar un Inicio real

| Defecto | Gravedad | Arreglo |
|---|---|---|
| Una renovación tardía del token podía revivir una sesión cerrada o pasar una escritura a otra cuenta | Alta | Se descarta si la sesión ya no es la vigente |
| Cambiar de idioma tras guardar duplicaba los pagos mensuales | Alta | Desde que la etapa 1 sale, los pagos no se editan ni se renombran |
| Si la respuesta se perdía, se podían perder las fuentes de ingreso | Alta | Se anota antes de enviar y se confirma con lo que tiene el servidor |
| «Bienvenida hecha» se tomaba como prueba de que el saldo y los pagos se guardaron | Alta | Se compara con los pagos y el saldo que devuelve el servidor |
| Al terminar, el Inicio mostraba el plan viejo | Alta | Se vuelve a pedir todo el Inicio |
| Datos de una cuenta visibles al entrar con otra sin conexión | Alta | Una copia de datos por ingreso |
| Reintentos automáticos dejaban la app girando unos 38 segundos | Media | Apagados: el fallo se muestra y la persona reintenta |
| Los términos se saltaban al recargar el perfil | Media | El último «no aceptado» manda |
| La bienvenida era una trampa si el guardado fallaba | Media | Aparece «Cerrar sesión» |
| Un saldo omitido se rellenaba con la propuesta sin que se viera | Media | Pasado el paso Saldo, vacío es una respuesta |
| Las pantallas de acceso no se traducían | Media | Login, registro, recuperar, bienvenida y arranque usan traducciones |

El guardado en dos etapas y el borrador cifrado se conservan. Regla de los pagos:

- **No salió del teléfono, o el servidor lo rechazó:** se puede corregir.
- **Pudo llegar (espera vencida, corte):** quedan bloqueados y se dice que no se sabe. «Ver mi plata»
  los envía otra vez iguales. «Omitir» no los repite, por si los cambió en la web.
- **El servidor los tiene (todos, por nombre):** bloqueados, con «ya quedaron guardados». Si después
  cambia el saldo, solo viaja el saldo.
- **El saldo se comprueba aparte, por valor.** Si el servidor tiene otro, se muestra en el paso Saldo
  antes de reemplazarlo. Un saldo que el servidor ya confirmó no se vuelve a enviar.
- **Se omitieron:** no se bloquea nada.
- Todo envío con saldo devuelve el tipo de ingreso que el servidor ya tenía, para no borrarlo.
- Cualquier envío sin terminar se retoma al abrir.

Esta regla se comprueba con un modelo (`save_model_test.dart`) que recorre unas 64.000 secuencias de
acciones y fallas, en cuatro situaciones de partida, contra las reglas del servidor leídas en su
código. Dentro de lo que modela no hay «guardado» falso, pago doble, respuesta perdida, tipo de
ingreso ajeno borrado ni pantalla sin salida. No modela cambios hechos en la web a mitad del guardado,
fallas del llavero ni un 500 en las fuentes: eso tiene pruebas directas o está en «Límites conocidos».
Hizo falta: las revisiones por casos encontraron regresiones en dos rondas seguidas de correcciones.

### Sigue pendiente del onboarding

- La decisión de marca sobre Rin ([RIN_EN_MOBILE.md](RIN_EN_MOBILE.md)).
- Todo lo que necesita una respuesta real de QA.
- Probar con TalkBack encendido.

---

## C. Arquitectura del dashboard

```
lib/features/home/
  data/          home_models · home_repository (API) · demo_home_repository
  domain/        home_view (estados) · home_notice (prioridad) · runway (ritmo) · home_dates
  application/   home_providers (carga, refresco, día, ocultar montos) · tour_controller
  presentation/  home_screen · widgets/ (tarjetas y avisos) · tour/ (tutorial)
lib/features/shell/   barra de pestañas y pantalla «En desarrollo»
lib/app/pending_modules.dart   lista única de destinos pendientes
```

- **Presentación:** solo dibuja `HomeView`. No hace peticiones ni cuentas.
- **Reglas:** `buildHomeView` es una función pura, probada con la tabla de combinaciones.
- **Datos:** la sesión decide el repositorio. Una sesión demo no puede usar la API.
- **Por ingreso:** perfil, bienvenida y bloques se guardan por sesión. Salir y entrar empieza de cero.
- **Actualización:** al halar, al volver al Inicio o a la app después de 5 minutos, y al cambiar el día.
- **Dependencias nuevas:** ninguna.

| Bloque | Endpoint |
|---|---|
| Saldo, bienvenida, pagos guardados | `GET /money-profile` |
| ¿Hay movimientos? | `GET /transactions?page=1&pageSize=1` |
| Plan | `GET /money-profile/plan` |
| Totales del mes | `GET /transactions/summary?period=month&date=` |
| Presupuestos | `GET /budgets?month=` |
| Tarjetas | `GET /cards` |
| Por confirmar | `GET /pending-payments` |
| No leídos | `GET /notifications` |
| Nombres de categorías | `GET /categories` |
| Tutorial visto | `POST /money-profile/tutorial` |

---

## D. Correspondencia con React

**Se conserva:** orden de los bloques, textos, los tres estados del plan, 2 pagos, un solo aviso con su
prioridad, la cifra que se achica, «+» en ingresos, las cinco posiciones de la barra y los ocho pasos
del tutorial.

**Cambia por integridad financiera:**

| Rinde Web | Rinde Mobile | Por qué |
|---|---|---|
| Sin saldo muestra «$ 0» | «—» y la razón | Un dato que falta no es un cero |
| Sin saldo usa el balance del mes como «Mi plata» | No lo usa | El balance del mes no es el saldo |
| Un plan cuya recarga falló sigue como vigente | Se oculta | Puede estar viejo |
| Datos viejos sin marca | «Lo que ves puede estar desactualizado» | No presentar lo viejo como fresco |
| Tarjeta sin deuda: «pago atrasado · Debes $ 0» | No avisa | Es una alarma falsa |
| Presupuesto justo en 100 %: sin aviso | «Ya casi llega al límite» | Es un hueco de la web |
| «Te alcanza» puede perder un día | Cuenta exacta por calendario | Redondeo y cambio de hora |
| Promete «lo intentamos solos» | «No pudimos traer todos tus datos» y Reintentar | No hay reintento automático |
| Máscara siempre con `$` | Símbolo de la moneda | Cuentas en euros, reales y otras |
| Signo negativo con un solo formato | El de cada país (Chile, Ecuador, Paraguay, Venezuela, Suiza) | Paridad con Intl |

**Cambia por ser móvil:**

- Halar para recargar.
- Atrás de Android vuelve al Inicio desde otra pestaña.
- Con letra grande los montos pasan debajo y los totales se apilan.
- Horizontal respeta las zonas del sistema.
- Etiquetas de pestaña de 12 (la web usa 11).
- Mejor contraste en la tarjeta violeta.
- El tutorial recuerda por cuenta y no por dispositivo.

**Documentación frente al código:** los ocho documentos auditaron `698dc57`. `main` está en `dd0068a`,
pero esos commits no tocan el Inicio. La auditoría encontró diez afirmaciones de los documentos que no
coinciden con el código (por ejemplo, el ojo está en el encabezado y el aviso de pagos nunca sale en
el celular). En todas mandó el código.

---

## E. Integridad financiera

**Vienen del servidor y se muestran tal cual:** `ready`, `mode`, `money`, `pendingTotal`, `free`,
`shortfall`, `perDay`, `nextPay`, `pending`, totales del mes, consumo de presupuestos, deuda y días de
las tarjetas. La app **no** implementa «libre para gastar».

| Campo | Significado verificado | Opcional |
|---|---|---|
| `ready` | Se sabe cómo entra la plata y cuánta hay | No. Si es `false`, no viene nada más |
| `money` | Plata actual | Con plan, no. En el perfil puede ser `null` |
| `pendingTotal` | Apartado para compromisos sin pagar | No |
| `free` | `money − pendingTotal`. Puede ser negativo | No |
| `shortfall` | Lo que falta. Cero si alcanza | No |
| `mode` | `daily`, `goal` o `runway` | No |
| `perDay`, `nextPay` | Diario y próximo día de pago | Solo en `daily` |
| `pending` | Compromisos por fecha, con atrasados | Puede venir vacío |

**Calcula el frontend (presentación):**

| Cálculo | Regla |
|---|---|
| Te alcanza | `saldo × día ÷ gastado del mes`. Es una estimación, no una promesa |
| Línea | Días cubiertos ÷ días que faltan, de 0 a 1 |
| Quedan | `límite − consumido`, en centavos enteros |
| Aviso | Atrasada → excedido → vence en 3 días o menos → cerca del límite → próxima |

**Importes:** el servidor manda `NUMERIC(12,2)` como número JSON. Al leer se normaliza a centavos,
lo que quita residuos y el «-$ 0,00». No se suman importes en el cliente.

**Diferencias y limitaciones del backend, documentadas y sin tocar:**

1. El plan usa la fecha de Bogotá. El resumen usa la del teléfono. Cerca de medianoche pueden diferir.
2. El plan redondea a unidades: en dólares o euros pierde los centavos.
3. Sus umbrales (100.000, 500.000) están pensados en pesos.
4. El redondeo puede dar `free: 0` con `shortfall: 1`, o `perDay > 0` con `free: 0`.
5. En modo `goal` el Inicio dice «Libre para gastar» aunque haga falta ganar cada día (igual en la web).
6. La fecha del calendario `cardDates` no está en `openapi.yaml`.

**Ocultar montos:**

- Tapa todas las cifras de plata, también para el lector («Monto oculto»).
- Se lee antes de dibujar y se conserva al cerrar la app. Si no se puede leer, arranca oculto.
- Siguen visibles nombres, fechas, días que alcanza y el tono de la tarjeta, como en la web.
- **No es cifrado.**
- **No tapa la miniatura de apps recientes del sistema.**

---

## F. Estados implementados

| Estado | Qué se ve | Captura |
|---|---|---|
| A. Libre para gastar | Cifra, apartado, diario si aplica | [13](etapa-02/13-plan.jpg) |
| B. Te faltan | El faltante, nunca un negativo «gastable» | [15](etapa-02/15-faltan.jpg) |
| C. Negativo | Signo intacto y dos salidas | [16](etapa-02/16-negativo.jpg) |
| D. Sin plan | Saldo, ritmo y acceso a configurar | [17](etapa-02/17-sin-plan.jpg) |
| D. Sin bienvenida, con movimientos | Saldo e invitación | [18](etapa-02/18-movimientos.jpg) |
| E. Sin movimientos | Rin y una acción | [10](etapa-02/10-vacio.jpg) |
| F. Cargando | Un esqueleto, sin cifras | pruebas |
| F. Sin conexión, sin datos | «—», razón y Reintentar | [20](etapa-02/20-sin-conexion-frio.jpg) |
| F. Sin conexión, con datos anteriores | Marca de desactualizado, sin plan | [19](etapa-02/19-sin-conexion.jpg) |
| F. Falló el plan | Vuelve a Mi plata y avisa | [22](etapa-02/22-error-plan.jpg) |
| F. Falló el perfil | Plan vigente, marca y Reintentar | [24](etapa-02/24-error-saldo.jpg) |
| F. Sesión vencida | Va al login, sin aviso de error | pruebas |
| Montos ocultos | Ninguna cifra | [12](etapa-02/12-ocultos-reabrir.jpg) |

**Sin conexión:** no hay copia local financiera ni cola. Solo se conserva en memoria lo último de la
sesión, marcado. El modelo `Block` (valor, cargando, error) es el punto donde entrará una copia local.

---

## G. Navegación

**Funcionan:** Inicio, las cinco posiciones de la barra, «Responder» (preguntas), «Ahora no», ocultar
montos, reintentar, recargar, ver el tutorial y cerrar sesión.

**Muestran «En desarrollo», sin datos ni acciones falsas (los 14 comprobados por ruta en pruebas):**

| Destino | Ruta | Página web por portar |
|---|---|---|
| Movimientos | `/app/movimientos` | `Movements.jsx` |
| Planear | `/app/planear` | `Planear.jsx` |
| Yo | `/app/cuenta` | `Account.jsx` (aquí ya están tutorial y cerrar sesión) |
| Anotar | `/app/anotar?tipo=` | `Anotar.jsx` |
| Notificaciones | `/app/notificaciones` | `Notifications.jsx` |
| Mi plata | `/app/mi-plata` | `MiPlata.jsx` |
| Pagos del mes | `/app/mi-plata/pagos` | `MoneyPayments.jsx` |
| Corregir saldo | `/app/mi-plata/corregir` | `FixBalance.jsx` |
| Ingresos | `/app/ingresos` | `PeriodDetail.jsx` |
| Gastos | `/app/gastos` | `PeriodDetail.jsx` |
| Por confirmar | `/app/por-confirmar` | `PendingPayments.jsx` |
| Presupuestos | `/app/presupuestos` | `Budgets.jsx` |
| Tarjetas | `/app/tarjetas` | `Cards.jsx` |
| Tarjeta | `/app/tarjetas/:id` | `CardDetail.jsx` |

**Estos flujos no están terminados.** Todas las rutas exigen sesión.

---

## H. Rin y tutorial

- **Inicio:** Rin oficial solo en el estado vacío. Saluda una vez por apertura y queda quieto. No
  reacciona a montos, no tapa cifras y no está en el negativo.
- **Onboarding:** sigue en todos los pasos por la decisión del 21 de noviembre. La evaluación y la
  excepción propuesta están en [RIN_EN_MOBILE.md](RIN_EN_MOBILE.md). **Necesita tu aprobación.**
- **Movimiento reducido:** Rin quieto, sin transiciones.

**Tutorial:** los ocho pasos de la web sobre elementos reales. El de gráficos va centrado, como en la
web, porque en el celular no existe. Se cierra con Omitir, tocando fuera o con Atrás.

- En **demostración** se abre solo una vez.
- En **cuentas reales no se abre solo todavía** (`kCoachTourForRealAccounts = false`). Explica módulos
  «En desarrollo», y cerrarlo lo marcaría visto también en la web. Se enciende cuando existan.
- Siempre se puede abrir desde «Yo».
- Nunca dice que se guardó en el servidor.

---

## I. Internacionalización

- Español, inglés y portugués: 354 traducciones por idioma. El generador **falla si falta alguna**.
- Los 7 textos pendientes están traducidos, más uno que apareció («Ya agregaste {name}…»).
- «Cuota» → *Loan payment* / *Prestação*, solo en Flutter (`tool/l10n_mobile/`). La web no se tocó.
  Al portar Vacas habrá que separar esa clave: allá «Cuota» sí es *Share*.
- «millones», plurales, separadores, «¿Faltan ceros?» con el formato de la moneda, textos del lector.
- Meses y fechas por idioma y país («30 November», «November 30», «setiembre»).
- Montos con el formato de 72 países, también negativos, con paridad probada contra Intl.
- **Hasta que la cuenta diga otra cosa, los montos se muestran en pesos, como la web.** Antes se
  tomaba la moneda del país del teléfono y podía pintar pesos como dólares.

**Textos míos que conviene que apruebes:** «Activity» y «Extrato» para la pestaña Movimientos
(los nombres completos no cabían a 320), «En desarrollo» y su explicación, y los avisos de
desactualizado y de pagos en duda.

---

## J. Pruebas

`flutter analyze`: sin problemas. `flutter test`: **818 de 818**. Eran 288. La suite tarda unos 3 minutos por el modelo del guardado.

| Área | Pruebas |
|---|---|
| Inicio: reglas, contratos, pantalla, tutorial, demo, aislamiento | 388 |
| Onboarding | 231 |
| Núcleo: red, sesión, regiones, idiomas | 52 |
| Autenticación | 47 |
| Rin | 28 |
| Barra y pantallas pendientes | 24 |
| Rutas | 21 |
| Entrada | 20 |
| Bienvenida sin sesión | 7 |

Cuatro pruebas de la entrada probaban el Inicio provisional: se reescribieron con los mismos casos.
Las que codificaban un defecto corregido se actualizaron. No se quitó cobertura.

| Escenario pedido | Cómo se llega | Prueba | Emulador |
|---|---|---|---|
| 1. Cuenta nueva | Usuario nuevo | Sí | Sí |
| 2. Ingresos y gastos | Usuario con movimientos | Sí | Sí |
| 3. Plan listo | Plan listo | Sí | Sí |
| 4. Insuficiente | Te faltan | Sí | Sí |
| 5. Negativo | Estás en negativo | Sí | Sí |
| 6. Sin plan | Sin plan | Sí | Sí |
| 7. Error de API | Panel: falla en la próxima | Sí | Sí |
| 8. Sin conexión | Panel: conexión apagada | Sí | Sí |
| 9. Montos ocultos | Ojo del encabezado | Sí | Sí |
| 10. Regiones | Panel: CO, US, BR, ES, GB | Sí | Sí |

**Demostración y continuidad:** un solo estado por cuenta demo. Lo respondido en la bienvenida
(región, saldo, fuentes, pagos) es lo que muestra el Inicio. No se inventan ingresos ni se marcan
pagos como hechos. En el escenario «Usuario nuevo» el plan es una resta simple para que el recorrido
sea coherente. **No es el algoritmo del servidor y no corre en cuentas reales.** En otras monedas los
montos fijos del ejemplo se dividen entre 1.000.

### Revisiones adversariales

| Pasada | Encontró | Qué se hizo |
|---|---|---|
| 1 | 8 graves (4 causas), 14 medios, 27 leves. 3 refutados | Corregidos |
| 2, sobre las correcciones | 17 hallazgos sin repetir, 3 graves | Corregidos |
| 3 | 9, con 1 grave | Corregidos y se agregó el modelo del guardado |
| 4 | 8, ninguno grave | Corregidos |
| 5 | 1 medio y 6 leves | Medio y 2 leves corregidos, el resto documentado |

---

## K. Emulador

Android 16 (API 36), `Medium_Phone_API_36`, con la app real. Las 48 capturas están en
[`etapa-02/`](etapa-02/).

| Prueba | Resultado | Capturas |
|---|---|---|
| Demo → bienvenida → Inicio | 1.800.000, 900.000 apartados, 900.000 libres | 01 a 08 |
| Cerrar y reabrir | Mismo estado, montos ocultos conservados | 11, 12 |
| Tutorial completo | Ocho pasos | 07-1 a 07-8 |
| Pantalla mediana, claro y oscuro | Bien | 13 a 18, 25, 26 |
| 320 × 568 y letra al doble | Sin desbordes | 28 a 31 |
| Cifra de 10 dígitos | Cabe entera | 35, 36 |
| COP, USD, BRL, EUR, GBP; es, en, pt | Formato correcto | 27 |
| Fallas, sin conexión, recuperación | Bien | 19 a 24 |
| Horizontal | Bien, con desplazamiento | 32 |
| Pestañas, destinos y Atrás | Bien | 33, 34 |
| Guardado que falla, cerrar, retomar | Sin duplicar: mismo saldo y mismos pagos | 38 a 40 |
| Build *release* con `DEMO_MODE=true` | **Sin demostración**, y descarta la sesión demo guardada | 37 |

**No se pudo probar:**

- iOS: exige un Mac.
- TalkBack y VoiceOver: se probó la semántica, no un lector encendido.
- Teléfono físico, rendimiento medido y gesto predictivo de Atrás.
- Red real: la demostración no sale a la red.
- Cambio de día real: se probó con reloj simulado.

Las capturas 01 a 37 son de compilaciones del mismo día anteriores a las últimas correcciones del
guardado; las 38 a 40 y la suite completa corresponden al código final.

---

## L. Riesgos

### Pendiente de backend QA (bloqueado por la URL)

1. Los diez endpoints de la sección C con una cuenta de prueba: forma, nulos y decimales.
2. `POST /welcome` repetido idéntico sin duplicar pagos. Se leyó en el código y no se probó en vivo.
3. Que `commitments[].name` y `balance` basten para confirmar una etapa 1 sin respuesta.
4. Espera vencida con el servidor dormido (20 s para conectar, 45 s para responder).
5. Renovación del token con ocho peticiones a la vez.
6. `409 CURRENCY_LOCKED` y que el perfil traiga moneda e idioma.
7. Diferencia entre la fecha de Bogotá y la del teléfono.
8. `POST /money-profile/tutorial` antes de encender el tutorial en cuentas reales.

### Límites que solo arregla el backend (propuesta aparte, no implementada)

- **`POST /money-profile/welcome` necesita una llave de idempotencia.** Sin ella la app no puede saber
  con certeza si un envío sin respuesta llegó, ni impedir que uno viejo llegue tarde y pise el saldo
  nuevo. Es el cambio de backend más importante antes de publicar.
- Quitar un saldo ya guardado no lo borra: el servidor lee «sin saldo» como «no respondió».

### Pendiente de iOS

Compilar con Xcode, Keychain (sobrevive a desinstalar), VoiceOver, áreas seguras, gesto de volver,
teclado, íconos de la app (siguen los de Flutter) y diálogos en los tres idiomas.

### Decisiones tuyas

| Decisión | Recomendación |
|---|---|
| Rin en la bienvenida | Volver a tres apariciones: saludo, ingresos y final |
| Miniatura de apps recientes muestra montos | Protegerla antes de publicar. `FLAG_SECURE` también impide capturas, por eso no lo activé |
| Pagos bloqueados tras una espera vencida | Mantenerlo: evita duplicar plata apartada |
| «Todavía no has anotado nada este mes» sale solo si nunca anotó | Cambiar el texto en web y app |
| Huecos de la web de la sección D | Corregirlos allá, en un PR aparte |

### Límites conocidos

- En pantallas de menos de 480 de alto el aviso de error se desplaza con la lista.
- «Movimientos» en español se ve a 9 px en 320 de ancho.
- Las builds *profile* sí permiten demostración: **no se publican**.
- «Cerrar sesión desde el saludo» y «moneda inicial en pesos» no tienen prueba propia.
- Tras una lectura fallida del llavero, lo escrito en esa sesión no se guarda en borrador (no pisa el
  que no se pudo leer). Solo se guarda al enviar.
- Un 500 al guardar fuentes cuenta como «pudo llegar»: si luego las quita todas, se borran también
  en el servidor.
- El aviso de saldo distinto dice que «Seguir» lo reemplaza. Si escribe el mismo que ya se había
  confirmado, no se reenvía y queda el del servidor.
- Guardar con saldo necesita leer antes el perfil: si esa lectura falla, no se envía y se reintenta.

---

## M. Archivos

### Creados

- `lib/features/home/`: 23 archivos (datos 3, dominio 4, aplicación 2, presentación 14).
- `lib/features/shell/presentation/`: `rinde_tab_scaffold.dart`, `pending_module_screen.dart`.
- `lib/app/pending_modules.dart` y `lib/design/widgets/rinde_skeleton.dart`.
- `assets/icons/`: `bell`, `calendar-range`, `chevron-right`, `construction`, `house`, `inbox`,
  `list`, `user-round` (Lucide).
- `tool/l10n_mobile/`: `en.json`, `pt.json`.
- `test/app/`: `icon_assets_test`, `router_test`.
- `test/core/`: `l10n_test`, `session_storage_test`.
- `test/features/home/`: `account_isolation`, `coach_tour`, `demo_home_repository`, `home_dates`,
  `home_models`, `home_notice`, `home_providers`, `home_repository`, `home_screen`, `home_view`,
  `runway`, `tour_controller`.
- `test/features/onboarding/`: `demo_panel_test`, `save_model_test`. También `test/features/shell/` (2 archivos).
- `test/support/`: `fake_home_repository`, `home_fixtures`.
- `docs/`: este informe, `RIN_EN_MOBILE.md` y 48 capturas.

### Modificados

- `lib/app/`: `app`, `router`, `routes`. También `lib/main.dart`.
- `lib/core/`: `i18n/tr`, `network/api_client`, `network/api_exception`, `region/region`,
  `region/region_data.g`, `storage/session_storage`.
- `lib/design/`: `tokens/rinde_typography` y los widgets `icon`, `line`, `money_field`, `segmented`,
  `text_field`.
- `lib/features/auth/`: `session_controller`, `auth_validators`, las 3 pantallas y 5 widgets.
- `lib/features/entry/`: `boot_screen`, `entry_screen`.
- `lib/features/onboarding/`: `onboarding_controller`, los 3 de datos, `commitments`,
  `onboarding_draft`, `demo_panel`, `money_invite`, `onboarding_screen`, pasos `balance`, `hello`,
  `payments`, y `onboarding_shell`.
- `lib/features/welcome/presentation/welcome_screen`.
- `assets/l10n/en.json`, `pt.json` (generados), `ios/Runner/Info.plist`, `README.md`.
- `tool/export_l10n.mjs`, `tool/export_region.mjs`.
- Pruebas existentes: `api_client`, `region` y sus ejemplos, `entry_screen`, `balance_payments`,
  `controller`, `draft`, `hello_country`, `repository`, `welcome_screen`.

Ningún archivo eliminado.

---

## N. Git y seguridad

- `rinde`: rama `main`, último commit `38f99e4`. **Sin commits ni push en esta etapa.**
  `git status` muestra los cambios de la sección M, pendientes de revisión.
- `gitleaks` sobre lo publicable: sin secretos.
- Sin URL de QA, `.env`, llaves ni APK entre lo publicable. Los correos de las pruebas son ficticios.
- Las capturas solo tienen datos sintéticos. El repositorio es público: revísalas antes de subir.
- Rinde Web: 0 archivos con seguimiento modificados. No se cambió de rama, no se tocó el backend ni
  bases de datos, no se desplegó y no se usó producción.

---

## O. Siguiente módulo recomendado (no implementado)

1. **Primero, una pasada contra QA.** Es poco trabajo y quita el riesgo mayor. Pedir la URL y una
   cuenta de prueba es lo que más desbloquea.
2. **Después, Anotar y la lista de Movimientos, juntos.**
   - Es la única forma de que entre información a la app: hoy el Inicio solo lee.
   - La acción principal del estado vacío y el botón central llevan ahí.
   - Anotar sin ver lo anotado no se puede verificar, por eso van juntos.
   - Obliga a decidir temprano la integridad sin conexión (no duplicar un gasto), base de lo demás.
   - Acerca el momento de encender el tutorial en cuentas reales.
3. **Luego Mi plata**, que explica «¿De dónde sale?» y permite corregir el saldo.
