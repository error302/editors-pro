import 'package:flutter/material.dart';

/// The Editors Pro symbol, kept separate from the wordmark for small surfaces.
class AppBrandMark extends StatelessWidget {
  const AppBrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/icons/editors_pro_mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      );
}

/// Live lettering remains sharp and follows the active light or dark theme.
class AppBrandWordmark extends StatelessWidget {
  const AppBrandWordmark({super.key, this.fontSize = 24, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        'EDITORS PRO',
        semanticsLabel: 'Editors Pro',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: color ?? Theme.of(context).colorScheme.onSurface,
        ),
      );
}
