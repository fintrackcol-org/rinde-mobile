# Seguimiento de fases (Rinde Mobile)

Registro único y compacto desde el 24-nov-2026 (directiva de optimización): cada fase implementa y
hace comprobaciones mínimas; las validaciones completas se hacen en la **fase final de
estabilización**. Detalle de etapas anteriores: `docs/ETAPA_0X_*.md`.

Niveles: **implementado** (código hecho) · **validado parcial** (comprobaciones mínimas) ·
**validado integral** (suite, emulador, revisión; antes de producción).

| Fase | Funcionalidad | Estado | Comprobaciones hechas | Commit |
|---|---|---|---|---|
| 5A | Tarjetas, y tarjeta + cuotas en Movimientos | Validado integral (ciclo largo) | Suite 1342, 2 rondas de revisión, emulador | `c5ef34b` |
| 5B | Cuentas (deudas) | Validado integral (ciclo largo) | Suite 1466, 2 rondas de revisión, emulador | `7188331` |
| 5C | Integración: aviso del Inicio con la etiqueta común de la tarjeta («Otra ••1234»); pruebas de integración tarjeta, cuenta y A/B | Validado parcial | analyze, formato, pruebas del Inicio y de integración (95 en verde), gitleaks | ver git log |
| 6 | «Yo» (Tu cuenta): eliminar cuenta (borra todo lo local), cerrar sesión, perfil, país, idioma, tema guardado, «Pago de tarjetas», categorías, WhatsApp, tutorial. Fuera: instalar PWA, atajo Apple Pay, avisos push | Validado parcial | analyze, formato, 145 pruebas de lo tocado (18 nuevas), gitleaks | ver git log |
| 7 | Planear: pestaña con accesos, Presupuestos (lista, detalle, crear/editar/borrar), Calendario (pagos fijos, tarjetas, cuentas, cobros) y Próximos días (proyección del servidor). Fuera: Metas y Vacas (siguen «En desarrollo») | Validado parcial | analyze, formato, 578 pruebas de plan, inicio, movimientos y demo; gitleaks | ver git log |
| 8 | Ingresos y Gastos del periodo (total, tabla, por categoría, Kakeibo, lista) y Por confirmar (confirmar con categoría, descartar; un envío a la vez y duda resuelta releyendo). Fuera: salto directo de periodo, «Conectar mi iPhone» | Validado parcial | analyze, formato, 19 pruebas nuevas + 823 de movimientos/inicio/shell/money + router y l10n; gitleaks | ver git log |
| 9 | Notificaciones (bandeja), Consejos (IA del servidor, reflexión Kakeibo, chat), Exportar (vista previa del servidor + archivo a la hoja de compartir, dependencia `share_plus`) y Renta y DIAN. Fuera: «Salud financiera / Tu mes en números», tarjetas sin historial, maquetas de formatos de Exportar | Validado parcial | analyze, formato, 151 pruebas de lo tocado (14 nuevas), my_money_screen, gitleaks, APK de depuración compila | ver git log |
| 10 | Metas (colchón, metas, apartar plata) y Vacas (lista, crear, detalle, aportar, invitar, miembros, unirse con código). Se quitó el mecanismo «En desarrollo»: ya no queda ningún módulo pendiente. Fuera: cola sin conexión de aportes, refresco cada 15 s, pestaña Calendario de la vaca, Negocios, enlaces profundos | Validado parcial | analyze, formato, 194 pruebas de lo tocado (15 nuevas, aportes sin duplicar con `localId`), router y cuenta, gitleaks | ver git log |
| Estab. 1 | Revisión aplazada de 5C a 10 (5 revisores + corrector): 15 hallazgos, 14 corregidos con prueba y 1 mitigado (chat del asistente; el arreglo de fondo es del backend). Emulador: 14 capturas en `docs/estabilizacion/` y 1 error más corregido (la demo mostraba «Falta API_BASE_URL» en Consejos) | Validado integral en Android/demo | Suite completa 1569 en verde (0 fallas), analyze, formato, gitleaks en lib/test/docs/tool, APK de depuración | ver git log |
| Estab. 2 | App contra la API de QA con la cuenta sintética (David inició sesión): tarjeta (abonar con doble toque = 1 pago, borrar pago), cuenta (crear, abonar y saldar con doble toque = 1 abono y 1 ingreso por lo que faltaba), presupuesto (crear, gastado del servidor, borrar), vaca (crear, aportar con doble toque = 1 aporte, consejo de IA, borrar). Datos de prueba borrados después. 3 arreglos de UI encontrados ahí | Validado contra QA (Android) | Recorrido real + prueba nueva del aviso viejo; Planear y Vacas 36 en verde; analyze | ver git log |

## Validaciones pendientes para la estabilización

