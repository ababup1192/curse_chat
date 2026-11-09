# 素材の出典とライセンス

このゲームの効果音・環境音・絵・フォントの出典です。
ゲームの中のクレジット（タイトル画面の「クレジット」と、物語を読み終えた後）にも同じ表記を流します（`assets/novel.credits.json`）。
素材を差し替えたら、ここと `assets/novel.credits.json` の両方を書き直してください。

## シナリオ

- 『呪いのチャット』の本文と演出の指示は、依頼主の設計書（`呪いのチャット(1).txt`）の字のまま `assets/talk/curse_chat.yarn` に写しています。

## 効果音

| 使った所 | 元の音 | 作者 | ライセンス |
|---|---|---|---|
| `se_post`（発言のポコッ）・`se_join`（入室）・`se_leave`（退出）・`se_drip`（背後の足音のピチャ）・`se_behind`（最後のピチャッ） | ポン（decision34）／ピロン（decision40）／ピチャッ（water-drop2） | [効果音ラボ](https://soundeffect-lab.info/) | 効果音ラボ利用規約（商用利用可・クレジット表記任意） |
| `amb_static` / `amb_static_loud`（テレビの砂嵐） | [TV Static](https://freesound.org/people/Jace/sounds/35291/) | Jace | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `amb_water`（濡れた床を歩く足音） | [濡れたタイルを裸足で歩く足音](https://freesound.org/people/SpliceSound/sounds/338106/) | SpliceSound | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `se_thud`（キャスターが倒れる音） | [木の床に倒れる音（thud）](https://freesound.org/people/Breviceps/sounds/447922/) | Breviceps | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `se_howl`（マイクのハウリング） | [マイクのハウリング（feedback）](https://freesound.org/people/JavierSerrat/sounds/470111/) | JavierSerrat | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |
| `amb_room`（静かな部屋） | [静かな部屋のホワイトノイズ（room tone）](https://freesound.org/people/Littleboot/sounds/147300/) | Littleboot | [CC0 1.0](http://creativecommons.org/publicdomain/zero/1.0/) |

freesound の音は、各ページのプレビュー（高音質 mp3）を元に、切り出し・音量調整・ループ加工をして作っています。
返事の音（`ui_*`）は `art/sfx.snd.star` から `bin/fge snd build` で合成した物です。

## 絵

- `assets/gpt/` の画像（アバター 4 つ・部屋・水浸しの部屋・ニュースのスタジオ 2 枚・水滴・血文字・タイトル）は、
  すべて ChatGPT（OpenAI の画像生成。codex-cli 経由）で生成した物です。
- 字とチャットの枠、画像がまだ届いていない間の部品は、エンジンの図形とシェーダーで描いています。

## フォント

- **M PLUS Rounded 1c Bold**（`assets/MPLUSRounded1c-Bold.subset.ttf`。チャットアプリの字）— Copyright 2016 The Rounded M+ Project Authors。
  [SIL Open Font License 1.1](assets/OFL.txt)。
- **しっぽり明朝**（`assets/ShipporiMincho-Regular.subset.ttf`。地の文・題・血文字）— Copyright 2021 The Shippori Mincho Project Authors
  （https://github.com/fontdasu/ShipporiMincho）。[SIL Open Font License 1.1](assets/OFL.txt)。

どちらも、ソースと Doc とシナリオに出てくる字だけを残した部分集合（サブセット）です。
シナリオや画面の言葉に新しい字を足したら、元のフォントから作り直してください（作り直すまで、その字は表示されません）:

```
python3 -m fontTools.subset <元のフォント> --text-file=<使う字を並べたファイル> --output-file=assets/<名前>.subset.ttf --layout-features='*'
```
