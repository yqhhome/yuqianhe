import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'singbox_constants.dart';
import 'singbox_controller.dart';
import 'singbox_state.dart';

Future<String?> _verifyWindowsOutboundThroughLocalProxy() async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY $kSingboxMixedHost:$kSingboxMixedPort';
  client.connectionTimeout = const Duration(seconds: 10);
  client.idleTimeout = const Duration(seconds: 18);

  final google204 = Uri.parse('https://www.google.com/generate_204');
  final backup204 = Uri.parse('https://connectivitycheck.gstatic.com/generate_204');
  final baidu = Uri.parse('https://www.baidu.com');

  Object? last;
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final req = await client.getUrl(google204);
        final res = await req.close().timeout(const Duration(seconds: 20));
        final code = res.statusCode;
        await res.drain();
        if (code == 204) {
          return null;
        }
        last = HttpException('HTTP $code', uri: google204);
      } on Object catch (e) {
        last = e;
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 200 + attempt * 150));
      }
    }

    try {
      final req = await client.getUrl(baidu);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final code = res.statusCode;
      await res.drain();
      if (code >= 200 && code < 400) {
        return '当前节点代理已建立，但无法访问 Google（可能是节点分流策略或出口限制）。';
      }
    } on Object {
      // 忽略兜底探测异常，保留主检测失败信息。
    }

    try {
      final req = await client.getUrl(backup204);
      final res = await req.close().timeout(const Duration(seconds: 15));
      final code = res.statusCode;
      await res.drain();
      if (code == 204) {
        return '代理可用，但 Google 域名访问异常（可能 DNS 或分流策略导致）。';
      }
      last = HttpException('HTTP $code', uri: backup204);
    } on Object catch (e) {
      last = e;
    }
    return _formatWindowsProxyVerifyFailure(last ?? Exception('未知错误'));
  } finally {
    client.close(force: true);
  }
}

String _formatWindowsProxyVerifyFailure(Object e) {
  if (e is SocketException) {
    final m = e.message.toLowerCase();
    if (m.contains('connection refused') || m.contains('actively refused')) {
      return '本机代理端口未就绪（${e.message}）';
    }
    if (m.contains('read failed') || m.contains('reset by peer')) {
      return '代理已启动但上游连接异常（${e.message}）';
    }
    return '无法连上本机代理 $kSingboxMixedHost:$kSingboxMixedPort（sing-box 可能未就绪）。${e.message}';
  }
  if (e is TimeoutException) {
    return '经代理访问外网超时：节点配置错误或网络不可达，请检查地址/端口/协议。';
  }
  if (e is HandshakeException) {
    return 'TLS 握手失败（经代理）：${e.message}';
  }
  if (e is TlsException) {
    return 'TLS 错误（经代理）：${e.message}';
  }
  if (e is HttpException) {
    return '代理请求失败：${e.message}';
  }
  return '代理连通性检测失败：$e';
}

class SingboxWindowsController implements SingboxController {
  SingboxWindowsController()
      : _controller = StreamController<SingboxState>.broadcast() {
    _emit(SingboxState.stopped);
  }

  final StreamController<SingboxState> _controller;
  SingboxState _current = SingboxState.stopped;

  Process? _process;
  StreamSubscription<List<int>>? _errSub;
  bool _userStop = false;
  final StringBuffer _stderrTail = StringBuffer();

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

