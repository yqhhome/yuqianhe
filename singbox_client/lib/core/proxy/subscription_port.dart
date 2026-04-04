/// 对齐 PHP [URL::subscriptionPortFromNodeName]：节点名「名称#偏移」时对外端口 = 443 + 偏移。
int subscriptionPortFromNodeName(String nodeName, int fallbackPort) {
  final parts = nodeName.split('#');
  if (parts.length < 2) {
    return fallbackPort;
  }
  final suffix = parts[1].trim();
  if (suffix.isEmpty || int.tryParse(suffix) == null) {
    return fallbackPort;
  }
  return 443 + int.parse(suffix);
}
