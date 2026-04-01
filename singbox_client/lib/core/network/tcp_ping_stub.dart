/// Web 等平台无 [dart:io] TCP，跳过测延迟。
Future<int?> tcpConnectLatencyMs(String host, int port) async => null;
