#!/usr/bin/env node
// さいたま市公式サイトの「収集日カレンダー」（p042612.html?page=area）が内部で使っている
// gomisuke（ごみすけ）ウィジェットのデータAPIから、地区ごとの収集曜日を取得して
// assets/data/areas.json の `areas` 配列を生成し直す。あわせて日本郵便の郵便番号データと
// 突き合わせて `postalAreas`（郵便番号→地区IDの候補一覧）も生成する。
//
// エンドポイントはウィジェットの通信をブラウザの開発者ツール相当（Playwright）で
// 観察して見つけたもので、公式に文書化されたAPIではない。ベンダーが変更すれば
// 壊れる前提で、実行結果は必ず目視確認してからコミットすること。
//
// 使い方: node scripts/update_areas_json.mjs
//   （Node 18+ を想定。fetchが標準搭載されているバージョンならこれ以外の依存は不要。
//   　郵便番号データはZIP配布なので、システムの`unzip`コマンドを使う。）
//
// 何をしているか:
//   1. area/type/calendar の3つのJSONP APIを取得する
//      - area: パターンID(areaID) → 区名＋町丁目名（★は早朝収集地区の印）
//      - type: typeID → ごみの分類名（もえるごみ、びん、など）
//      - calendar: areaID・年月ごとに「その月の何日に何のtypeIDが収集されるか」の実データ
//        （取得時点で15か月分＝1年強のデータが入っている）
//   2. calendarの実データから、区分(GarbageCategoryの5分類)ごとに
//      「何曜日か」「毎週か第何週だけか」を逆算する（CollectionRuleと同じモデル）
//   3. 資源物1類(びん・かん・ペットボトル・容器包装プラスチック)と
//      資源物2類(古紙類・繊維)が常にセットで収集されているかを検証する
//      （このアプリはこの4つ/2つをそれぞれ1つの区分として扱っているため、
//      　もし将来ズレる地区が出てきたらここで検知して止まる）
//   4. ★（早朝収集地区）が1パターンの中で町丁目ごとに混在する場合は、
//      早朝地区/通常地区の2エントリに分割する
//   5. 日本郵便の「住所の郵便番号」全国データ（KEN_ALL）からさいたま市の行を抜き出し、
//      町丁目名（丁目番号・かっこ書きを除いたベース名）でareasの各地区と突き合わせて
//      郵便番号→地区ID候補のマップを作る。1つの郵便番号が複数の地区にまたがることが
//      実際にあるため（例：三橋という郵便番号は西区の複数パターンにまたがる）、
//      「1件に絞れる」保証はしない。候補が複数残ったらUI側で選ばせる前提。
//   6. 既存の areas.json の presets・disclaimer・source は保持し、
//      areas・postalAreas だけ差し替える

import { writeFile, readFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const AREAS_JSON_PATH = path.join(__dirname, '..', 'assets', 'data', 'areas.json');

const API_BASE = 'https://admin.gomisuke.jp/app/0017/api/jsonp.php';
const POSTAL_ZIP_URL =
  'https://www.post.japanpost.jp/service/search/zipcode/download/utf/zip/utf_ken_all.zip';

const CATEGORY_TYPES = {
  burnable: ['1'],
  nonBurnable: ['2'],
  hazardous: ['3'],
  recyclable2: ['4', '5'], // 古紙類・繊維
  recyclable1: ['6', '7', '8', '9'], // びん・かん・ペットボトル・容器包装プラスチック
};
const CATEGORY_ORDER = ['burnable', 'nonBurnable', 'hazardous', 'recyclable1', 'recyclable2'];

async function fetchJsonp(file) {
  const res = await fetch(`${API_BASE}?file=${file}`);
  if (!res.ok) throw new Error(`fetch failed for file=${file}: ${res.status}`);
  const raw = await res.text();
  const jsonText = raw
    .replace(new RegExp(`^gomisukeGetData\\('${file}',`), '')
    .replace(/\);\s*$/, '');
  return JSON.parse(jsonText);
}

function nthWeekdayOfMonth(day) {
  return Math.floor((day - 1) / 7) + 1;
}

function buildPerAreaCalendar(calendarData) {
  // areaID -> [{year, month, day, weekday(1=月..7=日), typeIDs:[...]}]
  const perArea = {};
  for (const monthEntry of calendarData.array.dict) {
    const yearMonth = monthEntry.string;
    const year = parseInt(yearMonth.slice(0, 4), 10);
    const month = parseInt(yearMonth.slice(4, 6), 10);
    for (const areaEntry of monthEntry.array.dict) {
      const areaID = areaEntry.string;
      const dateDict = areaEntry.dict;
      if (!dateDict || !dateDict.key) continue;
      const days = Array.isArray(dateDict.key) ? dateDict.key : [dateDict.key];
      const vals = Array.isArray(dateDict.string) ? dateDict.string : [dateDict.string];
      perArea[areaID] ??= [];
      for (let i = 0; i < days.length; i++) {
        const day = parseInt(days[i], 10);
        const typeIDs = String(vals[i]).split(',').map((s) => s.trim()).filter(Boolean);
        const jsWeekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay(); // 0=日
        const weekday = jsWeekday === 0 ? 7 : jsWeekday; // Dart式 1=月..7=日
        perArea[areaID].push({ year, month, day, weekday, typeIDs });
      }
    }
  }
  return perArea;
}

