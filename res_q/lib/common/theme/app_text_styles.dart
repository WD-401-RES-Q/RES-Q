import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App-wide text style constants
class AppTextStyles {
  // Page titles
  static const TextStyle pageTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 45,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  // Headings
  static const TextStyle heading1 = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 24,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  static const TextStyle heading2 = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  static const TextStyle heading3 = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 16,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  // Labels and filter text
  static const TextStyle filterLabel = TextStyle(
    fontSize: 16,
    color: AppColors.appBlack,
    fontWeight: FontWeight.w900,
    fontFamily: 'Roboto',
  );

  static const TextStyle filterDropdown = TextStyle(
    fontSize: 13,
    color: AppColors.appBlack,
    fontFamily: 'Roboto',
  );

  // Report card styles
  static const TextStyle reportTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  static const TextStyle reportDescription = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle reportStatus = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle reportDate = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  // Dialog styles
  static const TextStyle dialogHeader = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 20,
    fontWeight: FontWeight.w900,
    color: AppColors.white,
  );

  static const TextStyle dialogQuestion = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 22,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle dialogReason = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle dialogLabel = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  // Comments page styles
  static const TextStyle commentPageTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.white,
  );

  static const TextStyle commentReportTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14,
    fontWeight: FontWeight.w900,
    color: AppColors.appBlack,
  );

  static const TextStyle commentReportStatus = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle commentFilterLabel = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle commentFilterDropdown = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle emptyCommentText = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  // Comment item styles
  static const TextStyle commentAuthor = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle commentTime = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle commentText = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle commentFlagCount = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  // Input styles
  static const TextStyle inputText = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.appBlack,
  );

  static const TextStyle inputHint = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle buttonText = TextStyle(
    fontFamily: 'RobotoCondensed',
    color: AppColors.white,
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  // Error text
  static const TextStyle errorText = TextStyle(
    fontFamily: 'RobotoCondensed',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.red,
  );

  // Auth page styles
  static const TextStyle authPageTitle = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.appBlack,
  );

  static const TextStyle authLabel = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.appBlack,
  );

  static const TextStyle authButton = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.white,
  );

  static const TextStyle authError = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.red,
  );

  static const TextStyle authLink = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.appBlue,
    decoration: TextDecoration.underline,
  );

  static const TextStyle authHelperText = TextStyle(
    fontFamily: 'Roboto',
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: Colors.grey,
  );
}
