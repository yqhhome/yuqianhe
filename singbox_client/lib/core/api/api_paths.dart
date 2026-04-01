/// SSPanel auth routes (`/shouquan` group in `config/routes.php`).
abstract final class ApiPaths {
  static const String authPrefix = '/shouquan';

  static const String login = '$authPrefix/lg';
  static const String register = '$authPrefix/rg';
  static const String sendEmailVerify = '$authPrefix/send';
  static const String logout = '$authPrefix/logout';

  /// Authenticated area; [Auth] middleware returns 302 to login when not signed in.
  static const String userHome = '/user';

  /// Vue API: JSON node list (requires session cookie). See [VueController::getNodeList].
  static const String getNodeList = '/getnodelist';

  /// Vue API: user info JSON. See [VueController::getUserInfo].
  static const String getUserInfo = '/getuserinfo';
}
