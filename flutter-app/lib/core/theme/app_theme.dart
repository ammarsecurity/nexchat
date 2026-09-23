import 'package:flutter/material.dart';

import 'app_colors.dart';

const kAppFont = 'Cairo';

ThemeData buildAppTheme({required bool light}) {
  final c = light ? AppColors.light : AppColors.dark;
  final base = ThemeData(
    useMaterial3: true,
    brightness: light ? Brightness.light : Brightness.dark,
    fontFamily: kAppFont,
  );
  final textTheme = base.textTheme.apply(
    fontFamily: kAppFont,
    bodyColor: c.textPrimary,
    displayColor: c.textPrimary,
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: c.border),
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.bgPrimary,
    colorScheme: base.colorScheme.copyWith(
      primary: c.primary,
      secondary: c.primary,
      surface: c.bgCard,
      error: c.danger,
      onPrimary: Colors.white,
      onSurface: c.textPrimary,
    ),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.bgPrimary,
      foregroundColor: c.textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: textTheme.titleMedium?.copyWith(fontFamily: kAppFont, fontWeight: FontWeight.w700),
    ),
    dividerColor: c.border,
    cardColor: c.bgCard,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.bgElevated,
      hintStyle: TextStyle(fontFamily: kAppFont, color: c.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.primary, width: 1.5)),
      errorBorder: inputBorder.copyWith(borderSide: BorderSide(color: c.danger)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(fontFamily: kAppFont, fontSize: 15, color: c.textPrimary),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.bgCard,
      textStyle: TextStyle(fontFamily: kAppFont, fontSize: 15, color: c.textPrimary),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      titleTextStyle: TextStyle(fontFamily: kAppFont, fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary),
      contentTextStyle: TextStyle(fontFamily: kAppFont, fontSize: 15, color: c.textPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.bgElevated,
      contentTextStyle: TextStyle(color: c.textPrimary, fontFamily: kAppFont),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    ),
  );
}
