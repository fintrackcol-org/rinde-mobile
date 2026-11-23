import '../../../../core/i18n/tr.dart';
import '../tour_anchors.dart';

/// Tramos del tutorial: el recorrido corto (lo esencial), la pregunta de si ver lo demás, y el
/// largo (lo menos visible).
enum TourSection { corto, pregunta, largo }

class CoachStep {
  const CoachStep(this.section, this.target, this.title, this.text);

  final TourSection section;

  /// Lo que se resalta. null = nada: la tarjeta sale en el centro y el paso se explica igual.
  final TourTarget? target;
  final String title;
  final String text;
}

/// Los 8 pasos de TOUR_STEPS (CoachTour.jsx de Rinde Web), con los mismos textos, en el idioma de [t].
List<CoachStep> coachSteps(Tr t) => [
  CoachStep(
    TourSection.corto,
    TourTarget.saldo,
    t('Esto es lo que te queda'),
    t(
      'La cifra grande es tu plata del mes. La línea muestra hasta qué día te alcanza, y la moneda verde es donde llega.',
    ),
  ),
  CoachStep(
    TourSection.corto,
    TourTarget.anotar,
    t('Anota en dos toques'),
    t(
      'Pon cuánto fue y en qué, o dilo con el micrófono: «taxi 9 mil» llena las dos casillas y la IA elige la categoría. También puedes anotar por WhatsApp.',
    ),
  ),
  CoachStep(
    TourSection.corto,
    TourTarget.totales,
    t('Ingresos y Gastos se tocan'),
    t('Ábrelos para ver en qué se fue cada peso y cuánto te entró este mes.'),
  ),
  // En la web resalta «graficos», que solo existe en el Inicio de computador: en celular la web
  // también lo explica con la tarjeta en el centro.
  CoachStep(
    TourSection.corto,
    null,
    t('En qué gastas y cómo van tus topes'),
    t(
      'Toca Gastos para ver en qué se fue cada peso; tus topes están en Planear › Presupuestos. Si uno pasa del 90 %, se pone rojo.',
    ),
  ),
  CoachStep(
    TourSection.corto,
    TourTarget.planear,
    t('Lo que viene, en Planear'),
    t(
      'Pagos fijos, calendario, presupuestos, metas, deudas y tarjetas. Ponle fecha a una meta y Rinde te dice cuánto apartar.',
    ),
  ),
  CoachStep(
    TourSection.pregunta,
    null,
    t('¿Quieres ver lo demás?'),
    t('Toca tu saldo para ver Mi plata: por confirmar, consejos de la IA, renta y tus próximos días.'),
  ),
  CoachStep(
    TourSection.largo,
    TourTarget.saldo,
    t('Mi plata reúne lo demás'),
    t(
      'Tu saldo, por confirmar, consejos, renta y lo que entra y sale en los próximos días. Todo a un toque.',
    ),
  ),
  CoachStep(
    TourSection.largo,
    TourTarget.cuenta,
    t('Yo: tu cuenta'),
    t('Conecta WhatsApp, elige tus avisos, cambia a modo oscuro o repite este tutorial cuando quieras.'),
  ),
];
