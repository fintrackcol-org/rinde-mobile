/// Modelos de Metas y Vacas con el contrato de `/api/v1/vacas` de Rinde Web (vacaService.js). Una meta
/// es una vaca `personal` de una sola persona. ESTRICTOS, como Tarjetas y Cuentas: una vaca ilegible
/// falla el bloque entero. Cuotas, estados, porcentajes y la proyección los calcula SIEMPRE el
/// servidor; aquí solo se leen.
library;

import '../../auth/data/auth_models.dart' show ContractException;
import '../../home/data/home_models.dart' show readList, readMap, readMoney;

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}');

String? _date(Object? raw, String key) {
  if (raw == null) return null;
  if (raw is String && _isoDate.hasMatch(raw)) return raw.substring(0, 10);
  throw ContractException('"$key" no es una fecha AAAA-MM-DD');
}

String? _text(Object? raw) => raw is String ? raw : null;

String _string(Map<String, dynamic> json, String key) =>
    json[key] is String ? json[key] as String : (throw ContractException('Falta "$key"'));

num _money(Map<String, dynamic> json, String key) =>
    readMoney(json[key]) ?? (throw ContractException('Falta "$key" o no es un número'));

/// `cumplido`, `al_dia`, `atrasado` o `pendiente` (MEMBER_STATUS de vacaFormat.js).
enum MemberStatus {
  done('cumplido'),
  onTime('al_dia'),
  late('atrasado'),
  pending('pendiente');

  const MemberStatus(this.wire);
  final String wire;

  static MemberStatus read(Object? raw) =>
      values.where((s) => s.wire == raw).firstOrNull ?? (throw ContractException('Estado de miembro: $raw'));
}

/// `activa`, `completada` o `vencida`.
enum VacaStatus {
  active('activa'),
  completed('completada'),
  expired('vencida');

  const VacaStatus(this.wire);
  final String wire;

  static VacaStatus read(Object? raw) =>
      values.where((s) => s.wire == raw).firstOrNull ?? (throw ContractException('Estado de vaca: $raw'));
}

/// La proyección del servidor (buildProjection de vacas.service.js).
class VacaProjection {
  const VacaProjection({
    required this.remaining,
    required this.averagePerDay,
    this.estimatedDate,
    this.daysLeft,
    this.neededPerWeek,
    this.onTrack,
  });

  factory VacaProjection.fromJson(Object? data) {
    final json = readMap(data);
    return VacaProjection(
      remaining: _money(json, 'remaining'),
      averagePerDay: _money(json, 'averagePerDay'),
      estimatedDate: _date(json['estimatedDate'], 'estimatedDate'),
      daysLeft: json['daysLeft'] is int ? json['daysLeft'] as int : null,
      neededPerWeek: readMoney(json['neededPerWeek']),
      onTrack: json['onTrack'] is bool ? json['onTrack'] as bool : null,
    );
  }

  final num remaining;
  final num averagePerDay;
  final String? estimatedDate;

  /// Negativo si ya pasó la fecha límite; null sin fecha.
  final int? daysLeft;
  final num? neededPerWeek;

  /// null sin fecha límite.
  final bool? onTrack;
}

class VacaMember {
  const VacaMember({
    required this.userId,
    required this.name,
    required this.isMe,
    required this.admin,
    required this.quota,
    required this.contributed,
    required this.remaining,
    required this.percentage,
    required this.status,
    this.customQuota,
  });

  factory VacaMember.fromJson(Object? data) {
    final json = readMap(data);
    return VacaMember(
      userId: _string(json, 'userId'),
      name: _string(json, 'name'),
      isMe: json['isMe'] == true,
      admin: json['role'] == 'admin',
      quota: _money(json, 'quota'),
      customQuota: readMoney(json['customQuota']),
      contributed: _money(json, 'contributed'),
      remaining: _money(json, 'remaining'),
      percentage: _money(json, 'percentage'),
      status: MemberStatus.read(json['status']),
    );
  }

  final String userId;

  /// Nombre visible (nunca el correo completo).
  final String name;
  final bool isMe;
  final bool admin;
  final num quota;

  /// La puesta por un administrador (reparto a medida); null = la calculada.
  final num? customQuota;
  final num contributed;
  final num remaining;
  final num percentage;
  final MemberStatus status;
}

class VacaContribution {
  const VacaContribution({
    required this.id,
    required this.name,
    required this.isMe,
    required this.amount,
    required this.date,
    this.note,
  });

  factory VacaContribution.fromJson(Object? data) {
    final json = readMap(data);
    return VacaContribution(
      id: _string(json, 'id'),
      name: _text(json['name']) ?? '',
      isMe: json['isMe'] == true,
      amount: _money(json, 'amount'),
      note: _text(json['note']),
      date: _date(json['date'], 'date') ?? (throw const ContractException('Falta "date"')),
    );
  }

