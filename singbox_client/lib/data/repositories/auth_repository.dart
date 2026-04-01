import '../datasources/auth_remote_datasource.dart';
import '../models/login_request.dart';
import '../models/panel_api_response.dart';
import '../models/register_request.dart';

/// Panel authentication: cookie-based session after successful login.
abstract class AuthRepository {
  Future<PanelApiResponse> login(LoginRequest request);

  Future<PanelApiResponse> register(RegisterRequest request);

  Future<PanelApiResponse> sendEmailVerification(String email);

  Future<void> logout();

  Future<bool> validateSession();
}

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<PanelApiResponse> login(LoginRequest request) => _remote.login(request);

  @override
  Future<PanelApiResponse> register(RegisterRequest request) => _remote.register(request);

  @override
  Future<PanelApiResponse> sendEmailVerification(String email) =>
      _remote.sendEmailVerification(email);

  @override
  Future<void> logout() => _remote.logout();

  @override
  Future<bool> validateSession() => _remote.validateSession();
}
