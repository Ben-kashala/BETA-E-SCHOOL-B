import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Breakpoints et marges pour les écrans comptable (téléphones étroits → tablettes).
abstract final class AccountantResponsive {
  static double widthOf(BuildContext context) => MediaQuery.sizeOf(context).width;

  static bool isCompact(BuildContext context) => widthOf(context) < 400;

  static bool isTabletUp(BuildContext context) => widthOf(context) >= 600;

  /// Marges latérales du contenu (liste / scroll).
  static double pagePaddingH(BuildContext context) {
    final w = widthOf(context);
    if (w >= 900) return 20;
    if (w >= 600) return 16;
    return 12;
  }

  static EdgeInsets pageInsets(
    BuildContext context, {
    double top = 16,
    double bottomExtra = 24,
  }) {
    final h = pagePaddingH(context);
    return EdgeInsets.fromLTRB(
      h,
      top,
      h,
      bottomExtra + MediaQuery.paddingOf(context).bottom,
    );
  }

  /// Cellules de tableaux : moins de padding sur très petit écran.
  static double cellPaddingH(BuildContext context) => isCompact(context) ? 6 : 10;

  static double cellPaddingV(BuildContext context) => isCompact(context) ? 8 : 10;

  /// Largeur du bloc scrollable horizontal : au moins [minScrollWidth], ou la largeur utile si plus grande.
  static double tableScrollInnerWidth(
    BuildContext context, {
    required double minScrollWidth,
  }) {
    final avail = widthOf(context) - pagePaddingH(context) * 2;
    return math.max(minScrollWidth, avail);
  }

  static double paymentsTableMinWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < 360) return 660;
    if (w < 420) return 720;
    if (w < 520) return 820;
    return 900;
  }

  static double expensesTableMinWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < 360) return 680;
    if (w < 420) return 780;
    if (w < 520) return 920;
    return 1020;
  }

  static double caisseTableMinWidth(BuildContext context) {
    final w = widthOf(context);
    if (w < 360) return 700;
    if (w < 420) return 800;
    if (w < 520) return 960;
    return 1080;
  }

  static int dashboardGridColumns(BuildContext context) {
    final w = widthOf(context);
    if (w >= 820) return 3;
    if (w >= 360) return 2;
    return 1;
  }

  static double dashboardGridAspectRatio(BuildContext context) {
    switch (dashboardGridColumns(context)) {
      case 3:
        return 1.05;
      case 2:
        return 1.12;
      default:
        return 2.25;
    }
  }

  static double appBarTitleFontSize(BuildContext context) =>
      isCompact(context) ? 17.0 : 20.0;

  static double bodyTitleFontSize(BuildContext context) =>
      isCompact(context) ? 16.0 : 18.0;
}
