import 'package:equatable/equatable.dart';

/// Subset of panel `user` from [VueController::getUserInfo] `info.user` + optional `info.ann`.
class PanelUserStats extends Equatable {
  const PanelUserStats({
    required this.todayBytes,
    required this.remainingBytes,
    required this.expireDaysRemaining,
    required this.balanceLabel,
    this.userId,
    this.subscriptionTitle,
    this.expireAt,
    this.announcementPlain,
    this.passwd,
    this.ssPort,
    this.ssMethod,
    this.ssProtocol,
    this.ssObfs,
  });

  /// 今日已用流量（字节），来自 `u+d-last_day_t`。
  final int todayBytes;

  /// 剩余流量（字节），来自 `transfer_enable - u - d`。
  final int remainingBytes;

  /// 用户账户到期剩余天数；`null` 表示无法解析或长期有效。
  final int? expireDaysRemaining;

  /// 账户余额展示文案。
  final String balanceLabel;

  final int? userId;

  /// 顶部订阅/等级摘要（无 `user_name` 时用 `等级 n`）。
  final String? subscriptionTitle;

  /// 用户账户到期时间（本地）。
  final DateTime? expireAt;

  /// 最新公告纯文本（HTML 已粗略剥离）。
  final String? announcementPlain;

  /// 连接密码（与面板 `user.passwd` 一致），用于 HY2 / UUID 派生；勿日志打印。
  final String? passwd;

  /// Shadowsocks/SSR 订阅用端口（`user.port`），与节点名 `#偏移` 规则配合。
  final int? ssPort;

  /// `user.method`（如 aes-128-gcm）。
  final String? ssMethod;

  /// `user.protocol`（origin / auth_chain_a 等）。
  final String? ssProtocol;

  /// `user.obfs`（plain / http_simple 等）。
  final String? ssObfs;

  static PanelUserStats fromApiMaps({
    required Map<String, dynamic> user,
    Map<String, dynamic>? ann,
  }) {
    final u = _toNum(user['u']);
    final d = _toNum(user['d']);
    final lastDay = _toNum(user['last_day_t']);
    final enable = _toNum(user['transfer_enable']);

    final today = (u + d - lastDay).round();
    final rem = (enable - u - d).round();

    final expireDays = _parseExpireDays(user['expire_in']);

    final money = user['money'];
    String balance;
    if (money is num) {
      balance = money.toStringAsFixed(2);
    } else if (money != null) {
      balance = money.toString();
    } else {
      balance = '—';
    }

    return PanelUserStats(
      todayBytes: today < 0 ? 0 : today,
      remainingBytes: rem < 0 ? 0 : rem,
      expireDaysRemaining: expireDays,
      balanceLabel: balance,
      userId: _toInt(user['id']),
      subscriptionTitle: _subscriptionTitle(user),
      expireAt: _parseExpireDate(user['expire_in']),
      announcementPlain: _announcementPlain(ann),
      passwd: user['passwd']?.toString(),
      ssPort: _toInt(user['port']),
      ssMethod: user['method']?.toString(),
      ssProtocol: user['protocol']?.toString(),
      ssObfs: user['obfs']?.toString(),
    );
  }

  static int? _toInt(dynamic v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.toInt();
    }
    return int.tryParse(v?.toString() ?? '');
  }

  static String? _subscriptionTitle(Map<String, dynamic> user) {
    final name = user['user_name']?.toString().trim();
    if (name != null && name.isNotEmpty && name != 'null') {
      return name;
    }
    final cls = user['class'];
    if (cls is num) {
      return '等级 ${cls.toInt()}';
    }
    if (cls != null) {
      return '等级 ${cls.toString()}';
    }
    return null;
  }

  static String? _announcementPlain(Map<String, dynamic>? ann) {
    if (ann == null || ann.isEmpty) {
      return null;
    }
    final md = ann['markdown'];
    final raw = (md != null && md.toString().trim().isNotEmpty)
        ? md.toString()
        : (ann['content']?.toString() ?? '');
    if (raw.isEmpty) {
      return null;
    }
    var t = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? null : t;
  }

  static double _toNum(dynamic v) {
    if (v == null) {
      return 0;
    }
    if (v is num) {
      return v.toDouble();
    }
    return double.tryParse(v.toString()) ?? 0;
  }

  static DateTime? _parseExpireDate(dynamic v) {
    if (v == null) {
      return null;
    }
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty || s == '0' || s.startsWith('0000-00-00')) {
        return null;
      }
      return DateTime.tryParse(s)?.toLocal();
    }
    if (v is num) {
      final n = v.toDouble();
      if (n <= 0) {
        return null;
      }
      if (n > 1e12) {
        return DateTime.fromMillisecondsSinceEpoch(n.round(), isUtc: false).toLocal();
      }
      if (n > 1e9) {
        return DateTime.fromMillisecondsSinceEpoch((n * 1000).round(), isUtc: false).toLocal();
      }
    }
    return null;
  }

  static int? _parseExpireDays(dynamic v) {
    final exp = _parseExpireDate(v);
    if (exp == null) {
      return null;
    }
    final now = DateTime.now();
    if (!exp.isAfter(now)) {
      return 0;
    }
    return exp.difference(now).inDays;
  }

  String expireDateLabel() {
    final e = expireAt;
    if (e == null) {
      return '—';
    }
    return '${e.year}/${e.month}/${e.day}';
  }

  String remainingDaysLabel() {
    final d = expireDaysRemaining;
    if (d == null) {
      return '长期有效';
    }
    if (d <= 0) {
      return '已过期';
    }
    return '剩余 $d 天';
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const u = 1024;
    if (bytes < u) {
      return '$bytes B';
    }
    final kb = bytes / u;
    if (kb < u) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / u;
    if (mb < u) {
      return '${mb.toStringAsFixed(2)} MB';
    }
    final gb = mb / u;
    if (gb < u) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final tb = gb / u;
    return '${tb.toStringAsFixed(2)} TB';
  }

  String get remainingTrafficCompact {
    final gb = remainingBytes / (1024 * 1024 * 1024);
    if (gb < 0) {
      return '0 GB';
    }
    if (gb < 1024) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    return '${(gb / 1024).toStringAsFixed(2)} TB';
  }

  bool get hasRemainingTraffic => remainingBytes > 0;

  bool get isExpired {
    final d = expireDaysRemaining;
    return d != null && d <= 0;
  }

  bool get isAccessBlocked => isExpired || !hasRemainingTraffic;

  String get accessBlockedReason {
    if (isExpired && !hasRemainingTraffic) {
      return '账号已到期，且流量已用完';
    }
    if (isExpired) {
      return '账号已到期';
    }
    if (!hasRemainingTraffic) {
      return '流量已用完';
    }
    return '';
  }

  @override
  List<Object?> get props => [
        todayBytes,
        remainingBytes,
        expireDaysRemaining,
        balanceLabel,
        userId,
        subscriptionTitle,
        expireAt,
        announcementPlain,
        passwd,
        ssPort,
        ssMethod,
        ssProtocol,
        ssObfs,
      ];
}
