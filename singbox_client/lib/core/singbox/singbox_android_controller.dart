import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'singbox_constants.dart';
import 'singbox_controller.dart';
import 'singbox_state.dart';

class SingboxAndroidController implements SingboxController {
  SingboxAndroidController() : _controller = StreamController<SingboxState>.broadcast() {
    _emit(SingboxState.stopped);
  }

  static const MethodChannel _ch = MethodChannel('yuqianhe/singbox_android');
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
    try {
      final ret = await _ch
          .invokeMapMethod<String, dynamic>('start', {
            'config': configJson,
          })
          .timeout(const Duration(seconds: 25));
      final ok = ret?['ok'] == true;
      final mixedPort = (ret?['mixedPort'] as num?)?.toInt() ?? kSingboxDefaultMixedPort;
      setRuntimeSingboxMixedPort(mixedPort);
      if (!ok) {
        _emit(SingboxState(
          phase: SingboxRunPhase.error,
          message: await _withDiagnosis('Android 启动 sing-box 失败。'),
        ));
        return;
      }
      String? err;
      for (var i = 0; i < 12; i++) {
        err = await _verifyOutboundThroughLocalProxy();
        if (err == null) {
          break;
        }
        if (i < 11) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      if (err != null) {
        await stop();
        _emit(SingboxState(
          phase: SingboxRunPhase.error,
          message: await _withDiagnosis(err),
        ));
        return;
      }
      _emit(const SingboxState(phase: SingboxRunPhase.running));
    } on TimeoutException {
      _emit(SingboxState(
        phase: SingboxRunPhase.error,
        message: await _withDiagnosis('Android 启动超时（25s）。'),
      ));
    } on PlatformException catch (e) {
      _emit(SingboxState(
        phase: SingboxRunPhase.error,
        message: await _withDiagnosis('PlatformException(${e.code}): ${e.message ?? ''}'),
      ));
    } on Object catch (e) {
      _emit(SingboxState(
        phase: SingboxRunPhase.error,
        message: await _withDiagnosis('$e'),
      ));
    }
  }