function checkGroupCoOccurrence(perArea) {
  // 資源物1類・2類が常にセットで出現するかを確認する。1件でも崩れていたら
  // カテゴリ分けの前提が崩れているということなので、呼び出し側で処理を止める。
  const mismatches = [];
  for (const [areaID, entries] of Object.entries(perArea)) {
    for (const e of entries) {
      const set = new Set(e.typeIDs);
      for (const ids of [['6', '7', '8', '9'], ['4', '5']]) {
        const present = ids.filter((id) => set.has(id));
        if (present.length > 0 && present.length < ids.length) {
          mismatches.push({ areaID, date: `${e.year}-${e.month}-${e.day}`, expected: ids, present });
        }
      }
    }
  }
  return mismatches;
}

function inferRulesForCategory(entries, typeIds) {
  // weekday-week の組ごとに「収集された月」「されなかった月」を集計し、
  // 月をまたいで矛盾なく同じ結果になっているかを確認しながら曜日ルールを組み立てる。
  const byKey = {};
  for (const e of entries) {
    if (e.month === 1 && e.day <= 3) continue; // 年始休止日は判定対象から除く
    const week = nthWeekdayOfMonth(e.day);
    const key = `${e.weekday}-${week}`;
    byKey[key] ??= { weekday: e.weekday, week, present: new Set(), absent: new Set() };
    const monthKey = `${e.year}-${e.month}`;
    const hasCategory = e.typeIDs.some((t) => typeIds.includes(t));
    (hasCategory ? byKey[key].present : byKey[key].absent).add(monthKey);
  }

  const inconsistent = [];
  const allWeeksByWeekday = {};
  const presentWeeksByWeekday = {};
  for (const { weekday, week, present, absent } of Object.values(byKey)) {
    (allWeeksByWeekday[weekday] ??= new Set()).add(week);
    if (present.size > 0 && absent.size > 0) {
      inconsistent.push({ weekday, week, presentMonths: [...present], absentMonths: [...absent] });
      continue;
    }
    if (present.size > 0) (presentWeeksByWeekday[weekday] ??= new Set()).add(week);
  }

  const rules = [];
  for (const [weekday, possible] of Object.entries(allWeeksByWeekday)) {
    const present = presentWeeksByWeekday[weekday];
    if (!present || present.size === 0) continue;
    const isWeekly = [...possible].every((w) => present.has(w));
    rules.push({
      weekday: Number(weekday),
      weeksOfMonth: isWeekly ? null : [...present].sort((a, b) => a - b),
    });
  }
  return { rules, inconsistent };
}

function toRuleJson(r) {
  const json = { weekday: r.weekday };
  if (r.weeksOfMonth !== null) json.weeksOfMonth = r.weeksOfMonth;
  return json;
}

// --- 郵便番号データ ---

