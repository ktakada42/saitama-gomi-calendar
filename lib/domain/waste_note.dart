/// 品目の注意点に付いていた印。
///
/// 市の早見表は紙の冊子なので、注意点に「★2」「▶P9参照」といった印だけを
/// 置き、意味は同じページの脚注や別のページに書いてある。冊子を持たない
/// 利用者にはこの印だけでは何のことか分からないので、抽出のときに本文から
/// 切り出しておき（`scripts/extract_waste_dictionary.py`）、ここで言葉にする。
class NoteMark {
  const NoteMark({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;

  /// 一覧やシートの見出しに出す短い言い方。
  final String title;

  /// 印の意味。市の脚注や参照先のページの中身を要約したもの。
  final String description;

  static const _marks = <String, NoteMark>{
    'star1': NoteMark(
      id: 'star1',
      title: '軽くすすいでから',
      description:
          '容器包装プラスチックは、軽くすすいで汚れが落ちるものだけが資源物1類です。'
          '汚れが落ちないものはもえるごみに出してください。',
    ),
    'star2': NoteMark(
      id: 'star2',
      title: '大きさで出し方が変わる',
      description:
          '90cm以上2m未満のものは収集所に出せません。'
          'ごみ処理施設への直接持込みか、戸別収集を申し込んでください。',
    ),
    'star3': NoteMark(
      id: 'star3',
      title: '小型家電としても出せる',
      description: '小型家電としての回収も行っています。回収ボックスに入る大きさなら、そちらでも出せます。',
    ),
    'star4': NoteMark(
      id: 'star4',
      title: '2026年10月から変わる',
      description:
          '令和8年（2026年）10月から、プラスチック製で30cm以上90cm未満のものは'
          'もえないごみになります。',
    ),
    'star5': NoteMark(
      id: 'star5',
      title: '大きさに条件がある',
      description:
          '鍵盤が2段までで、大人2人で運べるものに限ります。'
          'それより大きいものは販売店に処理を依頼してください。',
    ),
    'star6': NoteMark(
      id: 'star6',
      title: '大きさに条件がある',
      description:
          '戸別収集できる物置には条件があります。解体できるものは鋼板'
          '（90cm以上2m未満）10枚まで、解体できないものは高さ・横幅・奥行の'
          '合計が260cm以下のものに限ります。',
    ),
    'page7': NoteMark(
      id: 'page7',
      title: '出し方に決まりがある',
      description: '収集所への出し方が決まっています。市のマニュアル7ページ「収集所に出せるごみの出し方」を確認してください。',
    ),
    'page9': NoteMark(
      id: 'page9',
      title: '申込みが必要',
      description:
          '収集所には出せません。ごみ処理施設への直接持込み（完全予約制）か、'
          '戸別収集の申込みが必要です。どちらも手数料がかかります。'
          '市のマニュアル9ページを確認してください。',
    ),
    'page10': NoteMark(
      id: 'page10',
      title: '市では収集しない',
      description:
          '家電リサイクル法の対象品目など、市では収集・処理できないものです。'
          '販売店や専門業者に引き取りを依頼してください。'
          '市のマニュアル10ページを確認してください。',
    ),
    'page11': NoteMark(
      id: 'page11',
      title: '市では収集しない',
      description:
          '市では収集・処理できないものです。販売店・専門業者、または市の許可業者に'
          '引き取りを依頼してください。市のマニュアル11ページを確認してください。',
    ),
    'page12': NoteMark(
      id: 'page12',
      title: '回収ボックスへ',
      description:
          '小型家電回収ボックス（投入口30cm×15cm）に入れられます。'
          '充電式電池は本体から外し、テープで絶縁して電池回収ボックスへ。'
          '市のマニュアル12ページを確認してください。',
    ),
  };

  /// 印のidから中身を引く。知らないidは無視する。
  ///
  /// 市が印を増やしても、アプリが古いまま落ちたり空欄を出したりしないよう、
  /// 引けなかったものは黙って捨てる。
  static List<NoteMark> resolve(List<String> ids) =>
      ids.map((id) => _marks[id]).nonNulls.toList();
}
