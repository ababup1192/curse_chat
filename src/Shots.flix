// Shots — ギャラリーの場面（make render-all の 1 枚）の World。描き出し（SceneRender）と実機
// （Game の App.withShots。START=shot:<場面>）が同じ関数で組むので、実機で開いた場面はギャラリーの絵と同じ World から始まる。
// none-<場面> は背景なし（Art.Backdrop.Bare: 地の文の層の奥に部屋の絵を置かず、チャットの UI そのものを沈める）で撮る
// （地の文の出る場面だけ）。
// 場面は「進めて作る」: 「ノードの、.yarn のこの行の台詞」まで進める（行の名前と行番号の表は anchors）。
// WhyNot: 台詞の字で行を引かない — Shots はブラウザ版の wasm に入るので、字を書くと隠した台本（web.embed）の台詞が平文で残る。
//   台本を直して行がずれたら anchors の行番号を直す（TestDocs が、どの行も台詞を指していることを確かめる）。
// WhyNot: 描き出しの物（HeadlessRender・HeadlessFont・java.io）を引かない — Game.app から engine_tools へつながり、ブラウザ版で組めなくなる。
mod Shots {
    use fge::{App, Clock, Emit, Resources, UiTypewriter, YarnRunner, YarnStorage}

    /// 描き出しの始まりの World（セーブデータは空・時刻は clockBase）。
    def initialOf(res: Res.Res): World.World = World.initial(Saves.fresh(res#kind), clockBase())

    /// 描き出しの「起動した時刻」（2026/08/14 19:32。セーブの日時を毎回同じ字にする）。
    pub def clockBase(): Int64 = 1786735920i64

    /// 場面（背景なしの頭を付ける前の名前）。
    pub def scenes(): List[String] =
        "title" :: "chat" :: "chat-kaabo" :: "join" :: "thought" :: "glitch" :: "chill" :: "tv" :: "tv-water" :: "dark" :: "scare" ::
        "log" :: "save" :: "settings" :: "credits" :: Nil

    /// 背景なしでも撮る場面（地の文の層が出る所）。
    pub def bareScenes(): List[String] = "chat" :: "thought" :: Nil

    /// 背景なしの頭。
    def barePrefix(): String = "none-"

    /// 描き出せる場面の名前（make render の SHOT とギャラリーの並びの正）。場面を並べ、背景なしの物を後ろに足す。
    pub def names(): List[String] =
        List.append(scenes(), bareScenes() |> List.map(scene -> "${barePrefix()}${scene}"))

    /// 名前 → (地の文の奥, 場面)。none- の頭があれば背景なし、無ければ部屋の絵。
    pub def splitName(name: String): (Art.Backdrop, String) =
        if (String.startsWith(prefix = barePrefix(), name)) (Art.Backdrop.Bare, String.dropLeft(String.length(barePrefix()), name))
        else (Art.Backdrop.Room, name)

    /// 名前 → 描く元（地の文の奥を当てた物）と、描き出しと同じ初めの World（initialOf）から組んだ場面の World。知らない場面なら None。
    pub def shotOf(name: String, res: Res.Res): Option[(Res.Res, World.World)] =
        let (backdrop, scene) = splitName(name);
        let withArt = Res.withBackdrop(backdrop, res);
        sceneOf(withArt, scene, initialOf(withArt)) |> Option.map(w -> (withArt, w))

    /// App.withShots へ渡す始まりの一覧（地の文の奥を描く元へ当てるので、Resources.shotsOf ではなく組ごと作る）。
    pub def starts(): List[App.Start[Resources.With[Res.Res, World.World]]] =
        names() |> List.map(name ->
            { name = name, doc = "ギャラリーの場面（gallery/${name}.png）", args = Map.empty(),
              build = (h, _) -> shotOf(name, h#resources) |> Option.map(match (res, w) -> Resources.of(res, w))
                                    |> Option.toOk("場面 '${name}' を組めない") })

    /// 場面の World を組む時に進める先の行: 名前 → (ノード, .yarn の行番号)。
    pub def anchors(): Map[String, (String, Int32)] =
        Map#{ "chatTyping" => ("Chat", 54), "kaaboTyping" => ("Chat", 56), "firstPost" => ("Chat", 34), "thought" => ("Chat", 63),
              "glitch" => ("Chat", 107), "chill" => ("Chat", 134), "newsFirst" => ("News", 149), "impostor" => ("Chat", 84),
              "denial" => ("Chat", 120), "gamePick" => ("Chat", 41), "newsLast" => ("News", 153), "chatTop" => ("Chat", 40),
              "beginning" => ("Chat", 69), "newsChat" => ("News", 151) }

    /// 縦の画面だけで描く場面（menu = 上の帯の ≡ を開いた所・ask = 確認のウィンドウ）。
    // WhyNot: names に入れない — names は横の描き出しと実機の START=shot: の口でもあり、横の絵の一覧を変えない。
    pub def portraitOnly(): List[String] = "menu" :: "ask" :: Nil

    /// 場面の名前 → その場面の World。時計は秒で据える（水滴・砂嵐・入力中の点は実時間から導くので、据えれば毎回同じ絵）。
    def sceneOf(res: Res.Res, name: String, w0: World.World): Option[World.World] =
        match name {
            // タイトル画面: 音の注意と、左のメニュー。
            case "title"      => Some(at(3.0, w0))
            // チャット: 甘夏が打っている途中（入力中の点・まだ履歴に入っていない）。
            case "chat"       => Some(at(4.0, typing(0.6, lineAt(res, "chatTyping", w0))))
            // かーぼー（自分）が入力欄に一字ずつ打っている途中。
            case "chat-kaabo" => Some(at(4.0, typing(0.5, lineAt(res, "kaaboTyping", w0))))
            // 3 人が入室した直後（入室の行が 3 つ・甘夏が最初の発言を打ち始めた所）。
            case "join"       => Some(at(2.0, typing(0.3, lineAt(res, "firstPost", w0))))
            // 地の文: チャットを沈め、続いた 4 行を中央に明朝で出した所。
            case "thought"    => Some(at(4.0, lineAt(res, "thought", w0)))
            // 崩れた発言: 甘夏の「こっちきたた……」が震えている（冷えは 0.3）。
            case "glitch"     => Some(at(4.0, lineAt(res, "glitch", w0)))
            // 冷え: かーぼーの最後の発言の手前（2 人は退出・冷えは 0.6・水の音）。
            case "chill"      => Some(at(4.0, lineAt(res, "chill", w0)))
            // テレビ: キャスターの字幕が出ている途中。
            case "tv"         => Some(at(4.0, typing(0.7, lineAt(res, "newsFirst", w0))))
            // テレビ（倒れた後）: キャスターが画面の外へ落ち、画面の内側に水滴が付いている。
            case "tv-water"   => Some(laterBy(3.0, afterNews(res, w0)))
            // 真っ暗: 血文字の前の静寂。
            case "dark"       => Some(laterBy(1.5, waited(res, afterNews(res, w0))))
            // 血文字が一瞬だけ出ている所。
            case "scare"      => Some(laterBy(0.25, waited(res, waited(res, afterNews(res, w0)))))
            // バックログ: 関西が入れ替わった所まで読んでから開き、甘夏の発言に触れている所。
            case "log"        =>
                let w = quiet(() -> WorldLog.openLog(lineAt(res, "impostor", w0)));
                Some(at(4.0, { pointer = { x = 400.0, y = 360.0 } | w }))
            // セーブ: 読んでいる途中で開いたセーブ画面（1 ページ目に 3 つ。いちばん新しい物に NEW）。
            case "save"       => Some(at(4.0, quiet(() -> WorldSaves.openSave(withSlots(res, lineAt(res, "denial", w0))))))
            // 設定: チャットの途中で開いた設定（見本の文が流れている所）。
            case "settings"   => Some(at(1.2, quiet(() -> WorldSettings.openSettings(lineAt(res, "gamePick", w0)))))
            // ≡ のメニュー: 冷えの手前でオートを点け、≡ を開いた所（縦の画面だけ）。
            case "menu"       => Some(at(4.0, World.mapRead(r -> { playback = World.Playback.Auto | r }, { panel = World.Panel.Menu(0) | lineAt(res, "denial", w0) })))
            // 確認のウィンドウ: チャットの途中で「タイトルに戻りますか？」（縦の画面だけ）。
            case "ask"        => Some(at(4.0, quiet(() -> World.askFor(World.Ask.ToTitle, lineAt(res, "gamePick", w0)))))
            // クレジット: 流れ始めて 9 秒（音の出典が見えている所）。
            case "credits"    => Some(at(9.0, World.toCredits(res, w0)))
            case _            => None
        }

    /// 物語の時計と実時間の今を、どちらも seconds 秒に据える。
    def at(seconds: Float64, w: World.World): World.World =
        { storyClock = Clock.startAt(seconds), realNow = Clock.after(seconds, Clock.zero()) | w }

    /// 物語の時計と実時間を、今から seconds 秒だけ先へ据える。
    def laterBy(seconds: Float64, w: World.World): World.World =
        let now = Clock.secondsOf(World.now(w)) + seconds;
        { storyClock = Clock.startAt(now), realNow = Clock.after(now, Clock.zero()) | w }

    def quiet(f: Unit -> World.World \ Emit[World.Event]): World.World = fst(Emit.collect(f))

    /// anchors の名前の行を出し終えた所（その行までのコマンドは反映して、演出は終わりの形）。知らない名前なら Chat の頭。
    def lineAt(res: Res.Res, anchor: String, w: World.World): World.World =
        let (node, line) = Map.getWithDefault(anchor, ("Chat", 0), anchors());
        WorldRead.revealLine(quiet(() -> WorldRead.openAt(res, YarnStorage.empty(), node, line, w)))

    /// 今の行を、字の数の fraction だけ打った途中にする（まだ出し終えていない）。
    def typing(fraction: Float64, w: World.World): World.World =
        World.mapRead(r -> match r#page#current {
            case Some(line) =>
                let reveal = { shown = Int32.toFloat64(String.length(line#text)) * fraction | UiTypewriter.start(line#text) };
                { page = { reveal = reveal | r#page }, doneAt = None | r }
            case None => r
        }, w)

    /// ニュースの最後の字幕から送り、キャスターが倒れて水滴が付き始めた所（<<wait>> の明けまで流す）。
    def afterNews(res: Res.Res, w0: World.World): World.World =
        let last = lineAt(res, "newsLast", w0);
        waited(res, quiet(() -> WorldRead.advance(res, last)))

    /// <<wait>> を明かす（描き出しは時計を進めないので、明ける時刻で 1 歩だけ流す）。
    def waited(res: Res.Res, w: World.World): World.World =
        match World.readOf(w) |> Option.flatMap(r -> YarnRunner.waitUntilOf(r#talk)) {
            case Some(until) => quiet(() -> WorldRead.step(res, 0.0, { storyClock = Clock.startAt(Clock.secondsOf(until)) | w }))
            case None        => w
        }

    /// 1 ページ目に 3 つ（チャットの頭・地の文・テレビ）セーブした World。日時は少しずつずらす。
    def withSlots(res: Res.Res, w: World.World): World.World =
        let saveAt = (minutes: Int64, i: Int32, scene: World.World, target: World.World) ->
            { saves = quiet(() -> WorldSaves.writeSlot(res, Saves.Tab.Numbered(1), i, { saves = target#saves, clockBase = clockBase() + minutes * 60i64 | scene }))#saves | target };
        w |> saveAt(-2900i64, 0, lineAt(res, "chatTop", w))
          |> saveAt(-2860i64, 1, lineAt(res, "beginning", w))
          |> saveAt(-12i64, 2, lineAt(res, "newsChat", w))
          |> (cur -> { toast = None | cur })
}
