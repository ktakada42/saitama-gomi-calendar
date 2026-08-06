#!/usr/bin/env node
// さいたま市「家庭ごみの出し方マニュアル」PDFに含まれる「地区別ごみ収集曜日一覧表」
// （町丁目ごとの収集曜日を市が自ら公開している一覧）から、
// assets/data/areas.json の `areas` 配列を生成し直す。あわせて日本郵便の郵便番号データと
// 突き合わせて `postalAreas`（郵便番号→地区IDの候補一覧）も生成する。
//
// 【経緯】以前はさいたま市公式サイトが内部で使っている第三者ベンダー
// (gomisuke/株式会社G-Place)の非公開APIからこのデータを生成していたが、
// gomisukeは自治体向けの有料SaaS製品であり、その編集済みデータベースを
// アプリに同梱することには著作権・利用規約上の懸念があった（#18）。
// 現在は市が自ら配布しているPDFマニュアルの一覧表を直接読み取る方式に切り替えている。
// gomisukeへの依存は無くなった。
//
// 使い方: node scripts/update_areas_json.mjs
//   （Node 18+ を想定。fetchが標準搭載されているバージョンならこれ以外の依存は不要。
//   　ただし内部で呼ぶ scripts/extract_manual_schedule.py が pdfplumber を必要とする。
//   　事前に `python3 -m venv .venv && .venv/bin/pip install pdfplumber` しておくこと。
//   　郵便番号データはZIP配布なので、システムの`unzip`コマンドも使う。）
//
// 何をしているか:
//   1. scripts/extract_manual_schedule.py を実行し、PDFの「地区別ごみ収集曜日一覧表」から
//      町丁目ごとの収集曜日（CollectionRuleと同じ weekday の形）を抽出する
//      （PDFの取得・解析はPythonのpdfplumber側で完結し、こちらは結果のJSONを受け取るだけ）
//   2. 日本郵便の「住所の郵便番号」全国データ（KEN_ALL）からさいたま市の行を抜き出し、
//      町丁目名（丁目番号・かっこ書きを除いたベース名）でareasの各地区と突き合わせて
//      郵便番号→地区ID候補のマップを作る。1つの郵便番号が複数の地区にまたがることが
//      実際にあるため、「1件に絞れる」保証はしない。候補が複数残ったらUI側で選ばせる前提。
//   3. 既存の areas.json の presets・disclaimer・source は保持し、
//      areas・postalAreas だけ差し替える

import { writeFile, readFile, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const AREAS_JSON_PATH = path.join(__dirname, '..', 'assets', 'data', 'areas.json');

const POSTAL_ZIP_URL =
  'https://www.post.japanpost.jp/service/search/zipcode/download/utf/zip/utf_ken_all.zip';

// --- PDFからの地区データ抽出（Python側に委譲） ---

function extractAreasFromManual() {
  const venvPython = path.join(__dirname, '..', '.venv', 'bin', 'python3');
  const python = fs.existsSync(venvPython) ? venvPython : 'python3';
  const scriptPath = path.join(__dirname, 'extract_manual_schedule.py');
  console.log('マニュアルPDFから地区別収集曜日一覧表を抽出中...');
  const stdout = execFileSync(python, [scriptPath], {
    maxBuffer: 1024 * 1024 * 16,
    stdio: ['ignore', 'pipe', 'inherit'], // stderrはそのまま進捗ログとして流す
  });
  return JSON.parse(stdout.toString('utf8'));
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

function buildPostalAreas(areasOut, postalIndex) {
  const postalToAreaIds = {}; // postalCode -> Set(areaId)
  const unmatched = [];

  for (const area of areasOut) {
    const base = baseTownName(area.name);
    const codes = postalIndex[area.ward]?.[base];
    if (!codes || codes.size === 0) {
      unmatched.push({ areaId: area.id, ward: area.ward, name: area.name });
      continue;
    }
    for (const code of codes) {
      postalToAreaIds[code] ??= new Set();
      postalToAreaIds[code].add(area.id);
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
  const areasOut = extractAreasFromManual();
  console.log(`地区データ: ${areasOut.length}件を取得しました。`);

  console.log('日本郵便の郵便番号データを取得中...');
  const postalCsv = await fetchPostalCsv();
  const postalIndex = parsePostalCsv(postalCsv);
  const { postalAreas, unmatched } = buildPostalAreas(areasOut, postalIndex);

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
