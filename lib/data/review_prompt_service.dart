import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

import 'review_prompt_repository.dart';

/// アプリ内レビュー依頼（OS標準ダイアログ）の制御を行うサービス。
///
/// 利用者が一定期間アプリを継続利用しており、不満なく使えているタイミングで
/// OS標準のレビュー依頼（SKStoreReviewController / In-App Review API）を呼び出す。
class ReviewPromptService {
  ReviewPromptService({
    required this.repository,
    this.appStoreId = defaultAppStoreId,
    @visibleForTesting InAppReview? inAppReview,
  }) : _inAppReview = inAppReview ?? InAppReview.instance;

  /// App Store でのアプリID。
  /// iOS / macOS では openStoreListing 時にアプリIDが必須となる。
  static const String defaultAppStoreId = '6798954011';

  final ReviewPromptRepository repository;
  final String? appStoreId;
  final InAppReview _inAppReview;

  /// アプリ起動時に呼び出し、起動日を記録する。
  Future<void> recordLaunch({DateTime? now}) =>
      repository.recordLaunch(now: now);

  /// 条件を満たしている場合にOS標準のレビューダイアログを要求する。
  ///
  /// ダイアログの表示可否はOS側のクォータ（年あたりの上限）や利用状況によって
  /// 決定されるため、要求してもダイアログが出ない場合があるが、
  /// 過剰な要求を避けるため成功時にはリクエスト済みとして記録する。
  ///
  /// レビュー要求を行った（条件を満たして呼び出した）場合は true、
  /// 条件を満たさなかった／利用不可だった場合は false を返す。
  Future<bool> requestReviewIfEligible({
    required String currentVersion,
    DateTime? now,
  }) async {
    final shouldPrompt = repository.shouldRequestReview(
      currentVersion: currentVersion,
      now: now,
    );
    if (!shouldPrompt) {
      return false;
    }

    final isAvailable = await _inAppReview.isAvailable();
    if (!isAvailable) {
      return false;
    }

    await repository.markReviewPrompted(
      currentVersion: currentVersion,
      now: now,
    );
    await _inAppReview.requestReview();
    return true;
  }

  /// ストア（App Store / Google Play）のアプリページを開く。
  ///
  /// 利用者が設定画面などから自発的に評価を行いたいときに使用する。
  Future<void> openStoreListing({String? appStoreId}) =>
      _inAppReview.openStoreListing(appStoreId: appStoreId ?? this.appStoreId);
}
