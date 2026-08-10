# 中継サーバー

AI分別相談（#44）のために Claude API へ中継する。Cloudflare Workers。

APIキーをアプリに埋め込むと必ず抜き出されるので、間に立てる。それだけが目的で、
それ以外の仕事はさせない。

## 何を受け取り、何を返すか

```
POST /v1/sort
  x-app-token: <合言葉>
  { "deviceId": "<UUID>", "question": "こわれた傘", "candidates": ["かさ", "電池", ...] }

→ 200 { "index": 0, "remainingToday": 19 }   候補の何番目か。該当なしなら index: null
→ 400 { "error": "bad_request", "field": "question" }
→ 401 { "error": "unauthorized" }
→ 429 { "error": "device_quota_exhausted" | "rate_limited", "retryAfterSec": 3600 }
→ 503 { "error": "budget_exceeded" | "upstream_unavailable" }
```

候補の絞り込みは端末側でやる。サーバーは**候補の中から1つ選ぶ**だけ。
だから、アプリが表示する区分は必ず市の資料に由来する。作り話の区分が画面に出る道が
構造として存在しない（`pickIndex` が候補に無い答えを捨てる）。

### 送られてこないもの

- 設定した地区・区名・丁目
- 郵便番号
- 端末を識別できる情報

`deviceId` は端末が初回に作る乱数（UUID）で、機種や個人には結びつかない。
入れ直せば変わる。だから**回数制限の本命はこれではなく、IPのほう**。

### 記録しないもの

**質問文と候補は、ログにも残さない。** プライバシーポリシーにそう書く以上、実装でも守る。
`src/index.ts` の先頭にも同じことを書いてある。失敗を書き残すときも、種類と件数だけにする。

なお、質問文は Claude API（Anthropic）には渡る。ここは避けようがないので、
プライバシーポリシーにも「AI相談を使ったときだけ、質問文が送信される」と書く。

## 安全弁

広告を入れない（#40）ので、API代はそのまま開発者に来る。**使いすぎを止める仕組みを
最初から入れてある**。上限はすべて `wrangler.jsonc` の `vars` にあり、コードを触らずに
締められる。

| 段 | 何を止めるか | 既定値 |
|---|---|---|
| 入力の大きさ | 長文を送りつけてトークン代を焼く | 質問100文字／候補30件・各40文字 |
| 出力の長さ | 1回あたりの費用に天井を作る | `max_tokens: 64` |
| 端末ごと | ふつうの使いすぎ | 20問/日 |
| IPごと | 端末IDを作り直しての回避 | 60問/日 |
| IPごと（短時間） | 機械的な連打 | 5問/分 |
| **日額** | **1日で使い切って月末まで止まるのを防ぐ** | **300円/日** |
| **月額** | **想定外の請求** | **3,000円/月** |

金額は見積もりではなく、**APIが返した実際のトークン数**から積む。見積もりで積むと、
想定より長い応答が続いたときに上限をすり抜ける。

区切りは日本時間。UTCで切ると、日本の朝9時に回数が戻ってしまう。

数え上げは Durable Object 1つに集約している。KVのような結果整合の置き場だと、
同時に来た分を数え落として上限をすり抜ける。

### もう一段、コードの外にも置くこと

上の安全弁は**こちらのコードが正しく動く前提**に立っている。バグで効かなくなる目は
残るので、Anthropic Console 側にも上限を置く。

1. Anthropic Console → Settings → Limits で、ワークスペースの月額上限を設定する
2. 併せて請求の通知を有効にする

こちらは実装と無関係に効くので、最後の砦になる。**これを設定してから運用に入ること。**

## 使い方

```bash
npm ci
npm test          # 60件。安全弁の検査が中心
npm run typecheck
npm run dev       # 手元で動かす（.dev.vars が要る）
npm run deploy
```

### 秘密の値

リポジトリには置かない。`wrangler secret put` で入れる。

```bash
npx wrangler secret put ANTHROPIC_API_KEY   # Claude APIのキー
npx wrangler secret put APP_TOKEN           # アプリに埋め込む合言葉
npx wrangler secret put IP_SALT             # IPをそのまま持たないためのハッシュの種
npx wrangler secret put ADMIN_TOKEN         # 使用額を見るときの合言葉
```

`APP_TOKEN` は**アプリから抜き出せる**。URLを見つけただけの相手を弾く一段目でしかなく、
防御の本命ではない。本命は上の回数制限と金額の上限。

手元で動かすときは `.dev.vars`（gitignore 済み）に同じ4つを書く。

### いくら使ったか

```bash
curl -H "x-admin-token: $ADMIN_TOKEN" https://<ワーカーのURL>/v1/status
```

```json
{
  "day": "2026-08-10", "month": "2026-08",
  "spentTodayJpy": 12.5, "spentMonthJpy": 148.2,
  "dailyBudgetJpy": 300, "monthlyBudgetJpy": 3000
}
```

## プロンプトを変えるとき

`src/claude.ts` の `PROMPT` は #41 の精度検証（`scripts/ai_eval/run_eval.py`）で使ったものと
**同じ文言**にしてある。測った精度をそのまま引き継ぐため。

変えるなら、検証を回し直してから変えること。文言だけ直して精度が落ちても気づけない。
