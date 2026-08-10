/// 集計の区切りは日本時間で置く。
///
/// 利用者はさいたま市の住民なので、「1日20問」の1日は日本時間の1日である
/// べき。UTCで切ると、日本の朝9時に回数が戻ることになる。

const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

function jst(now: Date): string {
  return new Date(now.getTime() + JST_OFFSET_MS).toISOString();
}

/// 「2026-08-10」
export function jstDay(now: Date): string {
  return jst(now).slice(0, 10);
}

/// 「2026-08」
export function jstMonth(now: Date): string {
  return jst(now).slice(0, 7);
}

/// 「2026-08-10T14:23」。短時間に集中して投げられていないかを見るための区切り。
export function jstMinute(now: Date): string {
  return jst(now).slice(0, 16);
}
