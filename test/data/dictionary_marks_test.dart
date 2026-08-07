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

  test('印だけの品目は注意点が空になる', () {
    final chair = dictionary.items.firstWhere((i) => i.name == 'いす');
    expect(chair.note, isEmpty);
    expect(chair.markIds, ['star2']);
    expect(chair.hasDetail, isTrue);
  });
}
