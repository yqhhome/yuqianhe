import 'package:equatable/equatable.dart';

/// Mirrors [AuthController::registerHandle] POST fields.
class RegisterRequest extends Equatable {
  const RegisterRequest({
    required this.email,
    required this.password,
    required this.repeatPassword,
    this.displayName,
    this.contact,
    this.inviteCode = '',
    this.emailVerificationCode,
    this.imType = '2',
  });

  final String email;
  final String password;
  final String repeatPassword;

  /// Maps to `name` (web often duplicates email).
  final String? displayName;

  /// Maps to `wechat` contact field (web often duplicates email).
  final String? contact;

  /// Invite code when [register_mode] is `invite`.
  final String inviteCode;

  /// When [enable_email_verify] is on.
  final String? emailVerificationCode;

  /// IM type id (theme default `2`).
  final String imType;

  Map<String, String> toFormFields() {
    final e = email.trim().toLowerCase();
    return {
      'name': (displayName ?? e).trim(),
      'email': e,
      'passwd': password,
      'repasswd': repeatPassword,
      'wechat': (contact ?? e).trim(),
      'imtype': imType,
      'code': inviteCode.trim(),
      if (emailVerificationCode != null && emailVerificationCode!.trim().isNotEmpty)
        'emailcode': emailVerificationCode!.trim(),
    };
  }

  @override
  List<Object?> get props =>
      [email, password, repeatPassword, displayName, contact, inviteCode, emailVerificationCode, imType];
}
