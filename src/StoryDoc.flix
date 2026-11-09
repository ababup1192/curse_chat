// StoryDoc — novel.story.json（画面に出す言葉: タイトル・チャットアプリの字・メニュー・設定・セーブ・確認のウィンドウの文言と、話し手の呼び名）の宣言ドキュメント層。
// 発言・地の文・字幕はシナリオ assets/talk/curse_chat.yarn（Talk）にあり、ここはシナリオの外で画面に出す言葉だけを持つ。
// 言葉は Label の enum を鍵に引く（鍵の綴りと既定の言葉の正は entryOf。Doc に無い鍵は既定の言葉で出す = fail-open）。
mod StoryDoc {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// シナリオの外で画面に出す言葉の鍵。
    pub enum Label with Eq, Order, ToString {
        // タイトルのメニュー
        case NewGame
        case Continue
        case LoadGame
        case Settings
        case Credits
        case Quit
        // チャットの見出しのクイックメニュー
        case Rollback
        case Log
        case Auto
        case Skip
        case QuickSave
        case QuickLoad
        case Save
        case Load
        case Config
        case ToTitle
        // チャットアプリの字
        case ServerName
        case TextChannels
        case Channel
        case ChannelNews
        case ChannelTalk
        case Members
        case Online
        case Offline
        case Today
        case Joined
        case Left
        case Typing
        case InputHint
        case NewsTitle
        case Live
        // セーブの枠の場所
        case PlaceChat
        case PlaceNews
        case PlaceDark
        // 画面の見出しと「戻る」
        case SaveTitle
        case LoadTitle
        case LogTitle
        case SettingsTitle
        case Back
        // セーブ・ロードの画面
        case TabAuto
        case TabQuick
        case EmptySlot
        case NewBadge
        case SlotsHint
        // バックログ
        case LogHint
        // 設定の画面
        case GroupText
        case GroupSound
        case TextSpeed
        case AutoWait
        case SkipScope
        case SkipReadOnly
        case SkipEverything
        case Display
        case WindowMode
        case FullscreenMode
        case MasterVolume
        case AmbienceVolume
        case SeVolume
        case Reset
        case Preview
        // 確認のウィンドウ
        case Yes
        case No
        case AskOverwrite
        case AskDelete
        case AskLoad
        case AskJump
        case AskToTitle
        case AskQuit
        case AskReset
        case LostNote
        // 知らせ
        case Saved
        case QuickSaved
        case Loaded
        case Deleted
        case ResetDone
        case NoSave
        case NoQuickSave
        case NoRollback
        // 縦の画面（指で触る）
        case Menu
        case TapHint
        case LogTapHint
    }

    pub def labels(): List[Label] =
        Label.NewGame :: Label.Continue :: Label.LoadGame :: Label.Settings :: Label.Credits :: Label.Quit :: Label.Rollback :: Label.Log :: Label.Auto :: Label.Skip :: Label.QuickSave :: Label.QuickLoad :: Label.Save :: Label.Load :: Label.Config :: Label.ToTitle :: Label.ServerName :: Label.TextChannels :: Label.Channel :: Label.ChannelNews :: Label.ChannelTalk :: Label.Members :: Label.Online :: Label.Offline :: Label.Today :: Label.Joined :: Label.Left :: Label.Typing :: Label.InputHint :: Label.NewsTitle :: Label.Live :: Label.PlaceChat :: Label.PlaceNews :: Label.PlaceDark :: Label.SaveTitle :: Label.LoadTitle :: Label.LogTitle :: Label.SettingsTitle :: Label.Back :: Label.TabAuto :: Label.TabQuick :: Label.EmptySlot :: Label.NewBadge :: Label.SlotsHint :: Label.LogHint :: Label.GroupText :: Label.GroupSound :: Label.TextSpeed :: Label.AutoWait :: Label.SkipScope :: Label.SkipReadOnly :: Label.SkipEverything :: Label.Display :: Label.WindowMode :: Label.FullscreenMode :: Label.MasterVolume :: Label.AmbienceVolume :: Label.SeVolume :: Label.Reset :: Label.Preview :: Label.Yes :: Label.No :: Label.AskOverwrite :: Label.AskDelete :: Label.AskLoad :: Label.AskJump :: Label.AskToTitle :: Label.AskQuit :: Label.AskReset :: Label.LostNote :: Label.Saved :: Label.QuickSaved :: Label.Loaded :: Label.Deleted :: Label.ResetDone :: Label.NoSave :: Label.NoQuickSave :: Label.NoRollback :: Label.Menu :: Label.TapHint :: Label.LogTapHint :: Nil

