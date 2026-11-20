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
| 1.2.0+24 | 2026-09-13 23:50 | [`0ccfb4c`](https://github.com/ktakada42/saitama-gomi-calendar/commit/0ccfb4cc2e71aaa6746ad4612d23e58aa981d1e9) | clean | – | `c2d98c1f-f7b9-4d88-92f9-04b4251bed80` |
| 1.3.0+25 | 2026-10-01 18:50 | [`a15c14c`](https://github.com/ktakada42/saitama-gomi-calendar/commit/a15c14cd8823918b2969b4dee6284e3928ee755e) | clean | – | `2ebbc6ce-313a-4e10-a81c-4308a58acc68` |
| 1.3.0+26 | 2026-10-01 23:43 | [`e28b8e2`](https://github.com/ktakada42/saitama-gomi-calendar/commit/e28b8e2a91758c7ebd46cb6f905be59d2f49c6e3) | clean | – | `3609ecfd-db09-4389-ba37-06ad68466620` |
| 1.3.0+27 | 2026-10-02 00:02 | [`58175f6`](https://github.com/ktakada42/saitama-gomi-calendar/commit/58175f642f1f0b0194684f7fbc34347aa14263db) | clean | – | `30f6752b-3b85-42fd-91c8-efabf6e99e7a` |
| 1.3.0+28 | 2026-10-02 04:17 | [`a86a158`](https://github.com/ktakada42/saitama-gomi-calendar/commit/a86a1585a486dcda1d4e10954d202dbfdd2079b1) | clean | – | `001ea4ba-db38-4b63-aa35-70db00d846cd` |
| 1.3.0+29 | 2026-10-02 07:41 | [`1b9fb65`](https://github.com/ktakada42/saitama-gomi-calendar/commit/1b9fb655925e17c2f47b3c728e3320f21ea9c86a) | clean | – | `c28bcf85-0241-4805-bcc2-7853154d4d30` |
| 1.4.0+30 | 2026-10-31 15:14 | [`24a14b4`](https://github.com/ktakada42/saitama-gomi-calendar/commit/24a14b463f7ea50d0b46cd2757254d905add3609) | clean | – | `c580f7c7-a0ee-49e5-a406-025da52ed945` |
| 1.4.1+31 | 2026-11-01 01:03 | [`3e660f0`](https://github.com/ktakada42/saitama-gomi-calendar/commit/3e660f06204aa2b81c66123df05e7c3812fde964) | clean | – | `18a598c3-ce34-4ee9-8804-782989734c3a` |
| 1.5.0+32 | 2026-11-17 01:47 | [`fe8a333`](https://github.com/ktakada42/saitama-gomi-calendar/commit/fe8a3332ffc331ce278f29daca597e550ae23f59) | clean | – | `7fd023f7-b495-440c-b4b2-9349b1ea08e1` |
| 1.5.0+33 | 2026-11-17 22:55 | [`d12f4b7`](https://github.com/ktakada42/saitama-gomi-calendar/commit/d12f4b72b2f1d76b57a92f3fc0703ea821f9b536) | clean | – | `722b7675-7b8d-4944-b0ce-b1191d464fe8` |
| 1.5.0+34 | 2026-11-18 00:09 | [`e5d4bee`](https://github.com/ktakada42/saitama-gomi-calendar/commit/e5d4beec5e66e8423e38d9016aad3b46c4d218d9) | clean | – | `715e526d-abf8-41cc-986f-23dd10d64728` |
| 1.5.0+35 | 2026-11-18 10:27 | [`55bd5b3`](https://github.com/ktakada42/saitama-gomi-calendar/commit/55bd5b3c0003bbc2305d6a9842f6fa822c6362e6) | clean | – | `1a5b92df-f667-4af4-a3c5-af2bf9c8b6cb` |
| 1.5.0+36 | 2026-11-19 08:52 | [`d66560c`](https://github.com/ktakada42/saitama-gomi-calendar/commit/d66560c75c5495b96230008a9eff4d5d2b48965e) | clean | – | `19099009-9960-45c0-b4d3-5e09fd607979` |
| 1.5.1+37 | 2026-11-20 11:05 | [`324e3f9`](https://github.com/ktakada42/saitama-gomi-calendar/commit/324e3f91c199be1b2f5346a133fb05e2ca4da725) | clean | – | `eca6c803-b26d-4594-9a06-6b3d1afff3d5` |
| 1.5.1+38 | 2026-11-20 21:53 | [`41dbab9`](https://github.com/ktakada42/saitama-gomi-calendar/commit/41dbab96f508372a3357ccd45cef06be9d2c7d13) | clean | – | `d4f09e62-d43b-42da-9a07-d9cbe9483327` |
