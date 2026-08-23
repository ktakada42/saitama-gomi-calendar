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
class SortingChange {
  const SortingChange({
    required this.effectiveFrom,
    required this.title,
    required this.description,
  });

  /// この日から新しい決まりになる。
  final DateTime effectiveFrom;

  final String title;
  final String description;

  /// [today] の時点で、もう始まっている変更か。
  bool hasStarted(DateTime today) => !today.isBefore(effectiveFrom);

  /// 令和8年10月1日のプラスチックの分別変更。
  ///
  /// 市の「家庭ごみの出し方マニュアル」令和8年度版が予告しているもの。
  static final plastic2026 = SortingChange(
    effectiveFrom: DateTime(2026, 10, 1),
    title: 'プラスチックの分別が変わりました',
    description:
        'このアプリの分別はまだ変更前のものです。'
        '歯ブラシ・ストローなどの小さなプラスチック製品の出し先が変わっています。'
        '市の最新の案内を確認してください。',
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
