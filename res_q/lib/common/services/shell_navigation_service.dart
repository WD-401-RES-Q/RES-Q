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
    openTab(tabIndex, communityReportId: communityReportId);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class SemiAdminShellNavigationCommand {
  const SemiAdminShellNavigationCommand({required this.tabIndex});

  final int tabIndex;
}

class SemiAdminShellNavigationService {
  static final ValueNotifier<SemiAdminShellNavigationCommand?> commands =
      ValueNotifier<SemiAdminShellNavigationCommand?>(null);

  static void openTab(int tabIndex) {
    commands.value = SemiAdminShellNavigationCommand(tabIndex: tabIndex);
  }

  static void popToRootAndOpenTab(BuildContext context, int tabIndex) {
    openTab(tabIndex);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
