import 'package:flutter/material.dart';

/// Utility responsif yang menghadirkan breakpoint dan ukuran layout/font
/// sesuai lebar layar. Cocok untuk mobile, tablet, dan desktop.
class Responsive {
  final double width;
  final double height;
  final EdgeInsets viewPadding;

  const Responsive._({
    required this.width,
    required this.height,
    required this.viewPadding,
  });

  factory Responsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Responsive._(
      width: mq.size.width,
      height: mq.size.height,
      viewPadding: mq.viewPadding,
    );
  }

  bool get isDesktop => width >= 1024;
  bool get isTablet => width >= 600 && width < 1024;
  bool get isMobile => width < 600;
  bool get isMobilePortrait => isMobile && height > width;

  EdgeInsets get pagePadding {
    if (isDesktop) return const EdgeInsets.all(28);
    if (isTablet) return const EdgeInsets.all(20);
    return const EdgeInsets.symmetric(horizontal: 14, vertical: 16);
  }

  double get hPad {
    if (isDesktop) return 28;
    if (isTablet) return 20;
    return 14;
  }

  EdgeInsets get cardPadding {
    if (isDesktop)
      return const EdgeInsets.symmetric(horizontal: 18, vertical: 16);
    if (isTablet)
      return const EdgeInsets.symmetric(horizontal: 14, vertical: 13);
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 11);
  }

  double fontSize(double base) {
    if (isDesktop) return base;
    if (isTablet) return base - 0.5;
    return base - 1.5;
  }

  double get titleFontSize {
    if (isDesktop) return 20;
    if (isTablet) return 18;
    return 16;
  }

  double get sectionFontSize {
    if (isDesktop) return 15;
    if (isTablet) return 14;
    return 13;
  }

  double get topBarHeight {
    if (isDesktop) return 68;
    if (isTablet) return 60;
    return 56;
  }

  double get topBarHPad {
    if (isDesktop) return 28;
    if (isTablet) return 18;
    return 14;
  }

  bool get topBarShowEmail => !isMobile;

  int get statCardCols {
    if (width > 900) return 3;
    if (width > 500) return 3;
    return 2;
  }

  double get statCardAspectRatio {
    if (isDesktop) return 2.4;
    if (isTablet) return 1.9;
    if (width > 400) return 2.2;
    return 1.8;
  }

  double get searchWidth {
    if (isDesktop) return 300;
    if (isTablet) return 220;
    return double.infinity;
  }

  double get dialogMaxWidth {
    if (isDesktop) return 640;
    if (isTablet) return 560;
    return width - 32;
  }

  double get dialogHPad {
    if (isDesktop) return 28;
    if (isTablet) return 22;
    return 16;
  }

  EdgeInsets get dialogContentPad {
    if (isDesktop) return const EdgeInsets.fromLTRB(28, 20, 28, 28);
    if (isTablet) return const EdgeInsets.fromLTRB(22, 16, 22, 22);
    return const EdgeInsets.fromLTRB(16, 14, 16, 18);
  }

  int columns({int desktop = 4, int tablet = 3, int mobile = 2}) {
    if (isDesktop) return desktop;
    if (isTablet) return tablet;
    return mobile;
  }

  double get fieldHeight {
    if (isDesktop) return 44;
    if (isTablet) return 42;
    return 44;
  }

  double get buttonHeight {
    if (isDesktop) return 44;
    if (isTablet) return 42;
    return 46;
  }

  double get buttonFontSize {
    if (isDesktop) return 13.5;
    if (isTablet) return 13;
    return 13;
  }

  double get iconMd {
    if (isDesktop) return 22;
    if (isTablet) return 20;
    return 20;
  }

  double get iconSm {
    if (isDesktop) return 18;
    if (isTablet) return 16;
    return 16;
  }

  /// Sidebar responsive width when expanded
  double get sidebarExpandedWidth {
    if (width >= 1400) return 240;
    if (width >= 1200) return 220;
    if (width >= 1024) return 200;
    if (width >= 800) return 180;
    return 160;
  }

  /// Sidebar collapsed/icon-only width
  double get sidebarCollapsedWidth {
    if (isDesktop) return 72;
    return 64;
  }

  EdgeInsets get safeBottom => EdgeInsets.only(bottom: viewPadding.bottom);
}
