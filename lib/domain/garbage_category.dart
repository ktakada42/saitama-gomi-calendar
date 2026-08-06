/// さいたま市の家庭ごみの区分。
///
/// 市の収集区分は5つで、収集曜日はこの区分ごとに決まっている。
/// 「もえないごみ・有害危険ごみ・資源物2類」は同じ曜日にまとめて出す地区が多いが、
/// 頻度が違うことがある（例：資源物2類は毎週だがもえないごみは月1回）ため、
/// ここではあくまで独立した区分として扱い、曜日が揃うかどうかはデータ側に委ねる。
///
/// この列挙は表示順もかねている（宣言順にカレンダーやリストへ並ぶ）。
enum GarbageCategory {
  burnable(
    id: 'burnable',
    label: 'もえるごみ',
    shortLabel: 'もえる',
    examples: ['生ごみ', '紙くず', '衣類', '木くず', '容器包装以外のプラスチック製品'],
    howTo: '中身の見える袋（透明・半透明）に入れて出す。生ごみは水気をよく切る。',
  ),
  nonBurnable(
    id: 'nonBurnable',
    label: 'もえないごみ',
    shortLabel: 'もえない',
    examples: ['金属類', '陶磁器', 'ガラス製品', '小型家電', '鍋・やかん'],
    howTo: '中身の見える袋に入れて出す。刃物など危険なものは紙で包んで表示する。',
  ),
  hazardous(
    id: 'hazardous',
    label: '有害危険ごみ',
    shortLabel: '有害危険',
    examples: ['蛍光管', '乾電池', '水銀体温計', 'スプレー缶', 'ライター'],
    howTo: '他のごみとは別の透明袋にまとめる。スプレー缶・ライターは必ず使い切る。',
  ),
  recyclable1(
    id: 'recyclable1',
    label: '資源物1類',
    shortLabel: '資源1',
    examples: ['びん', 'かん', 'ペットボトル', '容器包装プラスチック'],
    howTo: '種類ごとに分けて、それぞれ透明袋へ。中を洗い、ペットボトルはキャップとラベルを外す。',
  ),
  recyclable2(
    id: 'recyclable2',
    label: '資源物2類',
    shortLabel: '資源2',
    examples: ['新聞', '雑誌・雑がみ', 'ダンボール', '紙パック', '古着'],
    howTo: '種類ごとにたたんで、ひも等でしばって出す。雨の日は次回に回すとよい。',
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
