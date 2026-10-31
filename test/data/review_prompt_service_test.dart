import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:saitama_gomi/data/review_prompt_repository.dart';
import 'package:saitama_gomi/data/review_prompt_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeInAppReview implements InAppReview {
  bool available = true;
  int requestReviewCallCount = 0;
  int openStoreListingCallCount = 0;
  String? lastAppStoreId;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requestReviewCallCount++;
  }

  @override
  Future<void> openStoreListing({
    String? appStoreId,
    String? microsoftStoreId,
  }) async {
    openStoreListingCallCount++;
    lastAppStoreId = appStoreId;
  }
}

void main() {
  group('ReviewPromptService', () {
    late ReviewPromptRepository repository;
    late FakeInAppReview fakeInAppReview;
    late ReviewPromptService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repository = await ReviewPromptRepository.open();
      fakeInAppReview = FakeInAppReview();
      service = ReviewPromptService(
        repository: repository,
        inAppReview: fakeInAppReview,
      );
    });

    test('条件を満たしていない場合、requestReview は呼ばれない', () async {
      final now = DateTime(2026, 10, 1);
      await service.recordLaunch(now: now);

      final result = await service.requestReviewIfEligible(
        currentVersion: '1.3.0',
        now: now,
      );

      expect(result, isFalse);
      expect(fakeInAppReview.requestReviewCallCount, 0);
      expect(repository.readLastPromptTime(), isNull);
    });

    test('条件を満たしており、かつ利用可能な場合は requestReview が呼ばれて記録される', () async {
      final firstLaunch = DateTime(2026, 10, 1);
      for (var i = 1; i <= 7; i++) {
        await service.recordLaunch(now: DateTime(2026, 10, i));
      }

      final targetDate = firstLaunch.add(const Duration(days: 14));
      final result = await service.requestReviewIfEligible(
        currentVersion: '1.3.0',
        now: targetDate,
      );

      expect(result, isTrue);
      expect(fakeInAppReview.requestReviewCallCount, 1);
      expect(repository.readLastPromptTime(), targetDate);
      expect(repository.readPromptedVersion(), '1.3.0');
    });

    test('条件を満たしていても isAvailable が false の場合は呼ばれず、記録もされない', () async {
      fakeInAppReview.available = false;

      final firstLaunch = DateTime(2026, 10, 1);
      for (var i = 1; i <= 7; i++) {
        await service.recordLaunch(now: DateTime(2026, 10, i));
      }

      final targetDate = firstLaunch.add(const Duration(days: 14));
      final result = await service.requestReviewIfEligible(
        currentVersion: '1.3.0',
        now: targetDate,
      );

      expect(result, isFalse);
      expect(fakeInAppReview.requestReviewCallCount, 0);
      expect(repository.readLastPromptTime(), isNull);
    });

    test(
      'openStoreListing が呼ばれると、既定の appStoreId を渡して inAppReview の openStoreListing を実行する',
      () async {
        await service.openStoreListing();
        expect(fakeInAppReview.openStoreListingCallCount, 1);
        expect(
          fakeInAppReview.lastAppStoreId,
          ReviewPromptService.defaultAppStoreId,
        );
      },
    );

    test('openStoreListing に appStoreId を明示した場合、それが優先される', () async {
      await service.openStoreListing(appStoreId: 'custom-id');
      expect(fakeInAppReview.openStoreListingCallCount, 1);
      expect(fakeInAppReview.lastAppStoreId, 'custom-id');
    });
  });
}
