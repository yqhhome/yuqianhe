import 'package:flutter/material.dart';

const _kBrandName = '宇千鹤';
const _kBrandLogoAsset = 'assets/images/yuqianhe_logo.png';

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
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(imageSize * 0.22),
      child: Image.asset(
        _kBrandLogoAsset,
        width: imageSize,
        height: imageSize,
        fit: BoxFit.cover,
      ),
    );

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

