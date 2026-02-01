import 'package:flutter/material.dart';

/// App-wide color constants
class AppColors {
  // Brand colors
  static const Color appRed = Color(0xFFAC1B22);
  static const Color appOffYellow = Color(0xFFFFC806);
  static const Color appGreen = Color(0xFF00A458); // True green
  static const Color appYellow = Color(0xFFFFC806); // Yellow for under review
  static const Color appBlack = Color(0xFF212121);
  static const Color appOffWhite = Color(0xFFF7F8F3);

  // Status colors
  static const Color statusGreen = Color(0xFF00A458); // Approved
  static const Color statusYellow = Color(0xFFFFC806); // Under Review
  static const Color statusRed = Color(0xFFAC1B22); // Flagged

  // Utility colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color transparent = Colors.transparent;
}

/// Extended color utilities
extension ColorUtilities on Color {
  /// Get opacity variant of color
  Color withCustomOpacity(double opacity) => withOpacity(opacity);
}

