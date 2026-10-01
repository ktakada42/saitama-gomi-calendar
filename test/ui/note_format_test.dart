import 'package:flutter_test/flutter_test.dart';
import 'package:saitama_gomi/ui/note_format.dart';

void main() {
  test('※の手前で改行する', () {
    // 早見表は1つの欄に複数の但し書きを詰め込んでいる。抽出すると
    // 前の文と地続きになって読みにくいので、文ごとに分ける。
    expect(
      splitNoteLines('紙等にしみ込ませるか、固めてから※液体のものは、排出禁止'),
      '紙等にしみ込ませるか、固めてから\n※液体のものは、排出禁止',
    );
  });

  test('先頭の※では改行しない', () {
    expect(
      splitNoteLines('※液体のものは、排出禁止※びんは中をからにして'),
      '※液体のものは、排出禁止\n※びんは中をからにして',
    );
  });

  test('すでに改行してある※の手前に、もう1つ改行を足さない', () {
    // 抽出のときに但し書きの切れ目で改行してある。重ねると空行ができる。
    expect(
      splitNoteLines('紙等にしみ込ませるか、固めてから\n※液体のものは、排出禁止'),
      '紙等にしみ込ませるか、固めてから\n※液体のものは、排出禁止',
    );
  });

  test('※が無ければそのまま', () {
    expect(splitNoteLines('中をすすいで'), '中をすすいで');
    expect(splitNoteLines(''), '');
  });

  test('括弧の折り返し防止と併せて効く', () {
    // 「（雨の日は次回に）」が途中で切れず、※の手前で行が分かれる。
    final result = formatNote('その他の紙として（雨の日は次回に）※金属部分は、もえないごみ');
    expect(result.replaceAll('⁠', ''), contains('\n※金属部分は'));
    expect(result, contains('（⁠雨'));
  });
}
