import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/app_shell.dart';
import '../../calendar/views/calendar_view.dart';
import '../../history/views/history_view.dart';
import '../../home/views/home_view.dart';
import '../../medicines/views/medicines_view.dart';
import '../../settings/views/settings_view.dart';
import '../view_model/shell_view_model.dart';

class MainShellView extends GetView<ShellViewModel> {
  const MainShellView({super.key});

  static Widget _tab(int i) => switch (i) {
    0 => const HomeView(),
    1 => const MedicinesView(),
    2 => const CalendarView(),
    3 => const HistoryView(),
    _ => const SettingsView(),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Obx(() {
        final current = controller.index.value;
        final visited = controller.visited;
        return IndexedStack(
          index: current,
          children: [
            for (var i = 0; i < ShellViewModel.tabCount; i++)
              // Hidden tabs keep their state but don't tick or take focus.
              TickerMode(
                enabled: i == current,
                child: FocusTraversalGroup(
                  child: ExcludeFocus(
                    excluding: i != current,
                    child: visited.contains(i)
                        ? KeyedSubtree(key: ValueKey('tab-$i'), child: _tab(i))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        );
      }),
      bottomNavigationBar: Obx(
        () => AppBottomNav(
          activeIndex: controller.index.value,
          onSelect: controller.select,
        ),
      ),
    );
  }
}
