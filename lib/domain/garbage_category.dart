import 'sorting_change.dart';

/// さいたま市の家庭ごみの区分。
///
/// 市の収集区分は5つで、収集曜日はこの区分ごとに決まっている。
/// 「もえないごみ・有害危険ごみ・資源物2類」は同じ曜日にまとめて出す地区が多いが、
/// 頻度が違うことがある（例：資源物2類は毎週だがもえないごみは月1回）ため、
/// ここではあくまで独立した区分として扱い、曜日が揃うかどうかはデータ側に委ねる。
///
/// この列挙は表示順もかねている（宣言順にカレンダーやリストへ並ぶ）。
///
/// examples・howToは、さいたま市「家庭ごみの出し方マニュアル」令和8年度版
/// （https://www.city.saitama.lg.jp/001/006/010/003/p005300.html）と
/// 2026年8月に照合済み。全文の要約であって全項目を網羅してはいない。
///
/// 令和8年10月1日のプラスチックの分別変更（容器包装プラスチックが
/// 「プラスチック資源」に名称変更され、プラスチック製品も対象になった）は、
/// 同マニュアルと、9月に全戸配布されたリーフレット
/// （https://www.city.saitama.lg.jp/001/006/010/003/p127278.html）に合わせてある。
enum GarbageCategory {
  burnable(
    id: 'burnable',
    label: 'もえるごみ',
    shortLabel: 'もえる',
    examples: ['生ごみ', '紙おむつ', '写真・レシート', '木の枝', '汚れの落ちないプラスチック'],
    examplesBeforePlastic2026: [
      '生ごみ',
      '紙おむつ',
      '写真・レシート',
      '木の枝',
      '容器包装以外のプラスチック製品',
    ],
    howTo:
        '中身の見える袋（透明・半透明）に入れて出す。'
        '最大の一辺または直径が90cm以上のものは粗大ごみ。生ごみは水気をよく切ってから入れる。',
  ),
  nonBurnable(
    id: 'nonBurnable',
    label: 'もえないごみ',
    shortLabel: 'もえない',
    examples: ['陶磁器', 'ガラス製品', '鍋・やかん', '電球', '傘', '30cm以上のプラスチック製品'],
    examplesBeforePlastic2026: ['陶磁器', 'ガラス製品', '鍋・やかん', '電球', '傘'],
    howTo:
        '中身の見える袋に入れて出す。刃物は紙で包んで「包丁」等と表示する。'
        'ライター・スプレー缶は入れない（有害危険ごみへ）。',
  ),
  hazardous(
    id: 'hazardous',
    label: '有害危険ごみ',
    shortLabel: '有害危険',
    examples: ['蛍光管', '乾電池', '水銀体温計', 'スプレー缶', 'ライター'],
    howTo:
        'もえないごみとは別に、種類ごとに別々の透明袋に入れて出す。'
        'スプレー缶・ライターは中身を使い切り、残る場合は「中身あり」と表示する。'
        'ボタン電池・充電式電池は出さず、電池回収ボックスへ。',
  ),
  recyclable1(
    id: 'recyclable1',
    label: '資源物1類',
    shortLabel: '資源1',
    examples: ['びん', 'かん', 'ペットボトル', 'プラスチック資源'],
    examplesBeforePlastic2026: ['びん', 'かん', 'ペットボトル', '容器包装プラスチック'],
    howTo:
        'フタを外し、軽くすすいで種類ごとに透明袋へ。ペットボトルはラベルも外す。'
        '洗剤を使う必要はない。'
        'プラスチック資源は、プラスチック100％で30cm未満、すすいで汚れが落ちるもの。',
    howToBeforePlastic2026:
        'フタを外し、軽くすすいで種類ごとに透明袋へ。ペットボトルはラベルも外す。'
        '洗剤を使う必要はない。',
  ),
  recyclable2(
    id: 'recyclable2',
    label: '資源物2類',
    shortLabel: '資源2',
    examples: ['新聞', '雑誌・雑がみ', 'ダンボール', '紙パック', '古着'],
    howTo:
        '種類ごとにたたんでひも等でしばる（繊維は透明袋でも可）。'
        '濡れるとリサイクルできないため、雨の日は次回に出す。',
  );

  const GarbageCategory({
    required this.id,
    required this.label,
    required this.shortLabel,
    required this.examples,
    required this.howTo,
    this.examplesBeforePlastic2026,
    this.howToBeforePlastic2026,
  });

  /// JSON に書き出すときの識別子。列挙の name と一致させてあるが、
  /// 将来 name を変えても保存済みデータが壊れないよう明示的に持つ。
  final String id;

  /// 画面に出す正式名称。
  final String label;

  /// カレンダーのセルなど幅の狭い場所で使う短い名称。
  final String shortLabel;

  /// 代表的な品目。「これはどの区分か」を思い出すための手がかり。
  ///
  /// いまの決まりでのもの。画面に出すときは、その日の決まりを引く
  /// [examplesOn] を使う。
  final List<String> examples;

  /// 出し方の要点。市のマニュアルの要約であって全文ではない。
  ///
  /// いまの決まりでのもの。画面に出すときは [howToOn] を使う。
  final String howTo;

  /// 令和8年10月のプラスチックの分別変更より前の代表品目。
  /// 変更で変わらなかった区分は null。
  final List<String>? examplesBeforePlastic2026;

  /// 同じく、変更より前の出し方。
  final String? howToBeforePlastic2026;

  /// [day] に出すときの代表品目。
  ///
  /// カレンダーは過去の月も見られる。9月以前の資源物1類に「プラスチック資源」
  /// と出すと、当時は集めていなかったものを載せることになる。
  /// 分別の一覧と違って日付で切り替えるのは、こちらは区分ごとの短い文で、
  /// 変更の前後とも市のマニュアルに書いてあるから（一覧のほうは、品目ごとの
  /// 新しい区分を市が一部しか示していない）。
  List<String> examplesOn(DateTime day) => _isBeforePlastic2026(day)
      ? examplesBeforePlastic2026 ?? examples
      : examples;

  /// [day] に出すときの出し方。
  String howToOn(DateTime day) =>
      _isBeforePlastic2026(day) ? howToBeforePlastic2026 ?? howTo : howTo;

  static bool _isBeforePlastic2026(DateTime day) =>
      !SortingChange.plastic2026.hasStarted(day);

  static GarbageCategory? fromId(String id) {
    for (final category in GarbageCategory.values) {
      if (category.id == id) return category;
    }
    return null;
  }
}
