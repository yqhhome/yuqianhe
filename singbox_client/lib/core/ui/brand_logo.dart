import 'package:flutter/material.dart';

const _kBrandName = '宇千鹤';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 72,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.18),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Icon(
        Icons.shield_rounded,
        color: theme.colorScheme.onPrimary,
        size: size * 0.58,
      ),
    );
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.showName = true,
    this.imageSize = 72,
    this.nameStyle,
    this.center = true,
  });

  final bool showName;
  final double imageSize;
  final TextStyle? nameStyle;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = BrandMark(size: imageSize);

    final children = <Widget>[
      logo,
      if (showName) ...[
        const SizedBox(height: 10),
        Text(
          _kBrandName,
          style: nameStyle ??
              theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
        ),
      ],
    ];

    return center
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
  }
}

