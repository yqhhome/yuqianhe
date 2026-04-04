/// Mixed 入站（HTTP + SOCKS），须与 [sspanel_singbox_config] 中 JSON 一致。
const kSingboxMixedHost = '127.0.0.1';
const kSingboxDefaultMixedPort = 2080;

int _runtimeSingboxMixedPort = kSingboxDefaultMixedPort;

int get kSingboxMixedPort => _runtimeSingboxMixedPort;

void setRuntimeSingboxMixedPort(int port) {
  if (port > 0 && port <= 65535) {
    _runtimeSingboxMixedPort = port;
  }
}
