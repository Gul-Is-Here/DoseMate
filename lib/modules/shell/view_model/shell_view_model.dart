import 'package:get/get.dart';

/// The main tabs: Home, Medicines, Calendar, History and Settings.
/// Switching only changes [index]; every visited tab stays built, so its
/// controllers, listeners, scroll position and filters live on while
/// another tab is shown.
class ShellViewModel extends GetxController {
  ShellViewModel({int initialTab = 0}) : index = initialTab.obs {
    visited.add(initialTab);
  }

  static const tabCount = 5;
  static const historyTab = 3;

  final RxInt index;

  /// Tabs built so far. A tab is built on its first visit, so opening the
  /// app on Home doesn't start Calendar's or History's queries.
  final visited = <int>{}.obs;

  void select(int tab) {
    if (tab < 0 || tab >= tabCount || tab == index.value) return;
    visited.add(tab);
    index.value = tab;
  }
}
