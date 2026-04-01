import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/core/proxy/sspanel_singbox_config.dart';
import 'package:singbox_client/data/models/panel_node.dart';

void main() {
  test('uses vmess outside_port for ping target', () {
    const node = PanelNode(
      id: 1,
      name: 'VMess 节点',
      sort: 11,
      rawServer: 'vmess.example.com;443;0;ws;none;outside_port=8443|host=cdn.example.com',
    );

    final target = panelNodePingTarget(node: node, userPort: 1024);

    expect(target, isNotNull);
    expect(target!.host, 'vmess.example.com');
    expect(target.port, 8443);
  });

  test('uses node name offset for vmess ping target', () {
    const node = PanelNode(
      id: 2,
      name: 'VMess 节点#9',
      sort: 11,
      rawServer: 'vmess.example.com;443;0;tcp;none;',
    );

    final target = panelNodePingTarget(node: node, userPort: 1024);

    expect(target, isNotNull);
    expect(target!.host, 'vmess.example.com');
    expect(target.port, 452);
  });

  test('parses vless reality json ping target', () {
    const node = PanelNode(
      id: 3,
      name: 'Reality',
      sort: 14,
      rawServer: '{"server":"reality.example.com","port":"2053","pbk":"abc"}',
    );

    final target = panelNodePingTarget(node: node, userPort: 1024);

    expect(target, isNotNull);
    expect(target!.host, 'reality.example.com');
    expect(target.port, 2053);
  });

  test('parses hysteria2 json ping target', () {
    const node = PanelNode(
      id: 4,
      name: 'HY2',
      sort: 15,
      rawServer: '{"server":"hy2.example.com","port":"8443","auth":"x"}',
    );

    final target = panelNodePingTarget(node: node, userPort: 1024);

    expect(target, isNotNull);
    expect(target!.host, 'hy2.example.com');
    expect(target.port, 8443);
  });

  test('falls back to legacy ss display host', () {
    const node = PanelNode(
      id: 5,
      name: 'SS 节点',
      sort: 10,
      serverDisplay: 'ss.example.com',
    );

    final target = panelNodePingTarget(node: node, userPort: 8388);

    expect(target, isNotNull);
    expect(target!.host, 'ss.example.com');
    expect(target.port, 8388);
  });

  test('can parse reality target without user port', () {
    const node = PanelNode(
      id: 6,
      name: 'Reality 无端口依赖',
      sort: 14,
      rawServer: '{"server":"reality2.example.com","port":"443","pbk":"abc"}',
    );

    final target = panelNodePingTarget(node: node, userPort: null);

    expect(target, isNotNull);
    expect(target!.host, 'reality2.example.com');
    expect(target.port, 443);
  });

  test('ss requires user port', () {
    const node = PanelNode(
      id: 7,
      name: 'SS 需用户端口',
      sort: 10,
      serverDisplay: 'ss2.example.com',
    );

    final target = panelNodePingTarget(node: node, userPort: null);

    expect(target, isNull);
  });
}
