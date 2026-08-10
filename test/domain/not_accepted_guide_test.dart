import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/domain/not_accepted_guide.dart';

/// 市では収集できないものの持って行き先の検査。
///
/// 行き先を間違えると、持って行った先で断られる。往復させることになるので、
/// 対応づけは1件ずつ縛る。
void main() {
  late NotAcceptedGuide guide;
  late Map<String, String> dictionary;

  setUpAll(() {
    guide = NotAcceptedGuide.fromJson(
      jsonDecode(File('assets/data/not_accepted.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final raw = File('assets/data/dictionary.json').readAsStringSync();
    dictionary = {
      for (final item
          in (jsonDecode(raw) as Map<String, dynamic>)['items'] as List)
        (item as Map<String, dynamic>)['name'] as String:
            item['category'] as String,
    };
  });

  group('同梱したデータ', () {
    test('連絡先には電話番号かURLがある', () {
      // 名前だけ出しても、そこから先へ進めない。
      for (final destination in guide.destinations) {
        for (final contact in destination.contacts) {
          expect(
            contact.phone.isNotEmpty || contact.url.isNotEmpty,
            isTrue,
            reason: '${destination.id} / ${contact.name}',
          );
        }
      }
    });

    test('電話番号は市の資料どおり', () {
      final byId = {for (final d in guide.destinations) d.id: d};
      expect(byId['homeAppliance']!.contacts.first.phone, '0120-319640');
      expect(byId['pc']!.contacts.first.phone, '03-5282-7685');
      expect(byId['motorcycle']!.contacts.first.phone, '050-3000-0727');
      expect(byId['extinguisher']!.contacts.first.phone, '03-5829-6773');
      expect(byId['licensed']!.contacts.first.phone, '048-685-8161');
      expect(byId['freon']!.contacts.first.phone, '048-883-7075');
    });

    test('どの行き先にも、当てはまるものの説明がある', () {
      for (final destination in guide.destinations) {
        expect(destination.title, isNotEmpty, reason: destination.id);
        expect(destination.body, isNotEmpty, reason: destination.id);
      }
    });

    test('行き先のidは重複しない', () {
      final ids = guide.destinations.map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('出典が示されている', () {
      expect(guide.source, contains('P10'));
      expect(guide.sourceUrl, startsWith('https://www.city.saitama.lg.jp/'));
    });
  });

  group('品目から行き先を引く', () {
    test('家電リサイクルの対象は、券センターへ', () {
      for (final name in ['テレビ', '液晶テレビ', 'エアコン', '洗濯機', '冷蔵庫']) {
        expect(guide.destinationFor(name)?.id, 'homeAppliance', reason: name);
      }
    });

    test('パソコン・バイク・消火器は、それぞれの窓口へ', () {
      expect(guide.destinationFor('パソコン本体（ノート型も）')?.id, 'pc');
      expect(guide.destinationFor('パソコンディスプレイ')?.id, 'pc');
      expect(guide.destinationFor('オートバイ（原付含む）')?.id, 'motorcycle');
      expect(guide.destinationFor('原動機付自転車')?.id, 'motorcycle');
      expect(guide.destinationFor('消火器')?.id, 'extinguisher');
    });

    test('破砕できないものは、許可業者へ', () {
      for (final name in ['金庫', '車の部品', 'モーター類', '農機具類']) {
        expect(guide.destinationFor(name)?.id, 'licensed', reason: name);
      }
    });

    test('危ないものは、まとめて販売店・専門業者へ', () {
      for (final name in ['ガソリン', '灯油', '農薬', 'プロパンガスボンベ', '炭酸ボンベ']) {
        expect(guide.destinationFor(name)?.id, 'dangerous', reason: name);
      }
    });

    test('注射針は医療機関へ返す', () {
      expect(guide.destinationFor('注射針')?.id, 'medical');
    });

    test('似た名前の別物を巻き込まない', () {
      // 部分一致で拾うと、ここが全部おかしくなる。
      // 「石」は「石こうボード」にも「消火器」にも含まれる。
      const shouldNotMatch = {
        // もえないごみ。「ボンベ」を含まないが「消火器」と紛れやすい。
        '殺虫剤（スプレーかん)': 'hazardous',
        // 電池回収ボックス行き。パソコンの窓口ではない。
        'モバイルバッテリー': 'battery',
        // もえるごみ。「灯油」を含む「灯油タンク」とは別。
        '歯ブラシ': 'burnable',
      };
      for (final entry in shouldNotMatch.entries) {
        expect(
          guide.destinationFor(entry.key),
          isNull,
          reason: '${entry.key}（${entry.value}）',
        );
      }
    });

    test('収集できるものには、行き先を出さない', () {
      // ここが漏れると、ふつうに収集所へ出せるものを業者へ持って行かせる。
      for (final entry in dictionary.entries) {
        if (entry.value == 'notAccepted') continue;
        expect(
          guide.destinationFor(entry.key),
          isNull,
          reason: '${entry.key} は ${entry.value}',
        );
      }
    });

    test('対応表に書いた品目は、すべて早見表の「収集できないもの」', () {
      // 書き間違えると誰にも当たらない対応表になり、気づけない。
      for (final destination in guide.destinations) {
        for (final applied in destination.appliesTo) {
          expect(
            dictionary[applied],
            'notAccepted',
            reason: '${destination.id} → $applied',
          );
        }
      }
    });

    test('収集できない35件のうち、行き先が決まっていないものを把握している', () {
      final unmapped = [
        for (final entry in dictionary.entries)
          if (entry.value == 'notAccepted' &&
              guide.destinationFor(entry.key) == null)
            entry.key,
      ];
      // 冊子P10・P11に窓口の記載が無いものだけが残る。
      // 増えていたら、対応づけの漏れを疑う。
      expect(unmapped, isEmpty, reason: unmapped.join('、'));
    });
  });
}
