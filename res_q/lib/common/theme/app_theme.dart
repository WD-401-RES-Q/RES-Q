import 'package:flutter/material.dart';

class AppColors {
  static const appRed = Color(0xFFAC1B22);
  static const appOffYellow = Color(0xFFFFC806);
  static const appGreen = Color(0xFF4CAF50);
  static const appYellow = Color(0xFFF5F520);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const appBrightWhite = Color(0xFFFEFEFD);
}

class AppText {
  // Uses font families declared in pubspec.yaml
  static const heading = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  static const subheading = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.appBlack,
  );

  static const body = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const bodyCondensed = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const badge = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: AppColors.appBlack,
  );

  static const caption = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class AppTheme {
  // Brand colors - direct access
  static const appRed = Color(0xFFAC1B22);
  static const appOffYellow = Color(0xFFFFC806);
  static const appBlack = Color(0xFF212121);
  static const appOffWhite = Color(0xFFF7F8F3);
  static const appBrightWhite = Color(0xFFFEFEFD);

  static final ButtonStyle pillOutlineButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: AppColors.appRed,
    backgroundColor: Colors.white,
    side: const BorderSide(color: AppColors.appRed, width: 1.2),
    shape: const StadiumBorder(),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    textStyle: const TextStyle(
      fontFamily: 'RobotoCondensed',
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ),
  );

  static ThemeData theme = ThemeData(
    primaryColor: AppColors.appRed,
    scaffoldBackgroundColor: AppColors.appOffWhite,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.appRed,
      primary: AppColors.appRed,
      secondary: AppColors.appYellow,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      titleTextStyle: AppText.subheading,
      contentTextStyle: AppText.body,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      elevation: 8,
      showDragHandle: false,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.appRed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.appBlack),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.appRed,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    ),
  );
}


