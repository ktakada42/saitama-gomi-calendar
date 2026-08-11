import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/data/waste_dictionary.dart';

/// 言い換えの検査。
///
/// 市は「かん」「びん」「フタ」とかなで書くが、利用者は「缶」「瓶」「ふた」と
/// 打つ。品目を足しても、この対応が無いと引けない。#102 で飲料のかんを
/// 足したのに「缶」でも「ジュースの缶」でも出なかった。
void main() {
  late WasteDictionary dictionary;
  late Map<String, dynamic> keywords;

  setUpAll(() {
    Map<String, dynamic> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    keywords = read('assets/data/dictionary_keywords.json');
    dictionary = WasteDictionary.fromJson(
      read('assets/data/dictionary.json'),
      extra: read('assets/data/dictionary_extra.json'),
      keywords: keywords,
    );
  });

  List<String> found(String query) =>
      dictionary.search(query).map((i) => i.name).toList();

  group('対応表', () {
    test('指している品目が、すべて実在する', () {
      // 名前を書き間違えると、その言い換えは誰にも当たらない。
      // 黙って効かなくなるので気づけない。
      final names = dictionary.items.map((i) => i.name).toSet();
      for (final key in (keywords['keywords'] as Map<String, dynamic>).keys) {
        expect(names, contains(key), reason: key);
      }
    });

    test('言い換えが品目に届いている', () {
      final withKeywords = dictionary.items.where((i) => i.keywords.isNotEmpty);
      expect(
        withKeywords,
        hasLength((keywords['keywords'] as Map<String, dynamic>).length),
      );
    });
  });

  group('漢字で打っても引ける', () {
    test('缶', () {
      // 市は「かん」。利用者は「缶」と打つ。
      expect(found('缶'), contains('飲料のかん'));
      expect(found('ジュースの缶'), contains('飲料のかん'));
      expect(found('空き缶'), contains('飲料のかん'));
      expect(found('一斗缶'), contains('一斗かん'));
      expect(found('スプレー缶'), contains('スプレーかん'));
    });

    test('瓶', () {
      expect(found('瓶'), contains('酒類のびん'));
      expect(found('ビール瓶'), contains('酒類のびん'));
      expect(found('ジャムの瓶'), contains('ジャムのびん'));
    });

    test('ふた・蓋', () {
      // 市は「フタ」。利用者は「ふた」「蓋」と打つ。
      expect(found('ふた'), contains('びんのフタ（金属製）'));
      expect(found('蓋'), contains('ペットボトルのフタ'));
      expect(found('お風呂のふた'), contains('風呂のフタ'));
    });
  });

  group('言い方が違っても引ける', () {
    test('太陽光パネル', () {
      // 市の名前は「太陽ソーラー」。この名前で探す人はいない。
      expect(found('太陽光パネル'), contains('太陽ソーラー'));
      expect(found('ソーラーパネル'), contains('太陽ソーラー'));
    });

    test('AIの検証で外していた言い方', () {
      // scripts/ai_eval/cases.json で候補に入らず落ちていたもの。
      // AIに推測させる前に、決まっている言い換えは確実に当てる。
      expect(found('けいたいでんわ'), contains('携帯電話・ＰＨＳ'));
      expect(found('こわれた傘'), contains('かさ'));
      expect(found('けいこうとう'), contains('蛍光管・蛍光ランプ'));
      expect(found('electric fan'), contains('扇風機'));
      expect(found('飲み物の管'), contains('ストロー'));
    });

    test('紛らわしい別物は、別の言い換えを持つ', () {
      // P11のミニカーは一人乗りの車。早見表のミニカーはおもちゃ。
      expect(found('トミカ'), contains('ミニカー（おもちゃ）'));
      expect(found('超小型モビリティ'), contains('ミニカー（一人乗りの車）'));
      expect(found('トミカ'), isNot(contains('ミニカー（一人乗りの車）')));
    });
  });

  group('打ち方が違っても引ける', () {
    test('修飾語を付けて打っても引ける', () {
      // 利用者は品目名だけを打つとは限らない。前方の一致だけを見ていると、
      // いちばん困っている人が0件になる。
      expect(found('こわれた電球'), contains('電球'));
      expect(found('金属のフライパン'), contains('フライパン'));
      expect(found('使わなくなった自転車'), contains('自転車'));
      expect(found('電子レンジが壊れた'), contains('電子レンジ'));
    });

    test('括弧の補足があっても、主要部で引ける', () {
      // 「新聞紙（折込チラシ含）」は、括弧まで含めると「古い新聞紙」に
      // 収まらない。主要部だけでも見る。
      expect(found('古い新聞紙'), contains('新聞紙（折込チラシ含）'));
      expect(found('割れたコップ'), contains('コップ（ガラス）'));
    });

    test('カタカナでもひらがなでも引ける', () {
      // 市は「生ごみ」、利用者は「生ゴミ」と打つ。
      expect(found('生ゴミ'), contains('食品くず・残飯'));
      expect(found('生ごみ'), contains('食品くず・残飯'));
      expect(found('ヤカン'), contains('やかん'));
    });

    test('短い名前が、長い入力にたまたま含まれても拾わない', () {
      // 「石」「土」のような1文字の品目は、どんな文にも紛れ込む。
      expect(found('石けんの容器'), isNot(contains('石')));
    });
  });

  group('AIで生成した言い換え', () {
    test('かな書きの品目を、漢字で引ける', () {
      // 「椅子」で「いす」が出ない、という実機での指摘がきっかけ。
      // 市はかなで書き、利用者は漢字で打つ。手で埋めると取りこぼす
      // （実際に取りこぼした）ので、ビルド時にAIで作らせている。
      expect(found('椅子'), contains('いす'));
      expect(found('玩具'), contains('おもちゃ'));
      expect(found('鞄'), contains('かばん・バッグ'));
      expect(found('襖'), contains('ふすま'));
      expect(found('箪笥'), contains('たんす'));
      expect(found('瓦'), contains('かわら'));
      expect(found('雑巾'), contains('ぞうきん'));
      expect(found('蝋燭'), contains('ろうそく'));
    });

    test('商品名で引ける。英字の綴りも', () {
      // 「アイコスやiQOSで調べる人がいそう」という指摘から。
      // 正規化はカタカナをひらがなに寄せるだけで、英字とは結び付かない。
      // 「アイコス」を入れても「iQOS」では出ないので、両方を持つ。
      for (final q in ['アイコス', 'iQOS', 'iqos', 'IQOS', 'プルーム', 'glo']) {
        expect(found(q), contains('加熱式電子たばこ'), reason: q);
      }
      for (final q in ['ルンバ', 'ダイソン', 'Dyson']) {
        expect(found(q), contains('掃除機'), reason: q);
      }
    });

    test('同じものが、区分違いで二重に載っていない', () {
      // 早見表に「加熱式電子たばこ」があるのに、図解ページから
      // 「加熱式タバコ」を足してしまい、電池回収ボックスと小型家電の
      // 2つが並んでいた。生成物のレビュー中に見つけた実バグ。
      final smoking = dictionary.items
          .where((i) => i.name.contains('たばこ') || i.name.contains('タバコ'))
          .toList();
      final categories = smoking
          .where((i) => !i.name.contains('紙箱'))
          .map((i) => i.categoryLabel)
          .toSet();
      expect(categories, hasLength(1), reason: '$smoking');
    });
  });

  test('言い換えを足しても、元の名前で引ける', () {
    // 上書きしていないこと。
    expect(found('やかん'), contains('やかん'));
    expect(found('ペットボトル'), contains('ペットボトル'));
  });
}
