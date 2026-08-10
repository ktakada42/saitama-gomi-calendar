import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/oversized_guide.dart';

/// 粗大ごみの案内の検査。
///
/// 金額は利用者が実際に払う額なので、写し間違いが直接の損害になる。
/// 冊子（P9）の記載と突き合わせた値を、ここに置いて動かないようにする。
void main() {
  late OversizedGuide guide;

  setUpAll(() {
    final raw = File('assets/data/oversized.json').readAsStringSync();
    guide = OversizedGuide.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  group('同梱したデータ', () {
    test('出す方法は持込みと戸別収集の2つ', () {
      expect(guide.methods.map((m) => m.id), ['dropOff', 'doorToDoor']);
    });

    test('どの方法にも、料金と申込み先と受付時間がある', () {
      // ひとつでも欠けると「で、どうすればいいのか」が分からない画面になる。
      for (final method in guide.methods) {
        expect(method.fee, isNotEmpty, reason: method.id);
        expect(method.phone, isNotEmpty, reason: method.id);
        expect(method.phoneHours, isNotEmpty, reason: method.id);
        expect(method.url, startsWith('https://'), reason: method.id);
      }
    });

    test('電話番号は市の資料どおり', () {
      final byId = {for (final m in guide.methods) m.id: m};
      expect(byId['dropOff']!.phone, '050-3033-8229');
      expect(byId['doorToDoor']!.phone, '048-878-0053');
    });

    test('個別料金は7品目', () {
      expect(guide.specialFees.items, hasLength(7));
    });

    test('個別料金は冊子P9の額と一致する', () {
      final byName = {
        for (final f in guide.specialFees.items)
          f.name: (f.dropOffYen, f.doorToDoorYen),
      };
      expect(byName['スプリング入りマットレス'], (1650, 2200));
      expect(byName['スプリング入りソファー（二人がけ以上用）'], (1650, 2200));
      expect(byName['スプリング入りソファー（一人がけ用）'], (550, 1100));
      expect(byName['物干し台（コンクリート台つき・1個）'], (550, 1100));
      expect(byName['バッテリー（鉛バッテリー）'], (550, 1100));
      expect(byName['タイヤ（1本）'], (550, 1100));
      expect(byName['ホイール（1本）'], (550, 1100));
    });

    test('取りに来てもらうほうが、持ち込むより高い', () {
      // 逆になっていたら写し間違い。冊子でも一貫してこの向き。
      for (final fee in guide.specialFees.items) {
        expect(
          fee.doorToDoorYen,
          greaterThanOrEqualTo(fee.dropOffYen),
          reason: fee.name,
        );
      }
    });

    test('2m以上は市では扱えないことが書いてある', () {
      // 大きいものほど粗大ごみだと思われがちだが、大きすぎると対象外になる。
      expect(guide.definition.tooLarge, contains('2m'));
    });

    test('戸別収集の手順は5つ', () {
      expect(guide.steps, hasLength(5));
      for (final step in guide.steps) {
        expect(step.title, isNotEmpty);
        expect(step.body, isNotEmpty);
      }
    });

    test('出典が示されている', () {
      expect(guide.source, contains('P9'));
      expect(guide.sourceUrl, startsWith('https://www.city.saitama.lg.jp/'));
    });
  });

  group('品目から個別料金を引く', () {
    test('早見表の書き方で引ける', () {
      // 早見表は「マットレス（スプリングあり）」、料金表は
      // 「スプリング入りマットレス」。書き方が違うので対応表で結ぶ。
      expect(guide.feeFor('マットレス（スプリングあり）')?.dropOffYen, 1650);
      expect(guide.feeFor('スプリング入りマットレス')?.dropOffYen, 1650);
      expect(guide.feeFor('タイヤ（乗用車・バイク用）')?.dropOffYen, 550);
      expect(guide.feeFor('バッテリー（乗用車・バイク用）')?.dropOffYen, 550);
      expect(guide.feeFor('物干し台（コンクリート台つき）')?.dropOffYen, 550);
    });

    test('似た名前でも、当てはまらないものには出さない', () {
      // 名前で機械的に照合すると、ここが全部誤って料金付きになる。
      // 金額の誤りは利用者の損害になるので、対応表に無いものには出さない。
      const shouldNotMatch = [
        // もえるごみ。「タイヤ」を含むが、粗大ごみの550円とは無関係。
        '自転車のタイヤ・チューブ（ゴム製）',
        // 粗大ごみだが、個別料金の対象ではない。
        'タイヤチェーン（材質に関係なく）',
        // 電池回収ボックス行き。鉛バッテリーの料金は当てはまらない。
        'バッテリー（電動アシスト自転車用）',
        'モバイルバッテリー',
        // スプリングが無いので、スプリング入りの額にはならない。
        'マットレス（スプリングなし）',
        'ソファー（スプリングなし）',
        // 「物干し竿」は「物干し台」とは別物。
        '物干し竿',
      ];
      for (final name in shouldNotMatch) {
        expect(guide.feeFor(name), isNull, reason: name);
      }
    });

    test('額が定まらないものは対応づけない', () {
      // 早見表のソファーは一人がけ／二人がけを分けていない。
      // 1,650円か550円かを決められないので、料金表を見てもらう。
      expect(guide.feeFor('ソファー（スプリング入り）'), isNull);
      expect(guide.feeFor('ソファーベッド'), isNull);
    });

    test('大きさで決まるものは null', () {
      for (final name in ['たんす', '自転車', '食器棚', 'サーフボード', '']) {
        expect(guide.feeFor(name), isNull, reason: name);
      }
    });

    test('対応表に書いた品目は、すべて早見表に実在する', () {
      // 書き間違えると、誰にも当たらない対応表になる。気づけないので縛る。
      final raw = File('assets/data/dictionary.json').readAsStringSync();
      final names = {
        for (final item
            in (jsonDecode(raw) as Map<String, dynamic>)['items'] as List)
          (item as Map<String, dynamic>)['name'] as String,
      };
      for (final fee in guide.specialFees.items) {
        for (final applied in fee.appliesTo) {
          expect(names, contains(applied), reason: '${fee.name} → $applied');
        }
      }
    });
  });
}