async function fetchPostalCsv() {
  const res = await fetch(POSTAL_ZIP_URL);
  if (!res.ok) throw new Error(`郵便番号データの取得に失敗しました: ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const tmpZip = path.join(os.tmpdir(), `ken_all_${Date.now()}.zip`);
  await writeFile(tmpZip, buf);
  try {
    // -p: 展開先を作らずファイル内容を標準出力に流す
    const csv = execFileSync('unzip', ['-p', tmpZip], {
      maxBuffer: 1024 * 1024 * 64,
    }).toString('utf8');
    return csv;
  } finally {
    await rm(tmpZip, { force: true });
  }
}

// 町丁目名から丁目番号・かっこ書きを取り除いたベース名を作る。
// 郵便番号は多くの場合「丁目」単位ではなく町丁目全体に1つ振られているため、
// このベース名同士を突き合わせる。
function baseTownName(s) {
  const m = s.match(/^[^0-9０-９（]+/);
  return (m ? m[0] : s).trim();
}

function parsePostalCsv(csv) {
  // ward -> baseName -> Set(postalCode)
  const index = {};
  for (const line of csv.split('\n')) {
    if (!line) continue;
    const cols = line.split(',').map((c) => c.replace(/^"|"$/g, ''));
    const postalCode = cols[2];
    const city = cols[7];
    const town = cols[8];
    if (!city || !city.startsWith('さいたま市')) continue;
    const ward = city.replace('さいたま市', '');
    const base = baseTownName(town);
    index[ward] ??= {};
    index[ward][base] ??= new Set();
    index[ward][base].add(postalCode);
  }
  return index;
}

function buildPostalAreas(areasOut, areaItemsById, postalIndex) {
  const postalToAreaIds = {}; // postalCode -> Set(areaId)
  const unmatched = [];

  for (const area of areasOut) {
    const items = areaItemsById.get(area.id) ?? [];
    for (const item of items) {
      const base = baseTownName(item);
      const codes = postalIndex[area.ward]?.[base];
      if (!codes || codes.size === 0) {
        unmatched.push({ areaId: area.id, ward: area.ward, item });
        continue;
      }
      for (const code of codes) {
        postalToAreaIds[code] ??= new Set();
        postalToAreaIds[code].add(area.id);
      }
    }
  }

  return {
    postalAreas: Object.fromEntries(
      Object.entries(postalToAreaIds).map(([code, ids]) => [code, [...ids].sort()])
    ),
    unmatched,
  };
}

async function main() {
  console.log('area/type/calendar を取得中...');
  const [areaData, calendarData] = await Promise.all([
    fetchJsonp('area'),
    fetchJsonp('calendar'),
  ]);

  const areaNames = {}; // areaID -> "【区】::町丁目、町丁目、★町丁目..."
  for (const d of areaData.array.dict) {
    const [id, name] = d.string;
    areaNames[id] = name;
  }

  const perArea = buildPerAreaCalendar(calendarData);

  const groupMismatches = checkGroupCoOccurrence(perArea);
  if (groupMismatches.length > 0) {
    console.error(
      `資源物1類/2類のグループ化の前提が崩れているデータが${groupMismatches.length}件あります。` +
        'カテゴリ分けの見直しが必要なため中断します。'
    );
    console.error(groupMismatches.slice(0, 5));
    process.exit(1);
  }
  console.log('資源物1類/2類のグループ化チェック: OK（不一致0件）');

  const areasOut = [];
  const areaItemsById = new Map(); // 郵便番号突き合わせ用に、生成後も町丁目アイテムを保持
  let inconsistentCount = 0;

  for (const [areaID, rawName] of Object.entries(areaNames)) {
    const entries = perArea[areaID] ?? [];
    const rulesByCategory = {};
    for (const cat of CATEGORY_ORDER) {
      const { rules, inconsistent } = inferRulesForCategory(entries, CATEGORY_TYPES[cat]);
      rulesByCategory[cat] = rules;
      inconsistentCount += inconsistent.length;
      if (inconsistent.length > 0) {
        console.warn(`areaID=${areaID} ${cat}: 月をまたいで一貫しないパターンを検出`, inconsistent.slice(0, 3));
      }
    }
    const rulesJson = {};
    for (const cat of CATEGORY_ORDER) {
      if (rulesByCategory[cat].length > 0) rulesJson[cat] = rulesByCategory[cat].map(toRuleJson);
    }

    const [wardBracket, chomeString] = rawName.split('::');
    const ward = wardBracket.replace(/[【】]/g, '');
    const chomeItems = chomeString.split('、').map((s) => s.trim()).filter(Boolean);
    const starred = chomeItems.filter((s) => s.startsWith('★')).map((s) => s.slice(1));
    const plain = chomeItems.filter((s) => !s.startsWith('★'));

    const note = `さいたま市「収集日カレンダー」から自動生成（scripts/update_areas_json.mjs、取得日:${
      new Date().toISOString().slice(0, 10)
    }、areaID=${areaID}）`;

    function pushEntry(idSuffix, chomeList, earlyMorning) {
      const id = `gomisuke-${areaID}${idSuffix}`;
      areasOut.push({ id, ward, name: chomeList.join('・'), earlyMorning, note, rules: rulesJson });
      areaItemsById.set(id, chomeList);
    }

    if (starred.length > 0 && plain.length > 0) {
      pushEntry('-am', starred, true);
      pushEntry('-std', plain, false);
    } else if (starred.length > 0) {
      pushEntry('', starred, true);
    } else {
      pushEntry('', plain, false);
    }
  }

  if (inconsistentCount > 0) {
    console.warn(
      `月をまたいで一貫しない曜日パターンが${inconsistentCount}件ありました。` +
        '該当地区は生成結果を目視で確認してください。'
    );
  }

  console.log('日本郵便の郵便番号データを取得中...');
  const postalCsv = await fetchPostalCsv();
  const postalIndex = parsePostalCsv(postalCsv);
  const { postalAreas, unmatched } = buildPostalAreas(areasOut, areaItemsById, postalIndex);

  const totalCodes = Object.keys(postalAreas).length;
  const ambiguousCodes = Object.values(postalAreas).filter((ids) => ids.length > 1).length;
  console.log(
    `郵便番号マッチ: ${totalCodes}件の郵便番号が地区に対応（うち${ambiguousCodes}件は複数地区にまたがる）`
  );
  if (unmatched.length > 0) {
    console.warn(
      `郵便番号が見つからなかった町丁目が${unmatched.length}件あります` +
        '（団地名など、郵便番号データ側に個別の項目がないもの。実害はなく、' +
        'その町丁目は郵便番号検索の対象から外れるだけ）'
    );
    console.warn(unmatched);
  }

  const existing = JSON.parse(await readFile(AREAS_JSON_PATH, 'utf8'));
  const updated = {
    ...existing,
    areas: areasOut,
    postalAreas,
  };
  await writeFile(AREAS_JSON_PATH, JSON.stringify(updated, null, 2) + '\n', 'utf8');

  console.log(
    `完了: ${areasOut.length}件の地区と${totalCodes}件の郵便番号対応を assets/data/areas.json に書き込みました。`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
