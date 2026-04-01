/// 根据节点名称中的国家/地区关键词匹配国旗 emoji（ISO 3166-1 alpha-2 → regional indicators）。
abstract final class CountryFlag {
  CountryFlag._();

  static String codeToEmoji(String code) {
    if (code.length != 2) {
      return '';
    }
    final c = code.toUpperCase();
    final a = c.codeUnitAt(0);
    final b = c.codeUnitAt(1);
    if (a < 0x41 || a > 0x5a || b < 0x41 || b > 0x5a) {
      return '';
    }
    return String.fromCharCode(0x1f1e6 + (a - 0x41)) + String.fromCharCode(0x1f1e6 + (b - 0x41));
  }

  /// 关键词按长度从长到短匹配，避免「国」误匹配。
  static const List<(String, String)> _zh = [
    ('乌兹别克斯坦', 'UZ'),
    ('哈萨克斯坦', 'KZ'),
    ('印度尼西亚', 'ID'),
    ('马来西亚', 'MY'),
    ('澳大利亚', 'AU'),
    ('新西兰', 'NZ'),
    ('新加坡', 'SG'),
    ('菲律宾', 'PH'),
    ('加拿大', 'CA'),
    ('美国', 'US'),
    ('英国', 'GB'),
    ('德国', 'DE'),
    ('法国', 'FR'),
    ('日本', 'JP'),
    ('韩国', 'KR'),
    ('香港', 'HK'),
    ('澳门', 'MO'),
    ('台湾', 'TW'),
    ('越南', 'VN'),
    ('泰国', 'TH'),
    ('印度', 'IN'),
    ('俄罗斯', 'RU'),
    ('乌克兰', 'UA'),
    ('土耳其', 'TR'),
    ('巴西', 'BR'),
    ('阿根廷', 'AR'),
    ('墨西哥', 'MX'),
    ('智利', 'CL'),
    ('哥伦比亚', 'CO'),
    ('阿联酋', 'AE'),
    ('迪拜', 'AE'),
    ('沙特', 'SA'),
    ('以色列', 'IL'),
    ('意大利', 'IT'),
    ('西班牙', 'ES'),
    ('荷兰', 'NL'),
    ('瑞士', 'CH'),
    ('瑞典', 'SE'),
    ('波兰', 'PL'),
    ('挪威', 'NO'),
    ('丹麦', 'DK'),
    ('芬兰', 'FI'),
    ('比利时', 'BE'),
    ('奥地利', 'AT'),
    ('葡萄牙', 'PT'),
    ('希腊', 'GR'),
    ('捷克', 'CZ'),
    ('爱尔兰', 'IE'),
    ('冰岛', 'IS'),
    ('罗马尼亚', 'RO'),
    ('匈牙利', 'HU'),
    ('保加利亚', 'BG'),
    ('塞尔维亚', 'RS'),
    ('克罗地亚', 'HR'),
    ('斯洛伐克', 'SK'),
    ('斯洛文尼亚', 'SI'),
    ('爱沙尼亚', 'EE'),
    ('拉脱维亚', 'LV'),
    ('立陶宛', 'LT'),
    ('埃及', 'EG'),
    ('南非', 'ZA'),
    ('尼日利亚', 'NG'),
    ('肯尼亚', 'KE'),
    ('巴基斯坦', 'PK'),
    ('孟加拉', 'BD'),
    ('缅甸', 'MM'),
    ('柬埔寨', 'KH'),
    ('老挝', 'LA'),
    ('尼泊尔', 'NP'),
    ('斯里兰卡', 'LK'),
    ('蒙古', 'MN'),
    ('文莱', 'BN'),
    ('卡塔尔', 'QA'),
    ('科威特', 'KW'),
    ('巴林', 'BH'),
    ('阿曼', 'OM'),
    ('约旦', 'JO'),
    ('黎巴嫩', 'LB'),
    ('塞浦路斯', 'CY'),
    ('马耳他', 'MT'),
    ('卢森堡', 'LU'),
    ('秘鲁', 'PE'),
    ('委内瑞拉', 'VE'),
    ('哥斯达黎加', 'CR'),
    ('巴拿马', 'PA'),
    ('厄瓜多尔', 'EC'),
    ('乌拉圭', 'UY'),
    ('巴拉圭', 'PY'),
    ('玻利维亚', 'BO'),
  ];

  static const List<(String, String)> _en = [
    ('United States', 'US'),
    ('USA', 'US'),
    ('Japan', 'JP'),
    ('United Kingdom', 'GB'),
    ('UK', 'GB'),
    ('Germany', 'DE'),
    ('France', 'FR'),
    ('Singapore', 'SG'),
    ('Hong Kong', 'HK'),
    ('Taiwan', 'TW'),
    ('Korea', 'KR'),
    ('Thailand', 'TH'),
    ('Malaysia', 'MY'),
    ('Indonesia', 'ID'),
    ('Vietnam', 'VN'),
    ('India', 'IN'),
    ('Australia', 'AU'),
    ('Canada', 'CA'),
    ('Brazil', 'BR'),
    ('Russia', 'RU'),
    ('Ukraine', 'UA'),
    ('Turkey', 'TR'),
    ('Netherlands', 'NL'),
    ('Spain', 'ES'),
    ('Italy', 'IT'),
    ('Poland', 'PL'),
    ('Sweden', 'SE'),
    ('Norway', 'NO'),
    ('Denmark', 'DK'),
    ('Finland', 'FI'),
    ('Ireland', 'IE'),
    ('Switzerland', 'CH'),
    ('Belgium', 'BE'),
    ('Austria', 'AT'),
    ('Portugal', 'PT'),
    ('Greece', 'GR'),
    ('Czech', 'CZ'),
    ('Romania', 'RO'),
    ('Hungary', 'HU'),
    ('Israel', 'IL'),
    ('UAE', 'AE'),
    ('Dubai', 'AE'),
    ('Saudi', 'SA'),
    ('Mexico', 'MX'),
    ('Argentina', 'AR'),
    ('Chile', 'CL'),
    ('Colombia', 'CO'),
    ('South Africa', 'ZA'),
    ('Egypt', 'EG'),
    ('Nigeria', 'NG'),
    ('Pakistan', 'PK'),
    ('Bangladesh', 'BD'),
    ('New Zealand', 'NZ'),
    ('Philippines', 'PH'),
  ];

  /// 若名称中可识别国家/地区则返回对应国旗 emoji，否则 `null`。
  static String? emojiForNodeName(String name) {
    if (name.isEmpty) {
      return null;
    }
    for (final (kw, code) in _zh) {
      if (name.contains(kw)) {
        return codeToEmoji(code);
      }
    }
    final lower = name.toLowerCase();
    for (final (kw, code) in _en) {
      if (lower.contains(kw.toLowerCase())) {
        return codeToEmoji(code);
      }
    }
    return null;
  }
}
