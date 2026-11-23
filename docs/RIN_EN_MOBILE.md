# Rin en Rinde Mobile

Propuesta de excepción para la app móvil. **No cambia el manual visual de Rinde Web**
(`fintrack/docs/manual-visual.md`), que sigue siendo el documento oficial de marca.

Estado: **decidido el 22 de noviembre de 2026: opción B**, aplicada en el código de Rinde Mobile.

## Decisión vigente (opción B)

- **Bienvenida:** Rin aparece solo en el **saludo**, en la nota de **ingresos** y en la **celebración
  final**. No aparece en País, en las cinco escenas de «Cómo funciona», en Saldo ni en Pagos. Las notas
  de Saldo y Pagos se conservan sin el dibujo.
- **Inicio:** solo en el estado vacío.
- **Siempre:** dibujo oficial, gesto breve y quieto con «reducir movimiento».
- El manual visual de Rinde Web no se modificó: esta decisión vale para Rinde Mobile.
- Pruebas que la fijan: `tour_test`, `hello_country_test` y `balance_payments_test`.

El resto de este documento es la evaluación que llevó a la decisión.

## Qué dice el manual

Sección 12 (Bienvenida): «Rin aparece dos veces y no más: saluda en la pantalla 0 y explica por qué
se pregunta por los ingresos. No da puntos ni premios, no interrumpe y no se repite en cada pantalla.
Se usa el dibujo oficial, sin versiones nuevas.»

La web cumple: Rin sale en el cierre de la landing, en el saludo de la bienvenida y en la nota de
ingresos. Dentro de la app (Inicio y demás) hoy no hay Rin en la versión aprobada.

## Qué hace la app móvil hoy

El 21 de noviembre de 2026 se decidió «Rin en todos los pasos» de la bienvenida. Eso da ocho
apariciones en lugar de dos:

| Dónde | Tamaño | Qué hace | Coincide con la web |
|---|---|---|---|
| Entrada sin sesión | grande | saluda una vez | sí (cierre de la landing) |
| Saludo (paso 0) | grande | saluda una vez | sí |
| País, idioma y moneda | 44 × 50 | asiente al elegir país | no |
| «Cómo funciona» (5 escenas) | 32 de alto | quieto; asiente en la última | no |
| Ingresos | 40 × 44, dentro de una nota | se alegra al marcar una fuente | sí |
| Saldo | 40 × 44, dentro de una nota | pensativo, quieto | no |
| Pagos | 40 × 44, dentro de una nota | curioso; un gesto al agregar | no |
| Final («¡Listo!») | grande | celebra una vez | no (la web no tiene pantalla final) |

En todas se usa el dibujo oficial (`lib/features/rin/`, portado de `Rin.jsx`), sin versiones nuevas.

## Evaluación

**Dónde aporta.** El saludo, la nota de ingresos (explica por qué se pregunta algo personal) y el
final. Son los tres momentos con carga emocional: llegar, confiar un dato y terminar.

**Dónde aporta poco.** País, las cinco escenas y Saldo. Ahí Rin no explica nada que el texto no diga:
acompaña. No estorba, pero tampoco suma.

**¿Compite con los formularios?** No. En los pasos con campos, Rin mide 40 × 44 y va dentro de una
nota arriba del formulario; nunca queda sobre un campo, un botón ni el teclado. En pantallas de 320 de
ancho y con la letra al doble no desplaza controles (probado en la etapa anterior).

**¿Distrae el movimiento?** Poco, con un matiz. Los gestos (saludar, asentir, alegrarse) ocurren una
sola vez y responden a algo que hizo la persona. Pero Rin también «respira» y parpadea todo el tiempo
(ciclos de 3,8 s y 6,4 s), y eso sí es movimiento constante junto a un formulario. Es muy leve (escala
de 0,6 % a 1,6 %), aunque en ocho pantallas seguidas se nota más que en dos.

**Accesibilidad.** Rin es decorativo para el lector de pantalla salvo en el saludo, donde se anuncia
una vez. Con «reducir movimiento» activo en el teléfono queda completamente quieto. No comunica nada
solo con el dibujo: todo lo que «dice» está en texto.

**Minimalismo.** Se conserva en cada pantalla por separado. Lo que se pierde es el efecto de las dos
apariciones: cuando Rin está en todas partes deja de ser un momento especial.

## Excepción propuesta para Mobile

1. **Bienvenida:** Rin puede acompañar todos los pasos, con estas condiciones.
   - Grande solo en el saludo y en el final.
   - En los demás pasos, como máximo 44 × 50, fuera del área de campos y botones.
   - Un gesto como máximo por acción de la persona; nunca gestos automáticos en bucle.
   - En los pasos con teclado (Saldo y Pagos) Rin queda quieto: sin respirar ni parpadear.
     *Esto último todavía no está hecho; se haría si se aprueba la excepción.*
2. **Inicio:** Rin aparece **solo en el estado vacío** (cuenta sin movimientos), saluda una vez y
   queda quieto. No aparece sobre las tarjetas de plata, no tapa cifras y no reacciona a los montos:
   nunca celebra ni se entristece por un saldo.
3. **Tutorial del Inicio y pantallas «En desarrollo»:** sin Rin.
4. **Siempre:** dibujo oficial, respeto a «reducir movimiento», y nada de puntos, premios ni mensajes
   que interrumpan.

## Decisión que falta

Es una decisión de marca y le corresponde a quien dirige la identidad de Rinde:

- **Opción A: aprobar la excepción.** Se anota en el manual visual que en Mobile Rin acompaña la
  bienvenida completa con las condiciones de arriba. Queda por hacer el punto de «quieto con teclado».
- **Opción B: volver a la regla del manual.** Rin queda en el saludo, en Ingresos y en el final, y
  se quita de País, las escenas, Saldo y Pagos. Es un cambio pequeño en cuatro archivos.

Recomendación: **opción B con el final incluido** (tres apariciones). Mantiene lo que hace especial a
Rin y deja la bienvenida igual de clara. Mientras no se decida, el código sigue con «todos los pasos»,
que fue la última instrucción recibida.
