#!/usr/bin/env node
// さいたま市公式サイトの「収集日カレンダー」（p042612.html?page=area）が内部で使っている
// gomisuke（ごみすけ）ウィジェットのデータAPIから、地区ごとの収集曜日を取得して
// assets/data/areas.json の `areas` 配列を生成し直す。
//
// エンドポイントはウィジェットの通信をブラウザの開発者ツール相当（Playwright）で
// 観察して見つけたもので、公式に文書化されたAPIではない。ベンダーが変更すれば
// 壊れる前提で、実行結果は必ず目視確認してからコミットすること。
//
// 使い方: node scripts/update_areas_json.mjs
//   （Node 18+ を想定。fetchが標準搭載されているバージョンならこれ以外の依存は不要）
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
//   5. 既存の areas.json の presets・disclaimer・source は保持し、areas だけ差し替える

import { writeFile, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const AREAS_JSON_PATH = path.join(__dirname, '..', 'assets', 'data', 'areas.json');

const API_BASE = 'https://admin.gomisuke.jp/app/0017/api/jsonp.php';

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
      areasOut.push({
        id: `gomisuke-${areaID}${idSuffix}`,
        ward,
        name: chomeList.join('・'),
        earlyMorning,
        note,
        rules: rulesJson,
      });
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

  const existing = JSON.parse(await readFile(AREAS_JSON_PATH, 'utf8'));
  const updated = {
    ...existing,
    areas: areasOut,
  };
  await writeFile(AREAS_JSON_PATH, JSON.stringify(updated, null, 2) + '\n', 'utf8');

  console.log(`完了: ${areasOut.length}件の地区を assets/data/areas.json に書き込みました。`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