  @override
  Future<void> stop() async {
    _emit(const SingboxState(phase: SingboxRunPhase.stopping));
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
    _emit(SingboxState.stopped);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

Future<String> _withDiagnosis(String base) async {
  try {
    final map = await SingboxAndroidController._ch
        .invokeMapMethod<String, dynamic>('diagnose', {
          // keep extensibility for native-side detailed checks
          'config': null,
        })
        .timeout(const Duration(seconds: 25));
    if (map == null || map.isEmpty) {
      return base;
    }
    final abi = map['abi']?.toString() ?? '';
    final arch = map['archMapped']?.toString() ?? '';
    final libboxVersion = map['libboxVersion']?.toString() ?? '';
    final libboxRunning = map['libboxRunning'] == true;
    final libboxError = map['libboxError']?.toString() ?? '';
    final tar = map['assetTarExists'] == true;
    final tgz = map['assetTarGzExists'] == true;
    final binExists = map['binExists'] == true;
    final binExec = map['binCanExecute'] == true;
    final ensureOk = map['ensureOk'] == true;
    final ensureErr = map['ensureError']?.toString() ?? '';
    final tunDnsServer = map['tunDnsServer']?.toString() ?? '';
    final upstreamInterface = map['upstreamInterface']?.toString() ?? '';
    final activeDnsServers = map['activeDnsServers']?.toString() ?? '';
    final activeNetworkInterface = map['activeNetworkInterface']?.toString() ?? '';
    final dnsFinal = map['dnsFinal']?.toString() ?? '';
    final routeDefaultResolver = map['routeDefaultResolver']?.toString() ?? '';
    final quicFallbackEnabled = map['quicFallbackEnabled']?.toString() ?? '';
    final resolveGoogle = map['resolveGoogle']?.toString() ?? '';
    final resolveFacebook = map['resolveFacebook']?.toString() ?? '';
    final resolveYouTube = map['resolveYouTube']?.toString() ?? '';
    final resolveYouTubeApi = map['resolveYouTubeApi']?.toString() ?? '';
    final proxyGoogle204 = map['proxyGoogle204']?.toString() ?? '';
    final proxyGoogleHome = map['proxyGoogleHome']?.toString() ?? '';
    final proxyYouTubeHome = map['proxyYouTubeHome']?.toString() ?? '';
    final proxyYouTubeApi = map['proxyYouTubeApi']?.toString() ?? '';
    final directGoogleHome = map['directGoogleHome']?.toString() ?? '';
    final directFacebookHome = map['directFacebookHome']?.toString() ?? '';
    return '$base\n'
        '诊断: abi=$abi arch=$arch asset(tar/tgz)=$tar/$tgz '
        'bin(exists/exec)=$binExists/$binExec ensureOk=$ensureOk '
        'libbox(version/running)=$libboxVersion/$libboxRunning'
        '${libboxError.isNotEmpty ? '\nlibboxError: $libboxError' : ''}'
        '${ensureErr.isNotEmpty ? '\nensureError: $ensureErr' : ''}'
        '${tunDnsServer.isNotEmpty ? '\ntunDnsServer: $tunDnsServer' : ''}'
        '${upstreamInterface.isNotEmpty ? '\nupstreamInterface: $upstreamInterface' : ''}'
        '${activeNetworkInterface.isNotEmpty ? '\nactiveNetworkInterface: $activeNetworkInterface' : ''}'
        '${activeDnsServers.isNotEmpty ? '\nactiveDnsServers: $activeDnsServers' : ''}'
        '${dnsFinal.isNotEmpty ? '\ndnsFinal: $dnsFinal' : ''}'
        '${routeDefaultResolver.isNotEmpty ? '\nrouteDefaultResolver: $routeDefaultResolver' : ''}'
        '${quicFallbackEnabled.isNotEmpty ? '\nquicFallbackEnabled: $quicFallbackEnabled' : ''}'
        '${resolveGoogle.isNotEmpty ? '\nresolveGoogle: $resolveGoogle' : ''}'
        '${resolveFacebook.isNotEmpty ? '\nresolveFacebook: $resolveFacebook' : ''}'
        '${resolveYouTube.isNotEmpty ? '\nresolveYouTube: $resolveYouTube' : ''}'
        '${resolveYouTubeApi.isNotEmpty ? '\nresolveYouTubeApi: $resolveYouTubeApi' : ''}'
        '${proxyGoogle204.isNotEmpty ? '\nproxyGoogle204: $proxyGoogle204' : ''}'
        '${proxyGoogleHome.isNotEmpty ? '\nproxyGoogleHome: $proxyGoogleHome' : ''}'
        '${proxyYouTubeHome.isNotEmpty ? '\nproxyYouTubeHome: $proxyYouTubeHome' : ''}'
        '${proxyYouTubeApi.isNotEmpty ? '\nproxyYouTubeApi: $proxyYouTubeApi' : ''}'
        '${directGoogleHome.isNotEmpty ? '\ndirectGoogleHome: $directGoogleHome' : ''}'
        '${directFacebookHome.isNotEmpty ? '\ndirectFacebookHome: $directFacebookHome' : ''}';
  } catch (_) {
    return base;
  }
}

Future<String?> _verifyOutboundThroughLocalProxy() async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY $kSingboxMixedHost:$kSingboxMixedPort';
  client.connectionTimeout = const Duration(seconds: 8);
  client.idleTimeout = const Duration(seconds: 16);
  final targets = <Uri>[
    Uri.parse('https://www.google.com/generate_204'),
    Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
    Uri.parse('https://www.baidu.com/'),
  ];
  try {
    for (var i = 0; i < targets.length; i++) {
      final u = targets[i];
      try {
        final req = await client.getUrl(u);
        final res = await req.close().timeout(const Duration(seconds: 10));
        final code = res.statusCode;
        await res.drain();
        final ok = i < 2 ? code == 204 : (code >= 200 && code < 400);
        if (ok) {
          return null;
        }
      } on Object {
        // try next target
      }
    }
    return '代理测试失败：无法通过本地端口访问外网';
  } on Object catch (e) {
    return '代理测试失败：$e';
  } finally {
    client.close(force: true);
  }
}

