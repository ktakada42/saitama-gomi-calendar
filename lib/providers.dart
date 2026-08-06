import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/area_catalog.dart';
import 'data/settings_repository.dart';
import 'domain/collection_area.dart';
import 'domain/collection_calendar.dart';

final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) => SettingsRepository.open(),
);

final areaCatalogProvider = FutureProvider<AreaCatalog>(
  (ref) => AreaCatalog.load(),
);

/// 設定済みの地区。null は「まだ設定していない」＝初回起動。
class SelectedArea extends AsyncNotifier<CollectionArea?> {
  @override
  Future<CollectionArea?> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return repository.readArea();
  }

  Future<void> save(CollectionArea area) async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.writeArea(area);
    state = AsyncData(area);
  }

  Future<void> clear() async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.clear();
    state = const AsyncData(null);
  }
}

final selectedAreaProvider =
    AsyncNotifierProvider<SelectedArea, CollectionArea?>(SelectedArea.new);

/// 外観設定（ライト／ダーク／システム）。デフォルトはライトモード。
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final repository = await ref.watch(settingsRepositoryProvider.future);
    return repository.readThemeMode();
  }

  Future<void> save(ThemeMode mode) async {
    final repository = await ref.read(settingsRepositoryProvider.future);
    await repository.writeThemeMode(mode);
    state = AsyncData(mode);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// 今日の日付（時刻は落としてある）。
///
/// `DateTime.now()` を画面から直接呼ばずここに集約しておくと、
/// テストで `overrideWithValue` して任意の日付の表示を確認できる。
final todayProvider = Provider<DateTime>(
  (ref) => CollectionCalendar.dateOnly(DateTime.now()),
);

/// 設定済み地区のカレンダー。地区が未設定なら null。
final calendarProvider = Provider<CollectionCalendar?>((ref) {
  final area = ref.watch(selectedAreaProvider).value;
  return area == null ? null : CollectionCalendar(area);
});
