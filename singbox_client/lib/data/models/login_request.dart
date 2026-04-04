import 'package:equatable/equatable.dart';

class LoginRequest extends Equatable {
  const LoginRequest({
    required this.email,
    required this.password,
    this.totpCode,
    this.rememberMe = true,
  });

  final String email;
  final String password;
  final String? totpCode;
  final bool rememberMe;

  Map<String, String> toFormFields() {
    return {
      'email': email.trim().toLowerCase(),
      'passwd': password,
      if (totpCode != null && totpCode!.trim().isNotEmpty) 'code': totpCode!.trim(),
      // 与主题 `login.tpl` 中 checkbox 的 `value="week"` 一致，便于面板识别「记住我」
      if (rememberMe) 'remember_me': 'week',
    };
  }

  @override
  List<Object?> get props => [email, password, totpCode, rememberMe];
}
