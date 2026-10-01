import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';
import 'package:saitama_gomi/domain/waste_note.dart';

void main() {
  late WasteDictionary dictionary;

  setUpAll(() {
    dictionary = WasteDictionary.fromJson(
      jsonDecode(File('assets/data/dictionary.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  test('注意点に冊子向けの印が残っていない', () {
    // 「★2」「▶P9参照」は紙の冊子を前提にした書き方で、そのまま出しても
    // 意味が通らない。抽出のときに切り出してmarksへ移してある。
    for (final item in dictionary.items) {
      expect(item.note, isNot(contains('★')), reason: item.name);
      expect(item.note, isNot(contains('参照')), reason: item.name);
    }
  });

  test('切り出した印はすべて説明を持っている', () {
    final ids = {for (final item in dictionary.items) ...item.markIds};
    expect(ids, isNotEmpty);
    for (final id in ids) {
      expect(NoteMark.resolve([id]), hasLength(1), reason: '$id の説明がない');
    }
  });

  test('印を切り出しても注意点の本文は失われていない', () {
    // 「★290㎝未満にしばる」のように印と本文がつながっている行がある。
    // ★2 だけを取り、本文は残す。
    final carpet = dictionary.items.firstWhere((i) => i.name == 'カーペット');
    expect(carpet.note, '90㎝未満にしばる');
    expect(carpet.markIds, ['star2']);
  });

  test('区分の名前を含む注意点が落ちていない', () {
    // 表の上の凡例（「もえるごみ」「もえないごみ」…）を落とすときに、
    // 同じ言葉を含む注意点まで語ごと落としていた。水筒の「プラスチック製は
    // もえるごみ」のように、区分が逆になる但し書きが90件ほど消えていた。
    String noteOf(String name) =>
        dictionary.items.firstWhere((i) => i.name == name).note;
    expect(noteOf('ハンガー'), '金属製は、もえないごみ');
    expect(noteOf('水筒'), 'プラスチック製はもえるごみ');
    expect(noteOf('アイロン'), contains('もえないごみとしても出せます'));
    expect(noteOf('てんぷら油'), contains('※液体のものは、排出禁止'));
    expect(noteOf('扇風機'), '充電式のものは、小型家電回収ボックスへ');
  });

  group('但し書きの切れ目', () {
    String noteOf(String name) =>
        dictionary.items.firstWhere((i) => i.name == name).note;

    test('別々の但し書きは改行で分かれている', () {
      // 区切らずに繋ぐと、どこで文が切れるのか読めない。
      expect(noteOf('おもちゃ'), '金属製は、もえないごみ\n電池が外れないものは、小型家電回収ボックスへ');
      expect(noteOf('アイロン'), '回収ボックスヘ\nもえないごみとしても出せます');
      expect(noteOf('自転車'), '直接持込みまたは戸別収集\n90㎝未満なら、もえないごみ');
    });

    test('同じ行に横に並べてある但し書きも分かれている', () {
      expect(noteOf('ふとん'), '90㎝未満にしばる\n1回に1枚まで');
      expect(noteOf('血圧計'), '回収ボックスへ\nもえないごみとしても出せます\n水銀を使用している場合は有害危険ごみ');
      // 「〜まで」は文の終わり。次の行へ続いているのではない。
      expect(
        noteOf('かわら'),
        '直接持込みまたは戸別収集\n直接持込みの場合は1日につき10個まで\n戸別収集の場合は4枚1品、最大8枚まで',
      );
    });

    test('欄に収まらず折り返した文は、途中で切らない', () {
      // 冊子では2行に折り返してあるが、1つの文。
      expect(noteOf('歯ブラシ'), '電動歯ブラシは電池を抜いて、回収ボックスへ');
      expect(noteOf('ベニヤ板'), '厚さ10cm未満で長さ90cm未満の場合のみ');
      expect(noteOf('ペットボトル'), '中をすすいで（フタとラベルははずして容器包装プラスチックへ）');
      expect(noteOf('サイリウム（ケミカルライト）'), '電池式ペンライトは、電池を外して回収ボックスまたはもえないごみへ');
      // カタカナ語の途中で折り返している（「フロンガ／スを回収済み」）。
      expect(noteOf('冷風機'), contains('フロンガスを回収済みである'));
      expect(noteOf('冷風機'), isNot(contains('\n')));
    });

    test('括弧の但し書きは前の文に付ける', () {
      expect(noteOf('本'), endsWith('一緒にまとめてしばる（雨の日は次回に）'));
      expect(noteOf('ティッシュペーパーの箱'), 'ビニールは除いて、その他の紙へ（雨の日は次回に）');
    });

    test('文の途中の区分のバッジは、区分の名前に直してある', () {
      // 冊子は「箱は口金部分をはずして [資2] その他の紙へ」と略号で書いている。
      expect(noteOf('ラップ類'), '箱は口金部分をはずして資源物2類のその他の紙へ');
    });

    test('空の行や、行頭・行末の空白が残っていない', () {
      for (final item in dictionary.items.where((i) => i.note.isNotEmpty)) {
        for (final line in item.note.split('\n')) {
          expect(line, isNotEmpty, reason: item.name);
          expect(line.trim(), line, reason: item.name);
        }
      }
    });
  });

  test('表のいちばん下の行の注意点が落ちていない', () {
    // 脚注の手前で切る位置がページによって違う。
    final dishwasher = dictionary.items.firstWhere((i) => i.name == '食器洗浄器');
    expect(dishwasher.note, 'ビルトインは許可業者（（有）太盛）へ');
    expect(dishwasher.markIds, ['page11']);
  });

  test('品目名と区分がくっついて読まれる行も拾えている', () {
    // 品目名が欄いっぱいまで伸びると、区分と1語に読まれる。
    // 区分が無い行として捨てられ、品目ごと消えていた。
    final can = dictionary.items.firstWhere((i) => i.name == 'じょうろ（プラスチック製）');
    expect(can.categoryId, 'nonBurnable');
    final jack = dictionary.items.firstWhere(
      (i) => i.name == 'ジャッキ（車用パンタグラフ型）',
    );
    expect(jack.categoryId, 'oversized');
  });

  test('印だけの品目は注意点が空になる', () {
    final chair = dictionary.items.firstWhere((i) => i.name == 'いす');
    expect(chair.note, isEmpty);
    expect(chair.markIds, ['star2']);
    expect(chair.hasDetail, isTrue);
  });
}