    /// novel.story.json の labels の鍵。
    pub def labelKey(label: Label): String = fst(entryOf(label))

    /// 鍵の綴りと、Doc に鍵が無い時に出す言葉（assets/novel.story.json と同じ値から出発する）。
    // WhyNot: preview の既定に Doc と同じ文（台本の地の文の 1 行）を書かない — このファイルはブラウザ版の wasm に入り、隠した台本の字が平文で残る。
    def entryOf(label: Label): (String, String) = match label {
        case Label.NewGame        => ("newGame", "はじめから")
        case Label.Continue       => ("continue", "つづきから")
        case Label.LoadGame       => ("loadGame", "ロード")
        case Label.Settings       => ("settings", "設定")
        case Label.Credits        => ("credits", "クレジット")
        case Label.Quit           => ("quit", "終了")
        case Label.Rollback       => ("rollback", "戻る")
        case Label.Log            => ("log", "ログ")
        case Label.Auto           => ("auto", "オート")
        case Label.Skip           => ("skip", "スキップ")
        case Label.QuickSave      => ("quickSave", "Qセーブ")
        case Label.QuickLoad      => ("quickLoad", "Qロード")
        case Label.Save           => ("save", "セーブ")
        case Label.Load           => ("load", "ロード")
        case Label.Config         => ("config", "設定")
        case Label.ToTitle        => ("toTitle", "タイトル")
        case Label.ServerName     => ("serverName", "大学ゲーム部")
        case Label.TextChannels   => ("textChannels", "テキストチャンネル")
        case Label.Channel        => ("channel", "ゲーム部屋")
        case Label.ChannelNews    => ("channelNews", "お知らせ")
        case Label.ChannelTalk    => ("channelTalk", "雑談")
        case Label.Members        => ("members", "メンバー")
        case Label.Online         => ("online", "オンライン")
        case Label.Offline        => ("offline", "オフライン")
        case Label.Today          => ("today", "今日")
        case Label.Joined         => ("joined", "が入室しました")
        case Label.Left           => ("left", "が退出しました")
        case Label.Typing         => ("typing", "が入力中")
        case Label.InputHint      => ("inputHint", "#ゲーム部屋 へメッセージを送信")
        case Label.NewsTitle      => ("newsTitle", "ニュース")
        case Label.Live           => ("live", "LIVE")
        case Label.PlaceChat      => ("placeChat", "#ゲーム部屋")
        case Label.PlaceNews      => ("placeNews", "ニュース")
        case Label.PlaceDark      => ("placeDark", "……")
        case Label.SaveTitle      => ("saveTitle", "セーブ")
        case Label.LoadTitle      => ("loadTitle", "ロード")
        case Label.LogTitle       => ("logTitle", "バックログ")
        case Label.SettingsTitle  => ("settingsTitle", "設定")
        case Label.Back           => ("back", "戻る")
        case Label.TabAuto        => ("tabAuto", "オート")
        case Label.TabQuick       => ("tabQuick", "クイック")
        case Label.EmptySlot      => ("emptySlot", "NO DATA")
        case Label.NewBadge       => ("newBadge", "NEW")
        case Label.SlotsHint      => ("slotsHint", "Q / E でページを替える ・ Delete で削除")
        case Label.LogHint        => ("logHint", "行をクリックすると、そこまで戻れます ・ ホイールで遡る")
        case Label.GroupText      => ("groupText", "文章")
        case Label.GroupSound     => ("groupSound", "音と画面")
        case Label.TextSpeed      => ("textSpeed", "文字の速さ")
        case Label.AutoWait       => ("autoWait", "オートの待ち時間")
        case Label.SkipScope      => ("skipScope", "スキップ")
        case Label.SkipReadOnly   => ("skipReadOnly", "既読のみ")
        case Label.SkipEverything => ("skipEverything", "未読も")
        case Label.Display        => ("display", "画面")
        case Label.WindowMode     => ("windowMode", "ウィンドウ")
        case Label.FullscreenMode => ("fullscreenMode", "フルスクリーン")
        case Label.MasterVolume   => ("masterVolume", "全体の音量")
        case Label.AmbienceVolume => ("ambienceVolume", "環境音")
        case Label.SeVolume       => ("seVolume", "効果音")
        case Label.Reset          => ("reset", "初期設定に戻す")
        case Label.Preview        => ("preview", "文字の速さの見本です。")
        case Label.Yes            => ("yes", "はい")
        case Label.No             => ("no", "いいえ")
        case Label.AskOverwrite   => ("askOverwrite", "このデータに上書きしますか？")
        case Label.AskDelete      => ("askDelete", "このデータを削除しますか？")
        case Label.AskLoad        => ("askLoad", "このデータをロードしますか？")
        case Label.AskJump        => ("askJump", "ここまで戻りますか？")
        case Label.AskToTitle     => ("askToTitle", "タイトルに戻りますか？")
        case Label.AskQuit        => ("askQuit", "ゲームを終了しますか？")
        case Label.AskReset       => ("askReset", "設定を初期値に戻しますか？")
        case Label.LostNote       => ("lostNote", "セーブしていない進行は失われます")
        case Label.Saved          => ("saved", "セーブしました")
        case Label.QuickSaved     => ("quickSaved", "クイックセーブしました")
        case Label.Loaded         => ("loaded", "ロードしました")
        case Label.Deleted        => ("deleted", "削除しました")
        case Label.ResetDone      => ("resetDone", "初期設定に戻しました")
        case Label.NoSave         => ("noSave", "セーブデータがありません")
        case Label.NoQuickSave    => ("noQuickSave", "クイックセーブがありません")
        case Label.NoRollback     => ("noRollback", "これ以上は戻れません")
        case Label.Menu           => ("menu", "メニュー")
        case Label.TapHint        => ("tapHint", "タップで選ぶ")
        case Label.LogTapHint     => ("logTapHint", "行をタップすると、そこまで戻れます")
    }

