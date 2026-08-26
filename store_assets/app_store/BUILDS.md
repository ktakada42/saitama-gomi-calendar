# ビルドの記録

`scripts/build_testflight.sh` でTestFlightに上げるたびに、末尾の表へ1行自動で
足す。「このビルドはどのコミットから作ったか」をあとから迷わないための記録。

v1.1.1（ビルド23）の審査が通ったあと、ビルドしたコミットが分からなくなった
（`git log` の中から近そうなコミットを当て推量し、実際は違った）ことを機に作った。
ビルド時点の`git status`は、ビルドが終われば失われる。表に残すのはそこだけ。

## 読み方

- **元のSHA** … ビルドした瞬間の `git rev-parse HEAD`。作業ツリーが dirty
  のときは、そこに乗っていた未コミットの変更まではこの列だけでは分からない
  （「作業ツリー」の列で件数だけ分かる）
- **作業ツリー** … `git status --porcelain` が空なら `clean`。空でなければ
  `dirty（N件）`
- **対応するコミット** … dirtyだったビルドについて、実際に配信された内容と
  一致するコミットが判明したら手で埋める。`git merge --ff-only` した直後などに。
  スクリーンショットやドキュメントだけの差分（バイナリに影響しない変更）なら
  「一致する」とみなしてよい。cleanなビルドは元のSHAと同じなので書かない
- **Delivery UUID** … `xcrun altool --upload-app` の出力から拾う。
  App Store Connect側でアップロードを特定するための番号

新しい行がいちばん下に来るよう、スクリプトはファイルの末尾に追記する。
**そのため、この表より下には何も書かないこと。** 手で埋めるのは
「対応するコミット」列だけ。

以下の4行はこの仕組みを作る前のビルドを、分かる範囲で遡って埋めたもの。
1.1.1の2行はApp Store Connect APIの`uploadedDate`とコミット履歴の突き合わせで
特定できたが、1.0.0・1.1.0は`uploadedDate`を確認しておらず「不明」のままにした。
「不明」を後から埋める手立てはない。当時の`git status`もアップロード時刻も
残っていないため。

## 表

| ビルド | 日時（JST） | 元のSHA | 作業ツリー | 対応するコミット | Delivery UUID |
|---|---|---|---|---|---|
| 1.0.0+15 | 不明 | 不明 | 不明 | [`5355487`](https://github.com/ktakada42/saitama-gomi-calendar/commit/5355487)（タグ`v1.0.0`） | 不明 |
| 1.1.0+21 | 2026-08-17 23:46 | 不明 | 不明 | [`fdd759f`](https://github.com/ktakada42/saitama-gomi-calendar/commit/fdd759f)（タグ`v1.1.0`） | 不明 |
| 1.1.1+22 | 2026-08-23 12:28 | `1d5e8a0`（推定） | dirty（推定） | [`7bf363a`](https://github.com/ktakada42/saitama-gomi-calendar/commit/7bf363a)（タグ`v1.1.1`） | 不明 |
| 1.1.1+23 | 2026-08-23 15:12 | `1d5e8a0` | dirty（18件） | [`7bf363a`](https://github.com/ktakada42/saitama-gomi-calendar/commit/7bf363a)（タグ`v1.1.1`） | `17594c2d-9dd5-411e-81c7-57ef4da9e418` |
