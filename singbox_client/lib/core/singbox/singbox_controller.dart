import 'singbox_state.dart';

/// Controls the sing-box core on each platform (VPN/TUN/process — implemented natively).
abstract class SingboxController {
  Stream<SingboxState> get stateStream;

  SingboxState get currentState;

  /// Starts sing-box with a full JSON config string (sing-box schema).
  Future<void> start(String configJson);

  Future<void> stop();

  Future<void> dispose();
}