  final String id;
  final String name;
  final bool isMe;
  final num amount;
  final String? note;
  final String date;
}

class VacaInvitation {
  const VacaInvitation({required this.email, required this.sentAt});

  final String email;

  /// AAAA-MM-DD.
  final String sentAt;
}

/// Una vaca (o meta) de la lista o del detalle. [members], [contributions] e [invitations] solo
/// llegan en el detalle; las invitaciones, solo a los administradores.
class Vaca {
  const Vaca({
    required this.id,
    required this.name,
    required this.goal,
    required this.split,
    required this.personal,
    required this.admin,
    required this.total,
    required this.percentage,
    required this.status,
    required this.membersCount,
    required this.myQuota,
    required this.myContributed,
    required this.myRemaining,
    required this.myStatus,
    required this.projection,
    this.description,
    this.deadline,
    this.code,
    this.members = const [],
    this.contributions = const [],
    this.invitations = const [],
  });

  factory Vaca.fromJson(Object? data) {
    final json = readMap(data);
    return Vaca(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      description: _text(json['description']),
      goal: _money(json, 'goal'),
      deadline: _date(json['deadline'], 'deadline'),
      split: json['split'] == 'personalizado' ? 'personalizado' : 'igual',
      code: _text(json['code']),
      personal: json['personal'] == true,
      admin: json['role'] == 'admin',
      total: _money(json, 'total'),
      percentage: _money(json, 'percentage'),
      status: VacaStatus.read(json['status']),
      membersCount: json['membersCount'] is int
          ? json['membersCount'] as int
          : (throw const ContractException('Falta "membersCount"')),
      myQuota: _money(json, 'myQuota'),
      myContributed: _money(json, 'myContributed'),
      myRemaining: _money(json, 'myRemaining'),
      myStatus: MemberStatus.read(json['myStatus']),
      projection: VacaProjection.fromJson(json['projection']),
      members: [for (final m in readList(json['members'] ?? const [])) VacaMember.fromJson(m)],
      contributions: [
        for (final c in readList(json['contributions'] ?? const [])) VacaContribution.fromJson(c),
      ],
      invitations: [
        for (final raw in readList(json['invitations'] ?? const []))
          if (raw is Map && raw['email'] is String)
            VacaInvitation(email: raw['email'] as String, sentAt: _date(raw['sentAt'], 'sentAt') ?? ''),
      ],
    );
  }

  final String id;
  final String name;
  final String? description;
  final num goal;
  final String? deadline;

  /// `igual` o `personalizado`.
  final String split;

  /// Código de invitación; null en una meta personal.
  final String? code;
  final bool personal;

  /// Quien mira es administrador (el servidor decide quién edita, borra o saca miembros).
  final bool admin;
  final num total;
  final num percentage;
  final VacaStatus status;
  final int membersCount;
  final num myQuota;
  final num myContributed;
  final num myRemaining;
  final MemberStatus myStatus;
  final VacaProjection projection;
  final List<VacaMember> members;
  final List<VacaContribution> contributions;
  final List<VacaInvitation> invitations;
}

/// Lo que muestra un código de invitación antes de unirse (GET /vacas/invitations/:code).
class InvitationPreview {
  const InvitationPreview({
    required this.id,
    required this.name,
    required this.goal,
    required this.total,
    required this.membersCount,
    required this.isMember,
    this.description,
    this.deadline,
    this.createdBy,
  });

  factory InvitationPreview.fromJson(Object? data) {
    final json = readMap(data);
    return InvitationPreview(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      description: _text(json['description']),
      goal: _money(json, 'goal'),
      total: _money(json, 'total'),
      deadline: _date(json['deadline'], 'deadline'),
      membersCount: json['membersCount'] is int ? json['membersCount'] as int : 0,
      createdBy: _text(json['createdBy']),
      isMember: json['isMember'] == true,
    );
  }

  final String id;
  final String name;
  final String? description;
  final num goal;
  final num total;
  final String? deadline;
  final int membersCount;
  final String? createdBy;
  final bool isMember;
}

/// GET /vacas/:id/advice: el consejo de la IA (con totales, sin nombres) o el de reglas.
class VacaAdvice {
  const VacaAdvice({required this.advice, required this.fromAi});

  factory VacaAdvice.fromJson(Object? data) {
    final json = readMap(data);
    return VacaAdvice(advice: _string(json, 'advice'), fromAi: json['source'] == 'ia');
  }

  final String advice;
  final bool fromAi;
}
