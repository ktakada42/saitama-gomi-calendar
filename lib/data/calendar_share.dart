import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/calendar_export.dart';
import '../domain/collection_area.dart';

/// 収集日を.icsファイルに書き出し、共有シートに渡す。
///
/// 端末のカレンダーに直接書き込む（EventKit）方式にしないのは、
/// カレンダーへのアクセス権限を求めずに済むため。共有シートから
/// 「カレンダー」を選ぶと、追加先も利用者が選べる。
///
/// ウィジェットテストではファイル書き出しも共有シートも動かないため、
/// テストからは[NoopCalendarShare]に差し替える。
abstract class CalendarShare {
  /// [area]の収集日を.icsにして共有シートを開く。
  Future<void> share(CollectionArea area);

  static CalendarShare create() => const _FileCalendarShare();
}

/// 何もしない実装。テストで使う。
class NoopCalendarShare implements CalendarShare {
  const NoopCalendarShare();

  @override
  Future<void> share(CollectionArea area) async {}
}

class _FileCalendarShare implements CalendarShare {
  const _FileCalendarShare();

  @override
  Future<void> share(CollectionArea area) async {
    final ics = CalendarExport(area).build(from: DateTime.now());

    // 共有シートに渡すには実ファイルが要る。一時ディレクトリに置けば、
    // OSが適当なタイミングで片付けてくれる。
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/gomi_calendar.ics');
    await file.writeAsString(ics);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/calendar')],
        subject: 'ごみ収集日（${area.ward} ${area.name}）',
      ),
    );
  }
}
