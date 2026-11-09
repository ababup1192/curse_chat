// KindDoc — novel.kind.json（手触りの数: 字の大きさ・オートとスキップの間・揺れ・クレジット）の宣言ドキュメント層。
// 設定の画面で人が変える値（文字の速さ・オートの待ち・音量）の出発点もここ（変えた値はセーブの config が持つ）。
// チャットの流れ（打つ速さ・発言の間・時刻）は PaceDoc。
// fail-open — 読めない・壊れているときは defaults() へ落とし、ゲームは必ず起動する。
mod KindDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// bodySize / nameSize / lineGap = チャットの本文と名前の字の大きさと行の間（px）、thoughtSize / captionSize = 地の文とテレビの字幕の字の大きさ、
    /// cps / autoWait / masterVolume / ambienceVolume / seVolume = 設定の既定（地の文の 1 秒の字数・オートで地の文を出し終えてから送るまでの秒・
    /// 全体と環境音と効果音の音量 0〜1）、autoPerChar = オートの待ちに足す 1 字あたりの秒、skipInterval = スキップで 1 行を出す間（秒）、
    /// logMax = バックログに残す行の数、shakeSeconds / shakePx = <<shake>> の長さと揺れ幅、creditsSpeed = クレジットが流れる速さ（px/秒）、
    /// toastSeconds = 知らせを出す秒、holdFadeSeconds = 素材を待つ時に黒へ重ねる秒（戻す秒も同じ）、holdGiveUpSeconds = 黒のまま待って諦めるまでの秒、
    /// holdMarkSeconds = 黒になってから隅に待ちの印を出すまでの秒（ブラウザ版で後回しの環境音がまだ届いていない時）、
    /// *Slider = 設定の画面のスライダーの範囲と 1 押しの量（文字の速さの最大はノーウェイト = isNoWait）。
    pub type alias Rec = {
        version = Int32,
        bodySize = Float64,
        nameSize = Float64,
        lineGap = Float64,
        thoughtSize = Float64,
        captionSize = Float64,
        cps = Float64,
        autoWait = Float64,
        masterVolume = Float64,
        ambienceVolume = Float64,
        seVolume = Float64,
        autoPerChar = Float64,
        skipInterval = Float64,
        logMax = Int32,
        shakeSeconds = Float64,
        shakePx = Float64,
        creditsSpeed = Float64,
        toastSeconds = Float64,
        holdFadeSeconds = Float64,
        holdGiveUpSeconds = Float64,
        holdMarkSeconds = Float64,
        cpsSlider = Slider,
        autoWaitSlider = Slider,
        masterVolumeSlider = Slider,
        ambienceVolumeSlider = Slider,
        seVolumeSlider = Slider
    }

    /// スライダーの下限・上限・1 押しの量。
    pub type alias Slider = { min = Float64, max = Float64, step = Float64 }

    /// 型検査が record を展開しないため、World が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/novel.kind.json"

    /// コード側の既定値（assets/novel.kind.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 2, bodySize = 15.0, nameSize = 15.0, lineGap = 5.0, thoughtSize = 22.0, captionSize = 22.0,
                  cps = 40.0, autoWait = 1.6, masterVolume = 1.0, ambienceVolume = 0.8, seVolume = 0.8,
                  autoPerChar = 0.05, skipInterval = 0.06, logMax = 200, shakeSeconds = 0.6, shakePx = 10.0,
                  creditsSpeed = 34.0, toastSeconds = 1.6,
                  holdFadeSeconds = 0.4, holdGiveUpSeconds = 20.0, holdMarkSeconds = 0.4,
                  cpsSlider = { min = 10.0, max = 130.0, step = 10.0 }, autoWaitSlider = { min = 0.2, max = 4.0, step = 0.2 },
                  masterVolumeSlider = volume(), ambienceVolumeSlider = volume(), seVolumeSlider = volume() })

    def volume(): Slider = { min = 0.0, max = 1.0, step = 0.1 }

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let num = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        let int = (key, fallback) -> JsonCodec.intOr(key, fallback, root);
        let slider = (key, fallback: Slider) -> Map.get(key, root) |> Option.flatMap(JsonCodec.expectObject)
            |> Option.map(o -> { min = JsonCodec.floatOr("min", fallback#min, o), max = JsonCodec.floatOr("max", fallback#max, o),
                                 step = JsonCodec.floatOr("step", fallback#step, o) })
            |> Option.getWithDefault(fallback);
        Doc.Doc({ version = int("version", d#version),
                  bodySize = num("bodySize", d#bodySize), nameSize = num("nameSize", d#nameSize), lineGap = num("lineGap", d#lineGap),
                  thoughtSize = num("thoughtSize", d#thoughtSize), captionSize = num("captionSize", d#captionSize),
                  cps = num("cps", d#cps), autoWait = num("autoWait", d#autoWait),
                  masterVolume = num("masterVolume", d#masterVolume),
                  ambienceVolume = num("ambienceVolume", d#ambienceVolume), seVolume = num("seVolume", d#seVolume),
                  autoPerChar = num("autoPerChar", d#autoPerChar), skipInterval = num("skipInterval", d#skipInterval),
                  logMax = int("logMax", d#logMax),
                  shakeSeconds = num("shakeSeconds", d#shakeSeconds), shakePx = num("shakePx", d#shakePx),
                  creditsSpeed = num("creditsSpeed", d#creditsSpeed),
                  toastSeconds = num("toastSeconds", d#toastSeconds),
                  holdFadeSeconds = num("holdFadeSeconds", d#holdFadeSeconds),
                  holdGiveUpSeconds = num("holdGiveUpSeconds", d#holdGiveUpSeconds),
                  holdMarkSeconds = num("holdMarkSeconds", d#holdMarkSeconds),
                  cpsSlider = slider("cpsSlider", d#cpsSlider), autoWaitSlider = slider("autoWaitSlider", d#autoWaitSlider),
                  masterVolumeSlider = slider("masterVolumeSlider", d#masterVolumeSlider),
                  ambienceVolumeSlider = slider("ambienceVolumeSlider", d#ambienceVolumeSlider),
                  seVolumeSlider = slider("seVolumeSlider", d#seVolumeSlider) })

    /// 文字の速さがスライダーの最大か（= ノーウェイト。行を一度に全部出す）。
    pub def isNoWait(cps: Float64, kind: Doc): Bool = cps >= rec(kind)#cpsSlider#max

    /// 設定の文字の速さが既定の何倍か（発言の打つ速さに掛ける）。
    pub def speedRatio(cps: Float64, kind: Doc): Float64 =
        let base = rec(kind)#cps;
        if (base <= 0.0) 1.0 else cps / base

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
