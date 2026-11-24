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

## Validaciones pendientes para la estabilización

- Suite completa tras cada fase posterior a 5C.
- 5C: emulador y capturas del aviso «Otra ••1234»; revisión independiente (se omitió por la directiva).
- App contra la API de QA con la cuenta sintética (tarjetas y cuentas).
- iOS (no hay Mac), teléfono real, TalkBack/VoiceOver.
- 6: eliminar cuenta contra QA (y respuesta perdida), «Abrir WhatsApp» en Android/iOS, tema sin destello en compilación real, «Apariencia» y la hoja de eliminar con letra grande y teclado.

## Bloqueos y decisiones abiertas (de David)

- PR #2 sin fusionar. Textos nuevos de 5A y 5B sin aprobar; 6 decisiones del 5B y la pregunta 5 (etiqueta de la tarjeta) tomadas con la recomendación del plan.
- Backend: B1/B2 (idempotencia de pagos de tarjeta y abonos) y B4 sin aprobar.
- Traducciones de la web que se leen mal en inglés: «Paid {v1}», «Delete account», «· share», «the».
- 6: DECIDIDO por David (24-nov): al cerrar sesión la cola sin conexión se queda en el teléfono, aparte por cuenta, como la web. Textos nuevos de la 6 sin aprobar.
- Rama 6 sale de la rama 5 (PR #2 sin fusionar): su PR va contra la rama de la etapa 5.
