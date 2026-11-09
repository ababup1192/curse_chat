// PortraitDoc — novel.portrait.json（縦の画面 = 縦に持ったスマホで縦の design で起動した時だけ使う字と押せる物の大きさ）の宣言ドキュメント層。
// 置き場所（どこに並べるか）は Layout のコードが決め、ここは大きさだけ。横の画面（PC・横持ち・デスクトップ版）は読まない。
// fail-open — 読めない・壊れているときは defaults() へ落とし、ゲームは必ず起動する。
mod PortraitDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// どれも design px（幅 540 の中の px）。*TextSize / *Size = 字の大きさ、*Height = 押せる高さ。
    /// header* = 上のチャンネル名の帯（高さ・チャンネル名の字・人数の字）、menuButtonSize = 帯の右の ≡ の押せる大きさ、
    /// menuItem* = ≡ から開くメニューの 1 項目、chat* = 発言の本文と名前の字、avatarSize = 発言のアバターの直径、
    /// typingSize = 「入力中…」の字、inputHeight = 下の入力欄の高さ、homeBarGap = 入力欄の下に空けるホームバーの余白、
    /// thoughtSize = 地の文の字、thoughtDim = 地の文の層でチャットを沈める濃さ（0〜1）、captionSize = テレビの字幕の字、titleItem* = タイトル画面のメニュー、
    /// noteSize = 画面の下の案内・タイトルの音の注意の字、back* = 画面の右上の「戻る」、tab* = セーブ・ロードのタブ、
    /// slotTextSize / slotPlaceSize = セーブの枠の番号と日時と発言の頭の字・場所の字、setting* = 設定の行、logTextSize = バックログの本文、
    /// askTextSize = 確認のウィンドウの問いの字、askButton* = はい・いいえ、credits* = クレジットの見出し・本文・出典の字。
    pub type alias Rec = {
        version = Int32,
        headerHeight = Float64,
        headerTitleSize = Float64,
        headerSubSize = Float64,
        menuButtonSize = Float64,
        menuItemTextSize = Float64,
        menuItemHeight = Float64,
        chatBodySize = Float64,
        chatNameSize = Float64,
        avatarSize = Float64,
        typingSize = Float64,
        inputHeight = Float64,
        homeBarGap = Float64,
        thoughtSize = Float64,
        thoughtDim = Float64,
        captionSize = Float64,
        titleItemTextSize = Float64,
        titleItemHeight = Float64,
        noteSize = Float64,
        backTextSize = Float64,
        backHeight = Float64,
        tabTextSize = Float64,
        tabHeight = Float64,
        slotTextSize = Float64,
        slotPlaceSize = Float64,
        settingTextSize = Float64,
        settingRowHeight = Float64,
        logTextSize = Float64,
        askTextSize = Float64,
        askButtonTextSize = Float64,
        askButtonHeight = Float64,
        creditsHeadingSize = Float64,
        creditsBodySize = Float64,
        creditsSmallSize = Float64
    }

    /// 型検査が record を展開しないため、Res が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/novel.portrait.json"

    /// コード側の既定値（assets/novel.portrait.json と同じ値から出発する）。
    pub def defaults(): Doc =
        Doc.Doc({ version = 1, headerHeight = 104.0, headerTitleSize = 30.0, headerSubSize = 18.0, menuButtonSize = 76.0,
                  menuItemTextSize = 25.0, menuItemHeight = 72.0, chatBodySize = 27.0, chatNameSize = 24.0, avatarSize = 64.0,
                  typingSize = 20.0, inputHeight = 80.0, homeBarGap = 44.0, thoughtSize = 31.0, thoughtDim = 0.94, captionSize = 27.0,
                  titleItemTextSize = 30.0, titleItemHeight = 72.0, noteSize = 19.0, backTextSize = 22.0, backHeight = 66.0,
                  tabTextSize = 20.0, tabHeight = 66.0, slotTextSize = 19.0, slotPlaceSize = 24.0,
                  settingTextSize = 20.0, settingRowHeight = 68.0, logTextSize = 24.0, askTextSize = 25.0,
                  askButtonTextSize = 24.0, askButtonHeight = 72.0, creditsHeadingSize = 34.0, creditsBodySize = 23.0, creditsSmallSize = 17.0 })

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let num = (key, fallback) -> JsonCodec.floatOr(key, fallback, root);
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  headerHeight = num("headerHeight", d#headerHeight), headerTitleSize = num("headerTitleSize", d#headerTitleSize),
                  headerSubSize = num("headerSubSize", d#headerSubSize), menuButtonSize = num("menuButtonSize", d#menuButtonSize),
                  menuItemTextSize = num("menuItemTextSize", d#menuItemTextSize), menuItemHeight = num("menuItemHeight", d#menuItemHeight),
                  chatBodySize = num("chatBodySize", d#chatBodySize), chatNameSize = num("chatNameSize", d#chatNameSize),
                  avatarSize = num("avatarSize", d#avatarSize), typingSize = num("typingSize", d#typingSize),
                  inputHeight = num("inputHeight", d#inputHeight), homeBarGap = num("homeBarGap", d#homeBarGap),
                  thoughtSize = num("thoughtSize", d#thoughtSize), thoughtDim = num("thoughtDim", d#thoughtDim), captionSize = num("captionSize", d#captionSize),
                  titleItemTextSize = num("titleItemTextSize", d#titleItemTextSize), titleItemHeight = num("titleItemHeight", d#titleItemHeight),
                  noteSize = num("noteSize", d#noteSize), backTextSize = num("backTextSize", d#backTextSize), backHeight = num("backHeight", d#backHeight),
                  tabTextSize = num("tabTextSize", d#tabTextSize), tabHeight = num("tabHeight", d#tabHeight),
                  slotTextSize = num("slotTextSize", d#slotTextSize), slotPlaceSize = num("slotPlaceSize", d#slotPlaceSize),
                  settingTextSize = num("settingTextSize", d#settingTextSize), settingRowHeight = num("settingRowHeight", d#settingRowHeight),
                  logTextSize = num("logTextSize", d#logTextSize), askTextSize = num("askTextSize", d#askTextSize),
                  askButtonTextSize = num("askButtonTextSize", d#askButtonTextSize), askButtonHeight = num("askButtonHeight", d#askButtonHeight),
                  creditsHeadingSize = num("creditsHeadingSize", d#creditsHeadingSize), creditsBodySize = num("creditsBodySize", d#creditsBodySize),
                  creditsSmallSize = num("creditsSmallSize", d#creditsSmallSize) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
