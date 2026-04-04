import 'package:flutter/material.dart';

/// 公告跑马灯：内容从**右到左**循环滚动（无缝衔接）。
///
/// [text] 宽度小于可用宽度时不滚动，仅单行省略或完整显示。
class AnnouncementMarquee extends StatefulWidget {
  const AnnouncementMarquee({
    super.key,
    required this.text,
    this.style,
    this.speed = 42,
    this.gap = 40,
    this.onTap,
  });

  final String text;
  final TextStyle? style;

  /// 滚动速度（像素/秒，按「单段」路程估算时长）。
  final double speed;

  /// 两段重复公告之间的空隙。
  final double gap;

  /// 点击跑马灯区域（例如查看全文）。
  final VoidCallback? onTap;

  @override
  State<AnnouncementMarquee> createState() => _AnnouncementMarqueeState();
}

class _AnnouncementMarqueeState extends State<AnnouncementMarquee> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  double _segmentLen = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnnouncementMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.speed != widget.speed ||
        oldWidget.gap != widget.gap) {
      _controller?.dispose();
      _controller = null;
      _segmentLen = 0;
    }
  }

  void _syncController(double segment) {
    if (segment <= 0) {
      return;
    }
    if ((_segmentLen - segment).abs() < 0.5 && _controller != null) {
      return;
    }
    _controller?.dispose();
    _segmentLen = segment;
    final durMs = (segment / widget.speed * 1000).round().clamp(4000, 180000);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durMs),
    )..repeat();
  }

  Widget _wrapTap(Widget child) {
    if (widget.onTap == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final tw = tp.width;
        if (tw <= maxW) {
          _controller?.dispose();
          _controller = null;
          _segmentLen = 0;
          return _wrapTap(
            Text(
              widget.text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }

        final seg = tw + widget.gap;
        _syncController(seg);
        final ac = _controller;
        if (ac == null) {
          return const SizedBox.shrink();
        }

        return _wrapTap(
          ClipRect(
            child: SizedBox(
              height: tp.height.clamp(18, 48),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: ac,
                  builder: (context, _) {
                    final t = ac.value;
                    // t:0→1，位移从 0 到 -seg：整行向左移动，视觉上文字从右向左流过。
                    final off = -seg * t;
                    return Transform.translate(
                      offset: Offset(off, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.text, style: style, maxLines: 1),
                          SizedBox(width: widget.gap),
                          Text(widget.text, style: style, maxLines: 1),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
