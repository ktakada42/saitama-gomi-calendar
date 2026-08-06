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
/// 【要フォローアップ】同マニュアルによると、令和8年10月1日から容器包装プラスチックは
/// 「プラスチック資源」に名称変更され、現在もえるごみとして出している歯ブラシ・
/// ハンガー・スプーン等（最長辺30cm未満・すべてプラスチック製）もその対象に加わる。
/// burnable.examplesの「容器包装以外のプラスチック製品」はこの変更で古くなるため、
/// 10月の施行にあわせて見直すこと。
enum GarbageCategory {
  burnable(
    id: 'burnable',
    label: 'もえるごみ',
    shortLabel: 'もえる',
    examples: ['生ごみ', '紙おむつ', '写真・レシート', '木の枝', '容器包装以外のプラスチック製品'],
    howTo:
        '中身の見える袋（透明・半透明）に入れて出す。'
        '最大の一辺または直径が90cm以上のものは粗大ごみ。生ごみは水気をよく切ってから入れる。',
  ),
  nonBurnable(
    id: 'nonBurnable',
    label: 'もえないごみ',
    shortLabel: 'もえない',
    examples: ['陶磁器', 'ガラス製品', '鍋・やかん', '電球', '傘'],
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
    examples: ['びん', 'かん', 'ペットボトル', '容器包装プラスチック'],
    howTo:
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
  });

  /// JSON に書き出すときの識別子。列挙の name と一致させてあるが、
  /// 将来 name を変えても保存済みデータが壊れないよう明示的に持つ。
  final String id;

  /// 画面に出す正式名称。
  final String label;

  /// カレンダーのセルなど幅の狭い場所で使う短い名称。
  final String shortLabel;

  /// 代表的な品目。「これはどの区分か」を思い出すための手がかり。
  final List<String> examples;

  /// 出し方の要点。市のマニュアルの要約であって全文ではない。
  final String howTo;

  static GarbageCategory? fromId(String id) {
    for (final category in GarbageCategory.values) {
      if (category.id == id) return category;
    }
    return null;
  }
}
