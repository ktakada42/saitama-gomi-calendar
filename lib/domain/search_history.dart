/// 分別早見表の検索履歴。
///
/// 端末内に保存するデータ量が際限なく増えないよう、保持する件数（[maxEntries]）と
/// 1件あたりの文字数（[maxQueryLength]）の両方に上限を置く。
///
/// 文字数にも上限を置くのは、`WasteItem.matches` が「入力のほうが品目名を含む場合」も
/// 拾うため。クリップボードの長文を誤って貼り付けたときに「いす」「かばん」などの
/// 短い品目名が紛れていると該当ありになってしまい、件数上限だけでは大きな文字列が
/// そのまま保存されうる。早見表で最も長い品目名は25文字なので、30文字あれば通常の
/// 検索語はすべて収まり、保存量も最大で数百バイトに留まる。
class SearchHistory {
  const SearchHistory._(this.queries);

  /// 履歴が空の初期状態。
  const SearchHistory.empty() : queries = const [];

  /// 保存されていた文字列の並びから履歴を復元する。
  ///
  /// 空文字・上限超過・重複を取り除き、先頭から最大 [maxEntries] 件に丸める。
  factory SearchHistory.fromList(Iterable<String> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      final cleaned = _sanitize(entry);
      if (cleaned == null || !seen.add(cleaned)) continue;
      result.add(cleaned);
      if (result.length >= maxEntries) break;
    }
    if (result.isEmpty) return const SearchHistory.empty();
    return SearchHistory._(List.unmodifiable(result));
  }

  /// 保持する最大件数。超えた分は古いものから落とす。
  static const int maxEntries = 10;

  /// 1件あたりの最大文字数（Unicodeコードポイント数）。
  static const int maxQueryLength = 30;

  /// 新しい順（先頭が直近）に並んだ検索語。
  final List<String> queries;

  bool get isEmpty => queries.isEmpty;
  bool get isNotEmpty => queries.isNotEmpty;

  /// [query] を直近の検索語として記録した新しい履歴を返す。
  ///
  /// 空白のみ、または [maxQueryLength] を超える入力は無視してそのまま返す。
  /// 既にある語は重複させず先頭へ移し、[maxEntries] を超えた古い語は落とす。
  SearchHistory record(String query) {
    final cleaned = _sanitize(query);
    if (cleaned == null) return this;
    if (queries.isNotEmpty && queries.first == cleaned) return this;

    final next = <String>[
      cleaned,
      for (final existing in queries)
        if (existing != cleaned) existing,
    ];
    if (next.length > maxEntries) {
      next.removeRange(maxEntries, next.length);
    }
    return SearchHistory._(List.unmodifiable(next));
  }

  /// [query] を取り除いた新しい履歴を返す。含まれていなければそのまま返す。
  SearchHistory remove(String query) {
    if (!queries.contains(query)) return this;
    final next = [
      for (final existing in queries)
        if (existing != query) existing,
    ];
    if (next.isEmpty) return const SearchHistory.empty();
    return SearchHistory._(List.unmodifiable(next));
  }

  static String? _sanitize(String raw) {
    final collapsed = raw.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (collapsed.isEmpty) return null;
    if (collapsed.runes.length > maxQueryLength) return null;
    return collapsed;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SearchHistory || other.queries.length != queries.length) {
      return false;
    }
    for (var i = 0; i < queries.length; i++) {
      if (other.queries[i] != queries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(queries);
}
