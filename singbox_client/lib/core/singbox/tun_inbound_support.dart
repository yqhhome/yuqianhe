import 'platform_info.dart';

/// 是否在 sing-box 配置中加入 `tun` inbound。
///
/// Android 已切到 libbox + 真 TUN；其余平台继续沿用 mixed 入站。
final bool tunInboundSupported = isAndroid;
