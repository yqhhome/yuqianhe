import 'package:equatable/equatable.dart';

/// Panel JSON shape: `{ "ret": 0|1, "msg": "..." }`.
class PanelApiResponse extends Equatable {
  const PanelApiResponse({
    required this.success,
    required this.message,
    this.raw,
  });

  final bool success;
  final String message;
  final Map<String, dynamic>? raw;

  factory PanelApiResponse.fromJson(Map<String, dynamic> json) {
    final ret = json['ret'];
    final ok = ret == 1 || ret == true || ret == '1';
    final msg = json['msg']?.toString() ?? '';
    return PanelApiResponse(success: ok, message: msg, raw: json);
  }

  @override
  List<Object?> get props => [success, message];
}
