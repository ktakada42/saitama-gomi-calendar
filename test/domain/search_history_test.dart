import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/search_history.dart';

void main() {
  group('record', () {
    test('新しい検索語が先頭に追加される', () {
      final history = const SearchHistory.empty()
          .record('ペットボトル')
          .record('乾電池');

      expect(history.queries, ['乾電池', 'ペットボトル']);
      expect(history.isEmpty, isFalse);
      expect(history.isNotEmpty, isTrue);
    });

    test('既にある語を記録すると重複せず先頭へ移る', () {
      final history = const SearchHistory.empty()
          .record('ペットボトル')
          .record('乾電池')
          .record('フライパン')
          .record('ペットボトル');

      expect(history.queries, ['ペットボトル', 'フライパン', '乾電池']);
    });

    test('前後の空白や改行は整えてから記録する', () {
      final history = const SearchHistory.empty()
          .record('  ペットボトル　')
          .record('ペット\nボトル');

      expect(history.queries, ['ペット ボトル', 'ペットボトル']);
    });

    test('空文字や空白のみの入力は記録しない', () {
      const empty = SearchHistory.empty();
      expect(empty.record(''), same(empty));
      expect(empty.record('   　\n '), same(empty));
    });

    test('最大件数（10件）を超えると古いものから落ちる', () {
      var history = const SearchHistory.empty();
      for (var i = 1; i <= 12; i++) {
        history = history.record('品目$i');
      }

      expect(history.queries, hasLength(SearchHistory.maxEntries));
      expect(history.queries.first, '品目12');
      expect(history.queries.last, '品目3');
      expect(history.queries, isNot(contains('品目1')));
      expect(history.queries, isNot(contains('品目2')));
    });

    test('上限ちょうどで既存の古い語を再検索すると、他の語を落とさず先頭へ移る', () {
      var history = const SearchHistory.empty();
      for (var i = 1; i <= SearchHistory.maxEntries; i++) {
        history = history.record('品目$i');
      }

      history = history.record('品目1');
      expect(history.queries, hasLength(SearchHistory.maxEntries));
      expect(history.queries.first, '品目1');
      expect(history.queries.last, '品目2');
    });

    test('文字数の上限（30文字）までは記録し、超える長文は記録しない', () {
      final exact = 'あ' * SearchHistory.maxQueryLength;
      final tooLong = 'あ' * (SearchHistory.maxQueryLength + 1);

      final history = const SearchHistory.empty().record(exact).record(tooLong);

      expect(history.queries, [exact]);
    });
  });

  group('remove', () {
    test('指定した語だけを取り除く', () {
      final history = const SearchHistory.empty()
          .record('ペットボトル')
          .record('乾電池')
          .record('フライパン')
          .remove('乾電池');

      expect(history.queries, ['フライパン', 'ペットボトル']);
    });

    test('最後の1件を消すと空に戻る', () {
      final history = const SearchHistory.empty()
          .record('ペットボトル')
          .remove('ペットボトル');

      expect(history, const SearchHistory.empty());
      expect(history.isEmpty, isTrue);
    });

    test('含まれない語を指定しても変わらない', () {
      final history = const SearchHistory.empty().record('ペットボトル');
      expect(history.remove('乾電池'), same(history));
    });
  });

  group('fromList', () {
    test('保存データの空文字・長文・重複・件数超過を整えて復元する', () {
      final raw = [
        '  ペットボトル ',
        '',
        '   ',
        'あ' * (SearchHistory.maxQueryLength + 5),
        'ペットボトル',
        for (var i = 1; i <= 15; i++) '品目$i',
      ];

      final history = SearchHistory.fromList(raw);
      expect(history.queries, hasLength(SearchHistory.maxEntries));
      expect(history.queries.first, 'ペットボトル');
      expect(history.queries[1], '品目1');
      expect(history.queries.last, '品目9');
    });
  });
}
