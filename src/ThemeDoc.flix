// ThemeDoc — novel.theme.json（色）の宣言ドキュメント層。チャットアプリの地と字・3 人の色・水と血の色。
// fail-open — 読めない綴りの色は既定の色のまま。
mod ThemeDoc {
    use fge::{Color, DocJson, JsonCodec}
    use Util.Json.Json

    /// rail / sidebar / chat = チャットアプリの左端の列・チャンネルの列・会話の地（奥ほど暗い灰紺）、
    /// ink = 字、inkDim = 添え書き（時刻・入退室・案内）、accent = 選んでいる物・オートとスキップの点灯、
    /// amanatsu / kaabo / kansai = 3 人の名前の字とアバターの縁、water = 冷えと水滴の青白、blood = 血文字（最後の 1 回だけ）、
    /// thought = 地の文の字。
    pub type alias Rec = {
        version = Int32,
        rail = Color,
        sidebar = Color,
        chat = Color,
        ink = Color,
        inkDim = Color,
        accent = Color,
        amanatsu = Color,
        kaabo = Color,
        kansai = Color,
        water = Color,
        blood = Color,
        thought = Color
    }

    /// 型検査が record を展開しないため、World が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/novel.theme.json"

    def hex(code: String): Color = Color.hex(code) |> Option.getWithDefault({ r = 1.0, g = 0.0, b = 1.0 })

    pub def defaults(): Doc =
        Doc.Doc({ version = 2, rail = hex("#15171d"), sidebar = hex("#1c1f27"), chat = hex("#242832"),
                  ink = hex("#dfe2ea"), inkDim = hex("#878d9b"), accent = hex("#8fa4c8"),
                  amanatsu = hex("#e8c547"), kaabo = hex("#62c37a"), kansai = hex("#e2574f"),
                  water = hex("#a9d3e6"), blood = hex("#9a0f12"), thought = hex("#ece6d8") })

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let color = (key, fallback) -> Map.get(key, root) |> Option.flatMap(JsonCodec.expectString)
            |> Option.flatMap(Color.hex) |> Option.getWithDefault(fallback);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  rail = color("rail", d#rail), sidebar = color("sidebar", d#sidebar), chat = color("chat", d#chat),
                  ink = color("ink", d#ink), inkDim = color("inkDim", d#inkDim), accent = color("accent", d#accent),
                  amanatsu = color("amanatsu", d#amanatsu), kaabo = color("kaabo", d#kaabo), kansai = color("kansai", d#kansai),
                  water = color("water", d#water), blood = color("blood", d#blood), thought = color("thought", d#thought) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)

    /// 3 人の色（名前の字とアバターの縁）。
    pub def castColor(cast: Talk.Cast, theme: Doc): Color =
        let r = rec(theme);
        match cast {
            case Talk.Cast.Amanatsu => r#amanatsu
            case Talk.Cast.Kaabo    => r#kaabo
            case Talk.Cast.Kansai   => r#kansai
        }
}
