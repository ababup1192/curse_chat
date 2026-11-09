// テストの共通部品: 実機と同じ App（Game.app）と Doc・シナリオで組んだ始まりの World と、系を直に呼ぶ 1 歩。
// シナリオは本物（assets/talk/dialogue.json）。期待値は台本と Doc から導き、行の文字を写さない。
//
// 発言は打ち終えて間が過ぎると勝手に流れるので、「出し終えるまで」進める口（settle）は小さな歩幅で時計を進め、
// 行を出し終えた所（間はまだ過ぎていない）で止まる。<<wait>> の間は時計を進めて明かす。
mod TestKit {

    use fge::{App, Emit, Resources, YarnRunner, YarnStorage}

    /// assets の Doc とシナリオをそのまま読んだ描く元。
    pub def res(): Res.Res \ Fs.FileRead = Controls.loadRes()

    /// タイトルの World（セーブデータは空・ファイルは書かない・時刻は 0）。
    pub def w0(res: Res.Res): World.World = World.initial(Saves.fresh(res#kind), 0i64)

    pub def app(res: Res.Res, w: World.World): App.App[Resources.With[Res.Res, World.World], {}] = Game.app(res, w#saves, w#clockBase)

    /// 物語の時計だけを dt 秒ぶん進める（実機と同じ App.addClock の進み方）。
    pub def tickClocks(res: Res.Res, dt: Float64, w: World.World): World.World =
        App.tickClocks(app(res, w), dt, Resources.of(res, w))#world

    /// 系を直に呼ぶ 1 歩: 実機と同じく、先に物語の時計を dt 秒ぶん進めてから WorldRead.step。
    pub def stepBy(res: Res.Res, dt: Float64, w: World.World): World.World =
        quiet(() -> WorldRead.step(res, dt, tickClocks(res, dt, w)))

    /// 規則が出す返事の出来事（Emit）を捨てて World だけを見る。
    pub def quiet(f: Unit -> World.World \ Emit[World.Event]): World.World = fst(Emit.collect(f))

    pub def advance(res: Res.Res, w: World.World): World.World = quiet(() -> WorldRead.advance(res, w))

    /// 1 歩の秒（打つ速さの見本より十分細かい）。
    def tick(): Float64 = 0.05

    /// 今の行を出し終えて止まっているか（行を出していて、出し終えた時刻が付き、<<wait>> の途中でない）。読んでいなければ止まっている。
    pub def isAtRest(w: World.World): Bool = match World.readOf(w) {
        case None    => true
        case Some(r) => match YarnRunner.shownOf(r#talk) {
            case YarnRunner.Shown.Line(_) => Page.isDone(r#page) and Option.nonEmpty(r#doneAt) and Option.isEmpty(r#hold)
            case YarnRunner.Shown.Closed  => true
            case _                        => false
        }
    }

    /// 出し終えるまで進め、その間に出た出来事も古い順に返す（fuel で必ず止まる）。
    pub def settleHearing(res: Res.Res, w: World.World): (World.World, List[World.Event]) =
        def go(fuel: Int32, cur: World.World, acc: List[World.Event]): (World.World, List[World.Event]) =
            if (fuel <= 0 or isAtRest(cur)) (cur, acc)
            else {
                let (next, heard) = Emit.collect(() -> WorldRead.step(res, tick(), tickClocks(res, tick(), cur)));
                go(fuel - 1, next, List.append(acc, heard))
            };
        go(6000, w, Nil)

    /// 出し終えるまで進める。
    pub def settle(res: Res.Res, w: World.World): World.World = fst(settleHearing(res, w))

    /// はじめから読み、最初の行を出し終えた所（頭の <<wait>> と入室も済んでいる）。
    pub def begun(res: Res.Res): World.World =
        settle(res, quiet(() -> WorldRead.newGame(res, w0(res))))

    /// 押して次の行を出し終えた所。
    pub def nextLine(res: Res.Res, w: World.World): World.World = settle(res, advance(res, w))

    /// 押しては出し終えるまで進め、until が真になった所で止まる（fuel で必ず止まる）。途中で規則が出した出来事も古い順に返す。
    pub def readHearing(res: Res.Res, until: World.World -> Bool, w: World.World): (World.World, List[World.Event]) =
        def go(fuel: Int32, cur: World.World, acc: List[World.Event]): (World.World, List[World.Event]) =
            if (fuel <= 0 or until(cur) or not World.isReading(cur)) (cur, acc)
            else {
                let (pressed, heard) = Emit.collect(() -> WorldRead.advance(res, cur));
                let (settled, more) = settleHearing(res, pressed);
                go(fuel - 1, settled, List.append(acc, List.append(heard, more)))
            };
        go(600, w, Nil)

    /// readHearing の World だけ。
    pub def readUntil(res: Res.Res, until: World.World -> Bool, w: World.World): World.World = fst(readHearing(res, until, w))

    /// 今の行の字が text になるまで読む。
    pub def readTo(res: Res.Res, text: String, w: World.World): World.World =
        readUntil(res, cur -> textOf(cur) == text, w)

    /// node の頭から開いて、出し終えるまで進めた所（そのノードの最初の行）。
    pub def openNode(res: Res.Res, node: String): World.World =
        settle(res, quiet(() -> WorldRead.openAt(res, YarnStorage.empty(), node, 0, w0(res))))

    /// 今の行の字（無ければ空）。
    pub def textOf(w: World.World): String = World.pageOf(w)#current |> Option.map(l -> l#text) |> Option.getWithDefault("")

    /// 今のシナリオの位置（ノードと行）。
    pub def placeOf(w: World.World): (String, String) = (World.talkNodeOf(w), World.talkLineOf(w))

    /// チャットの履歴の字（古い順）。
    pub def feedTexts(w: World.World): List[String] = Page.shownFeed(World.pageOf(w)) |> List.map(l -> l#text)

    pub def isWaiting(w: World.World): Bool = match World.readOf(w) |> Option.map(r -> YarnRunner.shownOf(r#talk)) {
        case Some(YarnRunner.Shown.Waiting) => true
        case _                              => false
    }

    /// 今の行の種類が地の文か。
    pub def isThought(w: World.World): Bool = World.pageOf(w)#current |> Option.exists(Page.isThought)

    /// 送り方を替えた World。
    pub def playing(mode: World.Playback, w: World.World): World.World = World.mapRead(r -> { playback = mode | r }, w)
}