  static String? _resolveBinaryPath() {
    final env = Platform.environment['SINGBOX_PATH'];
    if (env != null && env.isNotEmpty && File(env).existsSync()) {
      return env;
    }

    final candidates = <String>{};
    try {
      final exe = Platform.resolvedExecutable;
      final exeDir = File(exe).parent.path;
      candidates.add('$exeDir/sing-box.exe');
      candidates.add('$exeDir/data/sing-box.exe');
      candidates.add('$exeDir/../sing-box.exe');
    } catch (_) {}

    try {
      final cwd = Directory.current.path;
      candidates.add('$cwd/sing-box.exe');
      candidates.add('$cwd/data/sing-box.exe');
    } catch (_) {}

    for (final path in candidates) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          return file.resolveSymbolicLinksSync();
        } catch (_) {
          return file.path;
        }
      }
    }

    for (final command in const ['where.exe', 'where']) {
      try {
        final r = Process.runSync(command, ['sing-box.exe']);
        if (r.exitCode == 0) {
          final line = r.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first.trim();
          if (line.isNotEmpty && File(line).existsSync()) {
            return line;
          }
        }
      } catch (_) {}
      try {
        final r = Process.runSync(command, ['sing-box']);
        if (r.exitCode == 0) {
          final line = r.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first.trim();
          if (line.isNotEmpty && File(line).existsSync()) {
            return line;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<int> _pickMixedPort() async {
    for (final candidate in <int>[kSingboxDefaultMixedPort, 0]) {
      ServerSocket? socket;
      try {
        socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, candidate);
        final port = socket.port;
        await socket.close();
        return port;
      } catch (_) {
        if (socket != null) {
          try {
            await socket.close();
          } catch (_) {}
        }
      }
    }
    return kSingboxDefaultMixedPort;
  }

  static String _overrideMixedInboundPort(String configJson, int port) {
    try {
      final root = jsonDecode(configJson);
      if (root is Map<String, dynamic>) {
        final inbounds = root['inbounds'];
        if (inbounds is List) {
          for (final item in inbounds) {
            if (item is Map<String, dynamic> && item['type'] == 'mixed') {
              item['listen'] = kSingboxMixedHost;
              item['listen_port'] = port;
            }
          }
        }
      }
      return const JsonEncoder.withIndent('  ').convert(root);
    } catch (_) {
      return configJson;
    }
  }

  void _appendStderr(List<int> chunk) {
    final text = utf8.decode(chunk, allowMalformed: true);
    if (_stderrTail.length > 2000) {
      final current = _stderrTail.toString();
      _stderrTail.clear();
      _stderrTail.write(current.substring(current.length > 800 ? current.length - 800 : 0));
    }
    _stderrTail.write(text);
  }

  @override
  Future<void> start(String configJson) async {
    await stop();
    _userStop = false;
    _stderrTail.clear();
    _emit(const SingboxState(phase: SingboxRunPhase.starting));

    try {
      final bin = _resolveBinaryPath();
      if (bin == null) {
        _emit(const SingboxState(
          phase: SingboxRunPhase.error,
          message:
              '未找到 sing-box.exe。请设置环境变量 SINGBOX_PATH，或将 sing-box.exe 放在程序目录旁边。',
        ));
        return;
      }

      final dir = await getTemporaryDirectory();
      await dir.create(recursive: true);
      final file = File('${dir.path}/singbox_client_windows_run.json');
      final mixedPort = await _pickMixedPort();
      setRuntimeSingboxMixedPort(mixedPort);
      final effectiveConfig = _overrideMixedInboundPort(configJson, mixedPort);
      await file.writeAsString(effectiveConfig);

      late final Process proc;
      try {
        proc = await Process.start(
          bin,
          ['run', '-c', file.path],
          mode: ProcessStartMode.normal,
        );
      } on Object catch (e) {
        _emit(SingboxState(
          phase: SingboxRunPhase.error,
          message: '无法启动 sing-box.exe：$e',
        ));
        return;
      }

      _process = proc;
      _errSub = proc.stderr.listen(_appendStderr);

      proc.exitCode.then((code) async {
        await _errSub?.cancel();
        _errSub = null;
        _process = null;
        if (_userStop) {
          return;
        }
        if (code != 0) {
          final tail = _stderrTail.toString().trim();
          final extra = tail.isNotEmpty ? '\n$tail' : '';
          _emit(SingboxState(
            phase: SingboxRunPhase.error,
            message: 'sing-box 已退出（退出码 $code）。请检查节点配置。$extra',
          ));
        } else {
          _emit(SingboxState.stopped);
        }
      });

      await Future<void>.delayed(Duration.zero);
      if (_userStop || _process == null) {
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_userStop || _process == null) {
        return;
      }

      String? verifyErr;
      for (var i = 0; i < 4; i++) {
        if (_userStop) {
          return;
        }
        if (_process == null) {
          break;
        }
        verifyErr = await _verifyWindowsOutboundThroughLocalProxy();
        if (verifyErr == null) {
          break;
        }
        if (i < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        }
      }

      if (verifyErr != null) {
        if (_process == null) {
          final tail = _stderrTail.toString().trim();
          final extra = tail.isNotEmpty ? '\n$tail' : '';
          _emit(SingboxState(
            phase: SingboxRunPhase.error,
            message: 'sing-box 已退出，导致代理不可用。$extra',
          ));
          return;
        }
        _userStop = true;
        try {
          proc.kill();
          await proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
            proc.kill();
            return -1;
          });
        } catch (_) {}
        await _errSub?.cancel();
        _errSub = null;
        _process = null;
        final tail = _stderrTail.toString().trim();
        final extra = tail.isNotEmpty ? '\nsing-box 日志：\n$tail' : '';
        _emit(SingboxState(
          phase: SingboxRunPhase.error,
          message: '代理不可用：$verifyErr$extra',
        ));
        return;
      }

      _emit(const SingboxState(phase: SingboxRunPhase.running));
    } on Object catch (e) {
      _process = null;
      await _errSub?.cancel();
      _errSub = null;
      _emit(SingboxState(
        phase: SingboxRunPhase.error,
        message: '启动失败：$e',
      ));
    }
  }

  @override
  Future<void> stop() async {
    _userStop = true;
    final proc = _process;
    if (proc == null) {
      _emit(SingboxState.stopped);
      return;
    }
    _emit(const SingboxState(phase: SingboxRunPhase.stopping));
    try {
      proc.kill();
      await proc.exitCode.timeout(const Duration(seconds: 4), onTimeout: () {
        proc.kill();
        return -1;
      });
    } catch (_) {}
    await _errSub?.cancel();
    _errSub = null;
    _process = null;
    _emit(SingboxState.stopped);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
