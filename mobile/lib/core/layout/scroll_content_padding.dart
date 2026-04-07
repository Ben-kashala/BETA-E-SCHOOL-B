import 'package:flutter/material.dart';

/// Marges pour listes et vues scrollables (mode edge-to-edge, barre du bas, confort tactile).
abstract final class ScrollContentPadding {
  static const double defaultTrailing = 40;

  /// [trailing] + [MediaQuery.padding.bottom] (déjà consommé par un ancêtre [SafeArea] si applicable).
  static EdgeInsets page(
    BuildContext context, {
    double horizontal = 16,
    double top = 16,
    double trailing = defaultTrailing,
  }) {
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      trailing + MediaQuery.paddingOf(context).bottom,
    );
  }
}
