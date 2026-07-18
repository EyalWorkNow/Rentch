import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Semantic icon registry — one place to see and swap the app's icons. Names are
/// by MEANING (not by icon pack), so the underlying set can change in one spot.
/// All IconsaxPlus names below are ones already used in the codebase.
abstract final class AppIcons {
  // Navigation
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData forward = IconsaxPlusLinear.arrow_right;
  static const IconData close = Icons.close_rounded;
  static const IconData closeCircle = IconsaxPlusLinear.close_circle;

  // Core actions
  static const IconData search = IconsaxPlusLinear.search_normal;
  static const IconData filter = IconsaxPlusLinear.setting_4;
  static const IconData add = Icons.add_rounded;
  static const IconData edit = IconsaxPlusLinear.edit_2;
  static const IconData trash = IconsaxPlusLinear.trash;
  static const IconData share = IconsaxPlusLinear.export_2;
  static const IconData check = IconsaxPlusLinear.tick_circle;
  static const IconData checkFilled = IconsaxPlusBold.tick_circle;

  // Entities
  static const IconData building = IconsaxPlusLinear.building;
  static const IconData buildings = IconsaxPlusLinear.buildings;
  static const IconData home = IconsaxPlusLinear.home;
  static const IconData location = IconsaxPlusLinear.location;
  static const IconData map = IconsaxPlusLinear.map_1;
  static const IconData gallery = IconsaxPlusLinear.gallery;
  static const IconData document = IconsaxPlusLinear.document_text;

  // People / social
  static const IconData user = IconsaxPlusLinear.user;
  static const IconData profile = IconsaxPlusLinear.profile_circle;
  static const IconData users = IconsaxPlusLinear.profile_2user;
  static const IconData chat = IconsaxPlusLinear.message;
  static const IconData heart = IconsaxPlusLinear.heart;

  // Status / misc
  static const IconData verified = IconsaxPlusLinear.shield_tick;
  static const IconData star = IconsaxPlusLinear.star_1;
  static const IconData flash = IconsaxPlusLinear.flash_1;
  static const IconData eye = IconsaxPlusLinear.eye;
  static const IconData layers = IconsaxPlusLinear.layer;
  static const IconData expand = IconsaxPlusLinear.maximize_3;
}
