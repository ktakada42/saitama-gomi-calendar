import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/features/shell/home_shell.dart';
import 'package:saitama_gomi/providers.dart';

import '../data/review_prompt_service_test.dart';
import '../support/test_app.dart';

void main() {
  group('HomeShell でのレビュー依頼', () {
    testWidgets('初回起動直後（タブ切り替え前）はレビュー依頼ダイアログは呼ばれない', (tester) async {
      final fakeReview = FakeInAppReview();

      await pumpApp(tester, const HomeShell(), inAppReview: fakeReview);

      expect(fakeReview.requestReviewCallCount, 0);
    });

    testWidgets('条件を満たした状態でタブを切り替えるとレビューダイアログが要求される', (tester) async {
      final fakeReview = FakeInAppReview();

      await pumpApp(tester, const HomeShell(), inAppReview: fakeReview);

      // 14日経過・7アクティブ日の条件を満たす保存データを用意
      final element = tester.element(find.byType(HomeShell));
      final container = ProviderScope.containerOf(element);
      final repo = await container.read(reviewPromptRepositoryProvider.future);
      final firstLaunch = DateTime.now().subtract(const Duration(days: 20));
      await repo.recordLaunch(now: firstLaunch);
      for (var i = 1; i <= 7; i++) {
        await repo.recordLaunch(now: firstLaunch.add(Duration(days: i)));
      }

      // 起動直後は 0 回
      expect(fakeReview.requestReviewCallCount, 0);

      // カレンダーのタブをタップしてタブを切り替える
      await tester.tap(find.text('カレンダー'));
      await tester.pumpAndSettle();

      // タブ切り替え後にリクエストされる
      expect(fakeReview.requestReviewCallCount, 1);
    });
  });
}
