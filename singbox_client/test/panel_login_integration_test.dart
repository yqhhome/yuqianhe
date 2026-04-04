import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:singbox_client/core/di/app_services.dart';
import 'package:singbox_client/data/datasources/auth_remote_datasource.dart';
import 'package:singbox_client/data/models/login_request.dart';

/// Real HTTP check against your panel. Set env vars, then:
/// `PANEL_BASE_URL=https://example.com PANEL_EMAIL=a@b.com PANEL_PASSWORD=secret flutter test test/panel_login_integration_test.dart`
///
/// Fails if: wrong credentials, captcha enabled on login, or network/TLS issues.
void main() {
  final base = Platform.environment['PANEL_BASE_URL']?.trim();
  final email = Platform.environment['PANEL_EMAIL']?.trim();
  final pass = Platform.environment['PANEL_PASSWORD'] ?? '';
  final hasCreds = base != null &&
      base.isNotEmpty &&
      email != null &&
      email.isNotEmpty &&
      pass.isNotEmpty;

  test(
    'panel login API returns ret=1',
    () async {
    final b = base!;
    final e = email!;
    final services = await AppServices.initialize();
    final ds = AuthRemoteDataSource(services, () => b);
    final res = await ds.login(
      LoginRequest(email: e, password: pass, rememberMe: true),
    );

    expect(
      res.success,
      isTrue,
      reason: 'Panel said: ${res.message}',
    );
    },
    skip: hasCreds
        ? false
        : 'Set PANEL_BASE_URL, PANEL_EMAIL, PANEL_PASSWORD to run real login check',
  );
}
