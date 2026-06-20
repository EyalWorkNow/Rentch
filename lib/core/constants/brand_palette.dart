import 'package:flutter/material.dart';

/// Per-account-type accent palette. Tenants and landlords keep the signature
/// teal; real-estate **brokers** get a distinct premium indigo identity so the
/// app visibly reflects which kind of account is signed in (theme colours, nav,
/// buttons, badges).
class BrandPalette {
  const BrandPalette({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.primaryLight2,
    required this.accountLabel,
  });

  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color primaryLight2;
  final String accountLabel;

  /// Default teal identity (tenants + private landlords).
  static const BrandPalette teal = BrandPalette(
    primary: Color(0xFF13BEC9),
    primaryDark: Color(0xFF0D96A0),
    primaryLight: Color(0xFF5AD4DC),
    primaryLight2: Color(0xFFE6F9FB),
    accountLabel: '',
  );

  /// Premium indigo identity for real-estate brokers.
  static const BrandPalette broker = BrandPalette(
    primary: Color(0xFF6C5CE7),
    primaryDark: Color(0xFF5346C9),
    primaryLight: Color(0xFF9D90FF),
    primaryLight2: Color(0xFFEEEBFF),
    accountLabel: 'מתווך נדל״ן',
  );

  static BrandPalette forRole(String role) =>
      role == 'broker' ? broker : teal;
}
