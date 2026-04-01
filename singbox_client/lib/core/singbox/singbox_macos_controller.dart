import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'singbox_constants.dart';
import 'singbox_controller.dart';
import 'singbox_state.dart';

/// 经本机 mixed 代理访问公网；用于确认 sing-box 出站可用（非仅进程存活）。
Future<String?> _verifyOutboundThroughLocalProxy() async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY $kSingboxMixedHost:$kSingboxMixedPort';
  client.connectionTimeout = const Duration(seconds: 10);
  client.idleTimeout = const Duration(seconds: 18);

  final google204 = Uri.parse('https://www.google.com/generate_204');
  final backup204 = Uri.parse('https://connectivitycheck.gstatic.com/generate_204');
  final baidu = Uri.parse('https://www.baidu.com');

  Object? last;
  try {
    // 主检测：必须能通过代理访问 Google，避免“进程存活但无法翻墙”被误判为成功。
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

    // 兜底诊断：若国内站点可达但 Google 不可达，提示“节点策略/出口受限”。
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

    // 次检测：gstatic 204，可辅助区分 Google 域名级别故障。
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
    return _formatProxyVerifyFailure(last ?? Exception('未知错误'));
  } finally {
    client.close(force: true);
  }
}

String _formatProxyVerifyFailure(Object e) {
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

/// 通过子进程启动官方 [sing-box](https://github.com/SagerNet/sing-box) 可执行文件。
///
/// 查找顺序：`SINGBOX_PATH` → App 包内 `Contents/Resources/sing-box` → Homebrew → `which sing-box`。
class SingboxMacosController implements SingboxController {
  SingboxMacosController() : _controller = StreamController<SingboxState>.broadcast() {
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
    String? runtimeArch;
    try {
      final r = Process.runSync('uname', ['-m']);
      if (r.exitCode == 0) {
        final s = r.stdout.toString().trim();
        if (s.isNotEmpty) {
          runtimeArch = s;
        }
      }
    } catch (_) {}
    try {
      final exe = Platform.resolvedExecutable;
      final exeDir = File(exe).parent.path;
      // 兼容不同启动方式下 resolvedExecutable 的位置：
      // - .../Contents/MacOS/singbox_client
      // - .../Contents/Frameworks/App.framework/.../App
      final bases = <String>[
        '$exeDir/../Resources',
        '$exeDir/../../Resources',
        '$exeDir/../../../Resources',
      ];
      final candidates = <String>[];
      for (final base in bases) {
        if (runtimeArch != null) {
          candidates.add('$base/sing-box-$runtimeArch');
        }
        candidates.add('$base/sing-box');
      }
      for (final p in candidates) {
        final bundled = File(p);
        if (bundled.existsSync()) {
          return bundled.resolveSymbolicLinksSync();
        }
      }
    } catch (_) {}
    for (final p in ['/opt/homebrew/bin/sing-box', '/usr/local/bin/sing-box']) {
      if (File(p).existsSync()) {
        return p;
      }
    }
    try {
      final r = Process.runSync('which', ['sing-box']);
      if (r.exitCode == 0) {
        final line = r.stdout.toString().trim().split('\n').first.trim();
        if (line.isNotEmpty && File(line).existsSync()) {
          return line;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<int> _pickMixedPort() async {
    // 优先保留默认端口，避免频繁切换系统代理端口。
    for (final candidate in <int>[kSingboxDefaultMixedPort, 0]) {
      ServerSocket? s;
      try {
        s = await ServerSocket.bind(InternetAddress.loopbackIPv4, candidate);
        final p = s.port;
        await s.close();
        return p;
      } catch (_) {
        if (s != null) {
          try {
            await s.close();
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
    final t = utf8.decode(chunk, allowMalformed: true);
    if (_stderrTail.length > 2000) {
      final s = _stderrTail.toString();
      _stderrTail.clear();
      _stderrTail.write(s.substring(s.length > 800 ? s.length - 800 : 0));
    }
    _stderrTail.write(t);
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
              '未找到 sing-box 可执行文件。请安装：brew install sing-box，或设置环境变量 SINGBOX_PATH，或将二进制放入 App 的 Contents/Resources/sing-box。',
        ));
        return;
      }

      final dir = await getTemporaryDirectory();
      // macOS 上该路径可能在「清理缓存」或首次启动时尚未存在，须先创建再写入 JSON。
      await dir.create(recursive: true);
      final file = File('${dir.path}/singbox_client_run.json');
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
          message: '无法启动 sing-box：$e',
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
            message: 'sing-box 已退出（退出码 $code）。请检查节点配置或关闭 TUN 仅使用全局代理。$extra',
          ));
        } else {
          _emit(SingboxState.stopped);
        }
      });

      // 配置错误时 sing-box 会立刻退出；先让 exit 的 microtask 跑完，避免一直停在「启动中」
      await Future<void>.delayed(Duration.zero);
      if (_userStop) {
        return;
      }
      if (_process == null) {
        // 已快速退出，exit 回调里应已变为 error/stopped
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
        verifyErr = await _verifyOutboundThroughLocalProxy();
        if (verifyErr == null) {
          break;
        }
        // 进程刚拉起时，mixed 端口可能稍后才监听；短暂重试可避免误判失败。
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
          proc.kill(ProcessSignal.sigterm);
          await proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
            proc.kill(ProcessSignal.sigkill);
            return -1;
          });
        } catch (_) {}
        await _errSub?.cancel();
        _errSub = null;
        _process = null;
        final tail = _stderrTail.toString().trim();
        final extra =
            tail.isNotEmpty ? '\nsing-box 日志：\n$tail' : '';
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
    final p = _process;
    if (p == null) {
      _emit(SingboxState.stopped);
      return;
    }
    _emit(const SingboxState(phase: SingboxRunPhase.stopping));
    try {
      p.kill(ProcessSignal.sigterm);
      await p.exitCode.timeout(const Duration(seconds: 4), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
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
