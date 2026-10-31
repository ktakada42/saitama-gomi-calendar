import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/review_prompt_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ReviewPromptRepository> _openRepo([Map<String, Object>? values]) async {
  SharedPreferences.setMockInitialValues(values ?? {});
  return ReviewPromptRepository.open();
}

void main() {
  group('ReviewPromptRepository', () {
    test('初回起動時、初回起動日時とアクティブ日付が記録される', () async {
      final repo = await _openRepo();
      final now = DateTime(2026, 10, 1, 10, 0);

      expect(repo.readFirstLaunchTime(), isNull);
      expect(repo.readActiveDates(), isEmpty);

      await repo.recordLaunch(now: now);

      expect(repo.readFirstLaunchTime(), now);
      expect(repo.readActiveDates(), ['2026-10-01']);
    });

    test('同じ日に複数回起動してもアクティブ日数は重複して増えない', () async {
      final repo = await _openRepo();
      final time1 = DateTime(2026, 10, 1, 8, 30);
      final time2 = DateTime(2026, 10, 1, 20, 0);

      await repo.recordLaunch(now: time1);
      await repo.recordLaunch(now: time2);

      expect(repo.readFirstLaunchTime(), time1);
      expect(repo.readActiveDates(), ['2026-10-01']);
    });

    test('異なる日に起動するとアクティブ日数が追加される', () async {
      final repo = await _openRepo();

      await repo.recordLaunch(now: DateTime(2026, 10, 1));
      await repo.recordLaunch(now: DateTime(2026, 10, 2));
      await repo.recordLaunch(now: DateTime(2026, 10, 3));

      expect(repo.readActiveDates(), [
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
      ]);
    });

    group('shouldRequestReview', () {
      test('初回起動が記録されていない場合は false', () async {
        final repo = await _openRepo();
        expect(
          repo.shouldRequestReview(
            currentVersion: '1.3.0',
            now: DateTime(2026, 10, 20),
          ),
          isFalse,
        );
      });

      test('初回起動から14日未満の場合は false', () async {
        final repo = await _openRepo();
        final firstLaunch = DateTime(2026, 10, 1);

        // 7日アクティブにするが、経過日数は10日
        for (var i = 1; i <= 7; i++) {
          await repo.recordLaunch(now: DateTime(2026, 10, i));
        }

        final now = firstLaunch.add(const Duration(days: 10));
        expect(
          repo.shouldRequestReview(currentVersion: '1.3.0', now: now),
          isFalse,
        );
      });

      test('初回起動から14日以上でも、アクティブ日数が7日未満なら false', () async {
        final repo = await _openRepo();
        final firstLaunch = DateTime(2026, 10, 1);

        // 3日だけ起動
        await repo.recordLaunch(now: DateTime(2026, 10, 1));
        await repo.recordLaunch(now: DateTime(2026, 10, 2));
        await repo.recordLaunch(now: DateTime(2026, 10, 3));

        // 20日経過
        final now = firstLaunch.add(const Duration(days: 20));
        expect(
          repo.shouldRequestReview(currentVersion: '1.3.0', now: now),
          isFalse,
        );
      });

      test('初回起動から14日以上かつアクティブ7日以上なら true', () async {
        final repo = await _openRepo();
        final firstLaunch = DateTime(2026, 10, 1);

        // 7日間起動
        for (var i = 1; i <= 7; i++) {
          await repo.recordLaunch(now: DateTime(2026, 10, i));
        }

        // 14日経過後
        final now = firstLaunch.add(const Duration(days: 14));
        expect(
          repo.shouldRequestReview(currentVersion: '1.3.0', now: now),
          isTrue,
        );
      });

      test('レビュー依頼済みの場合、同一バージョンでは false', () async {
        final repo = await _openRepo();
        final firstLaunch = DateTime(2026, 10, 1);

        for (var i = 1; i <= 7; i++) {
          await repo.recordLaunch(now: DateTime(2026, 10, i));
        }

        final promptTime = firstLaunch.add(const Duration(days: 15));
        await repo.markReviewPrompted(currentVersion: '1.3.0', now: promptTime);

        // 100日経過後でも、同じバージョンなら再表示しない
        final later = promptTime.add(const Duration(days: 100));
        expect(
          repo.shouldRequestReview(currentVersion: '1.3.0', now: later),
          isFalse,
        );
      });

      test('レビュー依頼済みでも、90日以上経過かつバージョンアップしていれば true', () async {
        final repo = await _openRepo();
        final firstLaunch = DateTime(2026, 10, 1);

        for (var i = 1; i <= 7; i++) {
          await repo.recordLaunch(now: DateTime(2026, 10, i));
        }

        final promptTime = firstLaunch.add(const Duration(days: 15));
        await repo.markReviewPrompted(currentVersion: '1.3.0', now: promptTime);

        // バージョンアップしたが90日未満の場合は false（クーリングオフ）
        final day30 = promptTime.add(const Duration(days: 30));
        expect(
          repo.shouldRequestReview(currentVersion: '1.4.0', now: day30),
          isFalse,
        );

        // バージョンアップして90日経過した場合は true
        final day90 = promptTime.add(const Duration(days: 90));
        expect(
          repo.shouldRequestReview(currentVersion: '1.4.0', now: day90),
          isTrue,
        );
      });
    });
  });
}