    /// title / warning / hint = タイトル画面の題・音の注意・操作の案内、
    /// titleAmbience = タイトル画面の環境音（amb_<名前>。空なら鳴らさない）、names = 話し手の id → 呼び名、labels = Label の鍵 → 言葉。
    pub type alias Rec = {
        version = Int32,
        title = String,
        warning = String,
        hint = String,
        titleAmbience = String,
        names = Map[String, String],
        labels = Map[String, String]
    }

    /// 型検査が record を展開しないため、World が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/novel.story.json"

    pub def defaults(): Doc =
        Doc.Doc({ version = 2, title = "呪いのチャット",
                  warning = "音量注意・ヘッドホン推奨", hint = "クリックか Enter で選ぶ", titleAmbience = "room",
                  names = Map.empty(), labels = Map.empty() })

    /// 鍵の言葉（Doc に無ければ既定の言葉）。
    pub def labelOf(label: Label, doc: Doc): String =
        Map.get(labelKey(label), rec(doc)#labels) |> Option.getWithDefault(snd(entryOf(label)))

    /// 話し手の id の呼び名（地の文の空の id は空・Doc に無い id はそのまま）。
    pub def nameOf(id: String, doc: Doc): String =
        Map.getWithDefault(id, id, rec(doc)#names)

    /// チャットの 3 人の呼び名。
    pub def castName(cast: Talk.Cast, doc: Doc): String = nameOf(Talk.castId(cast), doc)

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        let strings = key -> Map.get(key, root)
            |> Option.flatMap(JsonCodec.decodeStringMap(JsonCodec.expectString))
            |> Option.getWithDefault(Map.empty());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  title = JsonCodec.stringOr("title", d#title, root),
                  warning = JsonCodec.stringOr("warning", d#warning, root),
                  hint = JsonCodec.stringOr("hint", d#hint, root),
                  titleAmbience = JsonCodec.stringOr("titleAmbience", d#titleAmbience, root),
                  names = strings("names"),
                  labels = strings("labels") })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)
}
