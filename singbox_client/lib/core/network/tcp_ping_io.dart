import 'dart:io';

/// TCP 建连耗时（毫秒），用于近似 ping；失败返回 `null`。
Future<int?> tcpConnectLatencyMs(String host, int port) async {
  try {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 3),
    );
    sw.stop();
    await socket.close();
    return sw.elapsedMilliseconds;
  } on Object {
    return null;
  }
}
