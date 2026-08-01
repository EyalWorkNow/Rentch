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
    primary: Color(0xFF2563EB),
    primaryDark: Color(0xFF1D4ED8),
    primaryLight: Color(0xFF60A5FA),
    primaryLight2: Color(0xFFEFF6FF),
    accountLabel: '',
  );

  /// Premium black identity for real-estate brokers.
  static const BrandPalette broker = BrandPalette(
    primary: Color(0xFF000000),
    primaryDark: Color(0xFF000000),
    primaryLight: Color(0xFF333333),
    primaryLight2: Color(0xFFEDEDED),
    accountLabel: 'מתווך נדל״ן',
  );

  static BrandPalette forRole(String role) =>
      role == 'broker' ? broker : teal;
}
