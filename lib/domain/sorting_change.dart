/// 市の分別の決まりが変わる日と、その内容。
///
/// 分別のデータはアプリに同梱しているので、決まりが変わっても
/// アプリを更新しない利用者には古い分類が出続ける。表示している分類が
/// もう当てにならないことを、その日を過ぎたら本人に伝える。
///
/// データを日付で切り替えることはしない。市が公表しているのは
/// 「最長辺30cm未満・すべてプラスチック製」という条件だけで、
/// 品目ごとにどうなるかは示されていない。446件のうち該当しそうなものは
/// 22件あるが、市が印を付けているのは6件だけで、残りは材質や大きさを
/// 品物ごとに見ないと決められない（「おもちゃ」「めがねケース」など）。
/// 推測で分類すると、市の情報と見分けのつかない誤りを混ぜることになる。
/// 品目ごとの分別は市が10月1日に分別辞典を更新すると告知しているので、
/// それが出てからデータを入れ替える（#20）。それまでは、市が挙げている
/// 条件をそのまま渡して、利用者が自分で判断できるようにしておく。
class SortingChange {
  const SortingChange({
    required this.effectiveFrom,
    required this.title,
    required this.description,
    required this.conditions,
    required this.noticeUrl,
  });

  /// この日から新しい決まりになる。
  final DateTime effectiveFrom;

  final String title;
  final String description;

  /// 品目別の分別が分からなくても自分で判断できるよう、市が挙げている条件。
  final List<String> conditions;

  /// 市がこの変更を告知しているページ。分別の一覧ではなく、こちらを開く。
  final String noticeUrl;

  /// [today] の時点で、もう始まっている変更か。
  bool hasStarted(DateTime today) => !today.isBefore(effectiveFrom);

  /// 令和8年10月1日のプラスチックの分別変更。
  ///
  /// 市の「家庭ごみの出し方マニュアル」令和8年度版と、告知ページ
  /// （https://www.city.saitama.lg.jp/001/006/010/003/p127278.html）が
  /// 予告しているもの。条件は告知ページの「ポイント」の逐語要約。
  static final plastic2026 = SortingChange(
    effectiveFrom: DateTime(2026, 10, 1),
    title: 'プラスチックの分別が変わりました',
    description:
        'このアプリの分別はまだ変更前のものです。'
        '歯ブラシ・ストローなどのプラスチック製品は、'
        'もえるごみではなく資源物1類（プラスチック資源）になりました。'
        '次のすべてにあてはまるものが対象です。',
    // 括弧の中は行を切らずに出している（keepParenthesesTogether）。
    // 下限の画面（375pt）で括弧が1行に収まる長さにしてあり、これより
    // 伸ばすと括弧の中で折り返して、閉じ括弧だけが次の行に残る。
    conditions: [
      'プラスチック100％でできている（金属を含む洗濯ばさみ等はもえるごみ）',
      'いちばん長い辺が30cm未満（30cm以上はもえないごみ、または小さく切る）',
      '水で軽くすすいで汚れが落ちる（油汚れの容器・スプーンはもえるごみ）',
    ],
    noticeUrl: 'https://www.city.saitama.lg.jp/001/006/010/003/p127278.html',
  );

  /// 表示の対象にする変更。過ぎたものから順に見る。
  static final all = [plastic2026];

  /// [today] の時点で伝えるべき変更。無ければ null。
  static SortingChange? current(DateTime today) {
    for (final change in all) {
      if (change.hasStarted(today)) return change;
    }
    return null;
  }
}
