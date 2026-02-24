import 'package:flutter/material.dart';

class MainShellNavigationCommand {
  const MainShellNavigationCommand({
    required this.tabIndex,
    this.communityReportId,
  });

  final int tabIndex;
  final String? communityReportId;
}

class MainShellNavigationService {
  static final ValueNotifier<MainShellNavigationCommand?> commands =
      ValueNotifier<MainShellNavigationCommand?>(null);

  static void openTab(int tabIndex, {String? communityReportId}) {
    commands.value = MainShellNavigationCommand(
      tabIndex: tabIndex,
      communityReportId: communityReportId,
    );
  }

  static void popToRootAndOpenTab(
    BuildContext context,
    int tabIndex, {
    String? communityReportId,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.popUntil((route) => route.isFirst);
    openTab(tabIndex, communityReportId: communityReportId);
  }
}

class ResponderShellNavigationCommand {
  const ResponderShellNavigationCommand({
    required this.tabIndex,
    this.reportId,
  });

  final int tabIndex;
  final String? reportId;
}

class ResponderShellNavigationService {
  static final ValueNotifier<ResponderShellNavigationCommand?> commands =
      ValueNotifier<ResponderShellNavigationCommand?>(null);

  static void openTab(int tabIndex, {String? reportId}) {
    commands.value = ResponderShellNavigationCommand(
      tabIndex: tabIndex,
      reportId: reportId,
    );
  }

  static void popToRootAndOpenTab(
    BuildContext context,
    int tabIndex, {
    String? reportId,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.popUntil((route) => route.isFirst);
    openTab(tabIndex, reportId: reportId);
  }
}