Hecho en la estabilización 1 (25-nov-2026): suite completa, revisión de código de 5C a 10, recorrido de todas las pantallas nuevas en el emulador (demo). **Siguen pendientes:** iOS, teléfono real, TalkBack/VoiceOver, rendimiento y enlaces que abran la app.


- Suite completa tras cada fase posterior a 5C.
- 5C: emulador y capturas del aviso «Otra ••1234»; revisión independiente (se omitió por la directiva).
- App contra la API de QA con la cuenta sintética (tarjetas y cuentas).
- iOS (no hay Mac), teléfono real, TalkBack/VoiceOver.
- 10: contra el backend real crear, unirse con código, aportar (ver el gasto en Movimientos y Mi plata), salirse, eliminar y pasar a Metas; en dispositivo el código en mayúsculas, copiar/compartir, lector y tema oscuro del detalle.
- 9: abrir .xlsx/.pdf/.csv desde la hoja de compartir en Android e iPhone (iPad: hoja junto al botón); consejos, reflexión y límite del chat con datos reales; pantallas nuevas a 320 px con letra al doble y en oscuro.
- 8: ver en dispositivo Inicio → Ingresos/Gastos → Por confirmar (claro, oscuro, montos ocultos); confirmar un pago real contra el backend.
- 7: emulador con letra grande y dos temas; presupuesto contra el servidor (crear, editar, borrar, 409 BUDGET_EXISTS); calendario con tarjetas, cuentas y vacas; gráfica de Próximos días sin ejes ni cifras (dibujo propio); calendario de la demo sin tarjeta ni cuentas.
- 6: eliminar cuenta contra QA (y respuesta perdida), «Abrir WhatsApp» en Android/iOS, tema sin destello en compilación real, «Apariencia» y la hoja de eliminar con letra grande y teclado.

## Bloqueos y decisiones abiertas (de David)

- PR #2 sin fusionar. Textos nuevos de 5A y 5B sin aprobar; 6 decisiones del 5B y la pregunta 5 (etiqueta de la tarjeta) tomadas con la recomendación del plan.
- Backend: B1/B2 (idempotencia de pagos de tarjeta y abonos) y B4 sin aprobar.
- Traducciones de la web que se leen mal en inglés: «Paid {v1}», «Delete account», «· share», «the».
- 6: DECIDIDO por David (24-nov): al cerrar sesión la cola sin conexión se queda en el teléfono, aparte por cuenta, como la web. Textos nuevos de la 6 sin aprobar.
- Rama 6 sale de la rama 5 (PR #2 sin fusionar): su PR va contra la rama de la etapa 5.
- 7: iniciales de los días (L M M J V S D) en español aunque la app esté en inglés o portugués, como la web; en Mi plata los presupuestos llevan a la lista y no al detalle. Textos nuevos de la 7 sin aprobar.
- 8: **riesgo de doble conteo abierto (backend):** confirmar en «Por confirmar» un gasto pagado con tarjeta de crédito resta de Mi plata y otra vez al pagar la tarjeta; `POST /pending-payments/:id/confirm` no acepta tarjeta. Propuesta: aceptar `credit_card_id`. Web: el Kakeibo de Ingresos/Gastos pide pageSize 200 (el servidor acepta 100) y siempre falla.
- 9: ¿se portan «Salud financiera / Tu mes en números» (~550 líneas en la web) y las tarjetas de Consejos sin historial (la web las calcula en el navegador)? Dependencia nueva `share_plus` por aprobar. Quedan «En desarrollo» solo Metas y Vacas.
- 10: enlaces de invitación que abran la app (deep links / App Links); ¿cola sin conexión de aportes, refresco cada 15 s, pestaña Calendario de la vaca y Negocios?; ¿encender el tutorial para cuentas reales (`kCoachTourForRealAccounts`)? La demo de Metas y Vacas solo lee (en todos los escenarios).
- Estab.: backend debería aplicar el tope de 500 caracteres del chat solo a los mensajes de la persona (`parseChat`); la web tiene el mismo fallo. Demo: en Ingresos/Gastos el resumen sale de cifras fijas y la lista de lo anotado (limitación de la demo, no de cuentas reales). Dependencia `path_provider` agregada como directa (ya venía con `share_plus`).
- Estab. 2: en compilaciones de QA pasar `--dart-define=WEB_URL=https://qa.rindecol.online`; sin eso, el enlace de invitación de las vacas apunta a la web de producción. En QA queda la cuenta saldada «Prueba QA 2» (sintética). Mi plata de la cuenta QA sale «—» porque nunca se dijo el saldo y sus movimientos dan negativo (igual que la web); en cuentas reales «Corregir saldo» sigue de solo lectura hasta la propuesta de versión del perfil.
