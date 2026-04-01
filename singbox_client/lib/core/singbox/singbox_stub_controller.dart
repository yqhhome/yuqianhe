import 'dart:async';

import 'singbox_controller.dart';
import 'singbox_state.dart';

/// Placeholder until Android/iOS/Desktop embed sing-box (MethodChannel / FFI).
class SingboxStubController implements SingboxController {
  SingboxStubController() : _controller = StreamController<SingboxState>.broadcast() {
    _emit(SingboxState.stopped);
  }

  final StreamController<SingboxState> _controller;
  SingboxState _current = SingboxState.stopped;

  void _emit(SingboxState s) {
    _current = s;
    if (!_controller.isClosed) {
      _controller.add(s);
    }
  }

  @override
  SingboxState get currentState => _current;

  @override
  Stream<SingboxState> get stateStream => _controller.stream;

  @override
  Future<void> start(String configJson) async {
    _emit(const SingboxState(phase: SingboxRunPhase.starting));
    await Future<void>.delayed(const Duration(milliseconds: 280));
    // Stub：便于客户端主页联调；接入真 sing-box 后由原生实现替换。
    _emit(const SingboxState(phase: SingboxRunPhase.running));
  }

  @override
  Future<void> stop() async {
    _emit(const SingboxState(phase: SingboxRunPhase.stopping));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _emit(SingboxState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
