# 呪いのチャット

深夜 23:41。大学のゲーム仲間 3 人（甘夏・かーぼー・関西ボーイ）がいつものサーバーに集まる。
他愛もない話の途中で、関西ボーイが「水の音がする」と言い出し、標準語で話し始める——。
チャットアプリの画面そのものが舞台のホラーのチャット型ノベル。5 分ほどで読み終わる一本道（選択肢は無い）。
flix_game_engine の sound-novel-starter から作り替えた。

- 発言は打っている時間（「○○が入力中…」・自分の発言は入力欄に一字ずつ）を経てチャットに入り、ポコッと鳴って、間をおいて勝手に流れる。
- 地の文（かーぼーの心の声）はチャットを沈めて画面の中央に明朝で浮かび、押すまで待つ。
- 恐怖が進むほど画面が冷え、最後はテレビのニュース → 真っ暗な画面 → 一瞬の血文字。
- 絵の部品（アバター・部屋・テレビ・水滴・血文字・タイトル）は ChatGPT で作った画像（`assets/gpt/`）を貼り、字とチャットの枠はエンジンで描く。
  画像が届いていない部品は、その部品だけ図形で描く。地の文の背景の有無（`backdrop`: `room` = 部屋の絵・`none` = 背景なしで UI を沈める）は
  `assets/chat.art.json` の 1 欄で切り替える。

## 始め方

| コマンド | 何をするか |
|---|---|
| `make run`    | ゲームを起動する（ウィンドウが開く。**音量注意・ヘッドホン推奨**） |
| `make debug`  | 保存即反映(watchFile)と F8 を有効にして起動 |
| `make check`  | 型検査だけ（一番速い確認） |
| `make test`   | テスト（規則・Doc の橋渡し・性質テスト） |
| `make render SHOT=chat` | その場面だけ `debug/chat.png` へ描き出す（場面の名前は下の表） |
| `make render-all` | ギャラリー PNG を全部描き出す（場面・背景なし・小さい画面） |
| `make flow FLOW=e2e/full.flow` | タイトル画面からクレジットまでを画面なしで流す（`e2e/bookmark.flow` はクイックセーブとロード） |
| `bin/fge yarn build assets/talk` | シナリオを直した後に木（`assets/talk/dialogue.json`）を書き直す |

描き出しの場面: `title` `chat`（甘夏が入力中）`chat-kaabo`（入力欄に打っている途中）`join` `thought` `glitch` `chill` `tv` `tv-water` `dark` `scare`
`log` `save` `settings` `credits`。背景なしは `none-chat` `none-thought`。小さい画面は `small-title` `small-chat` `small-thought` `small-save` `small-settings`。

## 遊び方

クリック / Enter / Space / Z: 打っている途中ならすぐ送信、出し終えた後なら間を飛ばして次へ。地の文は押して進める。
上の帯の右のボタンか、キーで:

| 操作 | キー |
|---|---|
| 戻る（1 つ前の行から読み直す。ロールバック） | PageUp / R |
| バックログ（ホイールを上へでも開く。行を押すとそこへ戻る） | L |
| オート（地の文も読み終えて少し待つと送る） | O |
| スキップ（既定は読んだ行だけ。真っ暗な画面に入ると止まる） | K / Tab |
| クイックセーブ・クイックロード | F5 / F9 |
| セーブ・ロード・設定・タイトルへ | 上の帯のボタン（テレビと暗転の間はボタンを出さない。キーは効く） |

キーの割り当ては `assets/novel.keys.json`。セーブ・既読・設定は `saves/novel.json` に残る（git には入れない）。

## どこで読むか

| 機能 | 書く所 | 読む所 |
|---|---|---|
| 発言・地の文・字幕・話し手 | `assets/talk/curse_chat.yarn`（Yarn Spinner の書き方。`amanatsu:` `kaabo:` `kansai:` `caster:`） | `WorldRead.absorb` / `showLine` |
| 発言が打たれて流れる（打つ速さ・間・時刻） | `assets/chat.pace.json`・タグ `#gap:long` `#gap:longer` | `WorldRead.readOn` / `autoOrSkip`・`PaceDoc.gapSeconds` |
| チャットの履歴・入退室・地の文のまとまり | `<<join 名>>` `<<leave 名>>` | `Page.show` / `notice`・`View.feedLayer` / `thoughtLayer` |
| 偽物に入れ替わる・崩れた発言 | タグ `#impostor` `#glitch` | `Stage.withImpostor`・`View.avatar` / `glitchRows` |
| 画面（チャット・テレビ・暗転）・血文字 | `<<chat>>` `<<tv caster|fallen|static>>` `<<dark>>` `<<scare 字>>` | `Stage.applyCue`・`View.readingScene` |
| 環境音の層・効果音 | `<<ambience 名 音量>>` `<<ambience 名 off>>` `<<silence>>` `<<se 名>>` | `Controls.ambience` / `soundOf`・音量は `assets/novel.mixer.json`（大音量は loud のバスが上限） |
| 冷え・水滴・揺れ・待ち | `<<chill 目標 秒>>` `<<drops on|off>>` `<<shake>>` `<<wait 秒>>` | `Stage.chillAt`・`View.chillLayer` / `dropsLayer` |
| 絵の部品と背景の有無 | `assets/chat.art.json` | `Art.imageOf`・`View.avatar` / `tvPicture` / `roomLayer` |
| セーブ・ロード・ロールバック | — | `WorldRead.restore`（ブックマークを当て直す。前のノードから持ち越す舞台は `Saves.Mark`） |
| ブラウザ版で絵と音を裏で取る | `project.json` の `web.deferred` | `Game.withAssetLoading`・`WorldRead` の「素材の待ち」 |

## 読む順

1. `make run` で一度読み終える。
2. `assets/talk/curse_chat.yarn` を読む。頭のコメントに、書けるコマンドとタグの一覧がある。
3. コードは **入口 → 状態 → 描画 → 入力** の順: `src/Game.flix`（目次と毎フレームの流れ）→ `src/Res.flix`（Doc とシナリオ）→
   `src/World.flix`（状態の形）→ `src/WorldRead.flix`（読み進める規則）→ `src/Stage.flix` と `src/Page.flix`（舞台と履歴）→
   `src/View.flix`（絵。画像を貼る部品は `View.imageOf` を呼ぶ所）→ `src/Controls.flix`（入力・音・Doc の読み直し）。
4. `assets/*.json` の数値や色を変えて、`make debug` で保存即反映を見る（打つ速さ・発言の間・冷え・3 人の色・背景の有無）。

## 素材を差し替える

- **絵**: `assets/gpt/` の画像を同じ名前で置き換える（960×540・アバターは 128×128）。名前は `project.json` の `textures` と `src/Art.flix` の `Art.textureOf`。
- **音**: `assets/sfx/` の WAV。出典は `CREDITS.md` と `assets/novel.credits.json` の両方に書く。
- **字**: `project.json` の `fonts`（default = 丸ゴシック・mincho = 明朝）。使う字だけに縮めた subset を置いている（新しい字を足したら作り直す。手順は `CREDITS.md`）。
