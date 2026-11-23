import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Íconos de lucide, la misma librería de Rinde Web (licencia ISC en assets/icons/).
/// Se agregan como SVG a medida que una pantalla los necesita.
enum RindeIcons {
  arrowLeft('arrow-left'),
  arrowRight('arrow-right'),
  bell('bell'),
  bike('bike'),
  briefcaseBusiness('briefcase-business'),
  calendarDays('calendar-days'),
  calendarRange('calendar-range'),
  chevronDown('chevron-down'),
  chevronLeft('chevron-left'),
  chevronRight('chevron-right'),
  check('check'),

  /// Check con trazo 3: casilla y reglas de contraseña (strokeWidth 3 en la web).
  checkBold('check-bold'),
  circleAlert('circle-alert'),

  /// Módulo en desarrollo.
  construction('construction'),
  creditCard('credit-card'),
  download('download'),
  eye('eye'),
  eyeOff('eye-off'),
  gift('gift'),
  handCoins('hand-coins'),
  house('house'),
  inbox('inbox'),
  keyRound('key-round'),
  landmark('landmark'),
  list('list'),
  loader('loader-circle'),
  logOut('log-out'),
  mail('mail'),
  mailCheck('mail-check'),
  mic('mic'),
  pencil('pencil'),
  plus('plus'),
  rotateCcw('rotate-ccw'),

  /// Ajuste de saldo: no es ingreso ni gasto.
  scale('scale'),
  search('search'),
  shieldAlert('shield-alert'),
  sparkles('sparkles'),
  target('target'),
  trendingUp('trending-up'),
  userRound('user-round'),
  users('users'),
  wallet('wallet'),
  wifiOff('wifi-off'),
  x('x');

  const RindeIcons(this.file);
  final String file;
  String get asset => 'assets/icons/$file.svg';
}

class RindeIcon extends StatelessWidget {
  const RindeIcon(this.icon, {super.key, this.size = 20, this.color, this.semanticLabel});

  final RindeIcons icon;
  final double size;

  /// Por defecto, el color del texto que lo rodea.
  final Color? color;

  /// Solo para íconos que comunican algo por sí solos; los decorativos se ocultan al lector.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return SvgPicture.asset(
      icon.asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
