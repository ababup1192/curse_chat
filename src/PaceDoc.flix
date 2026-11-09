// PaceDoc — chat.pace.json（チャットの流れの数: 打つ速さ・発言の間・時刻・履歴の長さ・地の文の層・血文字の秒）の宣言ドキュメント層。
// 字の大きさ・オート・スキップ・音量の既定は novel.kind.json（設定の画面の出発点）、ここはチャットの流れだけ。
// fail-open — 読めない・壊れているときは defaults() へ落とし、ゲームは必ず起動する。
mod PaceDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// chatClockStart = 最初の発言の時刻（"23:41"）、minutesPerPost = 発言 1 つで進む分、
    /// amanatsuCps / kaaboCps / kansaiCps / casterCps = 打つ・字幕を出す速さ（1 秒の字数。設定の「文字の速さ」が既定の何倍かを掛ける）、
    /// gapBase / gapPerChar = 発言を出し終えてから次へ流すまでの秒と、1 字あたりに足す秒、gapLong / gapLonger = #gap:long / longer で足す秒、
    /// feedMax = チャットの履歴に残す行の数、slideSeconds = 新しい発言が下から入って履歴を押し上げる秒、
    /// thoughtDim = 地の文の層でチャットを沈める濃さ（0〜1）、thoughtFadeSeconds = 地の文の層が出る・消える秒、
    /// scareSeconds = 血文字を出している秒。
    pub type alias Rec = {
        version = Int32,
        chatClockStart = String,
        minutesPerPost = Float64,
        amanatsuCps = Float64,
        kaaboCps = Float64,
        kansaiCps = Float64,
        casterCps = Float64,
        gapBase = Float64,
        gapPerChar = Float64,
        gapLong = Float64,
        gapLonger = Float64,
        feedMax = Int32,
        slideSeconds = Float64,
        thoughtDim = Float64,
        thoughtFadeSeconds = Float64,
        scareSeconds = Float64
    }

    /// 型検査が record を展開しないため、World が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/chat.pace.json"

    /// コード側の既定値（assets/chat.pace.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, chatClockStart = "23:41", minutesPerPost = 0.25,
                  amanatsuCps = 15.0, kaaboCps = 10.0, kansaiCps = 17.0, casterCps = 16.0,
                  gapBase = 0.9, gapPerChar = 0.06, gapLong = 1.8, gapLonger = 3.2,
                  feedMax = 40, slideSeconds = 0.24, thoughtDim = 0.82, thoughtFadeSeconds = 0.6, scareSeconds = 0.7 })

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let num = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  chatClockStart = JsonCodec.stringOr("chatClockStart", d#chatClockStart, root),
                  minutesPerPost = num("minutesPerPost", d#minutesPerPost),
                  amanatsuCps = num("amanatsuCps", d#amanatsuCps), kaaboCps = num("kaaboCps", d#kaaboCps),
                  kansaiCps = num("kansaiCps", d#kansaiCps), casterCps = num("casterCps", d#casterCps),
                  gapBase = num("gapBase", d#gapBase), gapPerChar = num("gapPerChar", d#gapPerChar),
                  gapLong = num("gapLong", d#gapLong), gapLonger = num("gapLonger", d#gapLonger),
                  feedMax = JsonCodec.intOr("feedMax", d#feedMax, root), slideSeconds = num("slideSeconds", d#slideSeconds),
                  thoughtDim = num("thoughtDim", d#thoughtDim), thoughtFadeSeconds = num("thoughtFadeSeconds", d#thoughtFadeSeconds),
                  scareSeconds = num("scareSeconds", d#scareSeconds) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)

    /// 話し手の打つ速さ（1 秒の字数・設定の倍率を掛ける前）。
    pub def cpsOf(speaker: Talk.Speaker, pace: Doc): Float64 =
        let r = rec(pace);
        match speaker {
            case Talk.Speaker.Amanatsu => r#amanatsuCps
            case Talk.Speaker.Kaabo    => r#kaaboCps
            case Talk.Speaker.Kansai   => r#kansaiCps
            case Talk.Speaker.Caster   => r#casterCps
        }

    /// 発言を出し終えてから次へ流すまでの秒（字数 chars・タグの段 gap）。
    pub def gapSeconds(chars: Int32, gap: Talk.Gap, pace: Doc): Float64 =
        let r = rec(pace);
        let extra = match gap {
            case Talk.Gap.Normal => 0.0
            case Talk.Gap.Long   => r#gapLong
            case Talk.Gap.Longer => r#gapLonger
        };
        r#gapBase + Int32.toFloat64(chars) * r#gapPerChar + extra

    /// 最初の発言の時刻（0 時からの分）。読めない字なら 23:41。
    pub def startMinutes(pace: Doc): Int32 =
        let parsed = match String.splitOn(substr = ":", rec(pace)#chatClockStart) {
            case h :: m :: Nil => forM (hh <- Int32.fromString(String.trim(h)); mm <- Int32.fromString(String.trim(m))) yield hh * 60 + mm
            case _             => None
        };
        parsed |> Option.getWithDefault(23 * 60 + 41)

    /// posted 番目（0 から）の発言の時刻の字（"23:41"。24 時を回れば 0 時へ）。
    pub def clockText(posted: Int32, pace: Doc): String =
        let passed = Float64.floor(Int32.toFloat64(posted) * rec(pace)#minutesPerPost) |> Float64.tryToInt32 |> Option.getWithDefault(0);
        let minutes = Int32.modulo(startMinutes(pace) + passed, 24 * 60);
        let pad = (n: Int32) -> if (n < 10) "0${n}" else "${n}";
        "${pad(minutes / 60)}:${pad(Int32.remainder(minutes, 60))}"
}
