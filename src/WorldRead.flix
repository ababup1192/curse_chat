// WorldRead — 読み進める規則（純粋）: はじめから読む・発言を打って流す・地の文を送る・オートとスキップ・戻れる所へ戻す。
// 発言・地の文・字幕はシナリオ assets/talk/curse_chat.yarn（YarnRunner が辿る）、舞台の変え方は Stage、チャットの履歴は Page。
// ここの関数は、場面が Reading の時だけ読んでいる値 Read を取り出して動く（ほかの場面では何もしない）。
//
// 1 発言 = シナリオの 1 行 = 実行器の Advance 1 回。発言が来たら reveal を「打っている時間」として進め（速さは話し手ごと）、
// 打ち終えたら履歴に入れてポコッ（Event.Posted）を鳴らし、間（PaceDoc.gapSeconds）が過ぎたら自分で次へ流す。
// 地の文は人が押して進める（オートの時はオートの待ち）。字幕は発言と同じく間で流れる（チャットには入らない）。
// 押すと: 打っている途中ならすぐ全部出し（すぐ送信）、出し終えた後なら間を飛ばして次へ。<<wait>> は押しても飛ばない。
//
// 戻れる所（Saves.Mark）は 3 か所が同じ物を持つ: セーブデータ・バックログの行・「戻る」。戻し方は restore 1 つで、
// ブックマークを当て直し（通ったコマンドは音を出さずに履歴と舞台へ反映し直す）、前のノードから持ち越す舞台は Mark の値で戻す。
// 当て直した最後の行は出し終えた形で、出し終えた時刻を今に据える（ポコッは鳴らさず、間はそこから数える）。
//
// ブラウザ版で後回しにした環境音が使う時にまだ届いていなければ、暗転して待つ（下の「素材の待ち」の節）。
// 絵は待たない（画像が届いていない部品は、その部品だけ図形で描く = Art.imageOf）。
mod WorldRead {
    use fge::{Clock, Emit, Log, Yarn, YarnRunner, YarnStorage}

    /// シナリオの出来事を反映する時に、音とオートセーブを出すか。
    /// Live = 人が読み進めている時、Silent = ロード・戻る・プレビューの当て直し（音もオートセーブも出さず、行は出し終えた形）。
    enum Replay with Eq {
        case Live
        case Silent
    }

    /// 読んでいる間だけ f(読んでいる値) を通す（ほかの場面ではそのまま）。
    def whileReading(f: World.Read -> World.World \ ef, w: World.World): World.World \ ef =
        match World.readOf(w) {
            case Some(r) => f(r)
            case None    => w
        }

    // ── はじめから ──

    /// はじめから読む。[遷移: Title→Reading]
    pub def newGame(res: Res.Res, w: World.World): World.World \ Emit[World.Event] =
        Emit.emit(World.Event.Opened);
        let opened = { panel = World.Panel.Closed, ask = None | w };
        let first = Talk.nodeName(Talk.Node.Opening);
        match Yarn.nodeOf(first, res#dialogue) {
            case Some(_) =>
                let (talk, events) = YarnRunner.start(res#dialogue, first, World.now(w));
                absorb(res, Replay.Live, events, { talk = talk | World.emptyRead() }, opened)
            case None =>
                showLine(res, Replay.Live, None, { speaker = "", text = "（シナリオが読めない。assets/talk/curse_chat.yarn を直して bin/fge yarn build assets/talk を流すと、ここに物語が流れる）",
                                             parts = Nil, tags = Nil, source = { file = "", line = 0 } }, World.emptyRead(), opened)
        }

    // ── シナリオの出来事を反映する ──

    /// 実行器が返した出来事を順に反映する。r は反映を始める読んでいる値（新しいシナリオの位置 talk を入れた物）。
    /// 台詞ごとの戻れる所は、最後のブックマークから「その台詞より後に受けた入力」の数だけ入力を外した物（inputsAfter と markAt）。
    /// [遷移: シナリオが終わる(Done) → Credits]
    def absorb(res: Res.Res, replay: Replay, events: List[YarnRunner.Event], r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        absorbFrom(res, replay, YarnRunner.bookmarkOf(r#talk), List.zip(events, inputsAfter(events)), World.withRead(r, w))

    /// 出来事を頭から 1 つずつ反映する。人が読み進めている時（Live）に、まだ届いていない環境音を足すコマンドに
    /// 当たったら、そこから先を素材の待ち（Hold）に預けて止まる（届いたら resumeHold が続きから反映する）。
    def absorbFrom(res: Res.Res, replay: Replay, last: Option[YarnRunner.Bookmark], pairs: List[(YarnRunner.Event, Int32)],
                   w: World.World): World.World \ Emit[World.Event] =
        match pairs {
            case Nil => w
            case (event, later) :: rest =>
                let waitFor = if (replay == Replay.Live) namesToWait(res, pairs, w) else Nil;
                if (not List.isEmpty(waitFor)) startHold(waitFor, pairs, last, w)
                else absorbFrom(res, replay, last, rest, absorbOne(res, replay, last, event, later, w))
        }

    /// 出来事 1 つ。later = その出来事より後ろに出た台詞と選択肢の数。
    // WhyNot: 選択肢を受けない — このシナリオに選択肢は無く、選ぶ画面も持たない。書かれても読み進めは止めずに捨てる。
    def absorbOne(res: Res.Res, replay: Replay, last: Option[YarnRunner.Bookmark], event: YarnRunner.Event, later: Int32,
                  w: World.World): World.World \ Emit[World.Event] =
        match event {
            case YarnRunner.Event.Line(line)       =>
                whileReading(cur -> showLine(res, replay, markAt(last, later, cur#stage), line, cur, w), w)
            case YarnRunner.Event.Choices(_)       => w
            case YarnRunner.Event.Command(command) =>
                whileReading(cur -> World.withRead(cue(res, replay, command, cur, w), w), w)
            case YarnRunner.Event.Done             => World.toCredits(res, w)
        }

    /// 出来事ごとに、それより後ろに出た台詞と選択肢の数（= その所から今までに受けた入力の数）。
    /// 台詞は送る 1 回、選択肢は選ぶ 1 回で次へ進むので、後ろに出た台詞と選択肢の数がそのまま入力の数になる。
    ///
    /// 例: 出来事が [台詞 A, <<join>>, 台詞 B, 台詞 C] なら、後ろから数えて
    ///       台詞 C → 0（後ろに何も無い）
    ///       台詞 B → 1（C）
    ///       <<join>> → 2（B・C。コマンドは入力を受けないので数えない）
    ///       台詞 A → 2
    ///     となり、[2, 2, 1, 0] を返す。台詞 B へ戻るには、今のブックマークから入力を 1 つ外せばよい（markAt）。
    def inputsAfter(events: List[YarnRunner.Event]): List[Int32] =
        let isInput = event -> match event {
            case YarnRunner.Event.Line(_)    => 1
            case YarnRunner.Event.Choices(_) => 1
            case _                           => 0
        };
        // 後ろから 1 つずつ見て、(ここまでの答え, 後ろの入力の数) を持ち回る。
        fst(List.foldRight((event, acc) -> {
            let (counts, n) = acc;
            (n :: counts, n + isInput(event))
        }, (Nil, 0), events))

    /// 最後のブックマークから入力を later 個外した所と、その時の舞台。
    /// ブックマークの steps は「ノードの頭から受けた入力」の列なので、後ろの later 個を外すとその台詞を出した所に戻る。
    def markAt(last: Option[YarnRunner.Bookmark], later: Int32, stage: Stage.Stage): Option[Saves.Mark] =
        last |> Option.map(b -> {
            let kept = Int32.max(0, List.length(b#steps) - later);
            { bookmark = { steps = List.take(kept, b#steps) | b }, screen = stage#screen, tv = stage#tv,
              ambience = stage#ambience, chill = stage#chill#target, drops = Option.nonEmpty(stage#dropsFrom) }
        })

    /// 履歴に入れる決まり（feedMax と今）。
    def ruleOf(res: Res.Res, w: World.World): Page.Rule = { feedMax = PaceDoc.rec(res#pace)#feedMax, now = World.now(w) }

    /// コマンド 1 つ（wait は実行器が待つので何もしない）。読めないコマンドは 1 行知らせて舞台はそのまま。
    def cue(res: Res.Res, replay: Replay, command: Yarn.Command, r: World.Read, w: World.World): World.Read \ Emit[World.Event] =
        let live = replay == Replay.Live;
        if (command#name == "wait") r
        else match Stage.cueOf(command) {
            case Ok(Stage.Cue.Se(name)) => if (live) { Emit.emit(World.Event.Cue("se_${name}")); r } else r
            case Ok(Stage.Cue.Presence(cast, presence)) =>
                let words = match presence {
                    case Stage.Presence.Join  => StoryDoc.Label.Joined
                    case Stage.Presence.Leave => StoryDoc.Label.Left
                };
                let line = { kind = Page.Kind.Notice(cast, presence),
                             text = "${StoryDoc.castName(cast, res#story)}${StoryDoc.labelOf(words, res#story)}",
                             source = "", glitch = false, impostor = false, gap = Talk.Gap.Normal, posted = 0 };
                if (live) Emit.emit(World.Event.Cue(presenceSound(presence))) else ();
                { stage = Stage.applyCue(World.now(w), Stage.Cue.Presence(cast, presence), r#stage),
                  page = Page.notice(ruleOf(res, w), line, r#page), doneAt = None,
                  log = List.take(KindDoc.rec(res#kind)#logMax, World.Entry.Joined(line) :: r#log) | r }
            // WhyNot: 真っ暗な画面をスキップで飛ばさせない — 暗転の静けさと血文字が、この物語の終わりそのもの。
            case Ok(Stage.Cue.ToScreen(Stage.Screen.Dark)) =>
                let playback = if (r#playback == World.Playback.Skip) World.Playback.Manual else r#playback;
                { stage = Stage.applyCue(World.now(w), Stage.Cue.ToScreen(Stage.Screen.Dark), r#stage), playback = playback | r }
            case Ok(c)                  => { stage = Stage.applyCue(World.now(w), c, r#stage) | r }
            case Err(message)           => Log.warnThen("[stage] ${message}", r)
        }

    /// 入退室の音の名前。
    def presenceSound(presence: Stage.Presence): String = match presence {
        case Stage.Presence.Join  => "se_join"
        case Stage.Presence.Leave => "se_leave"
    }

    /// シナリオの台詞の種類（話し手が空・知らない id → 地の文、caster → 字幕、3 人 → 発言）。
    def kindOf(speaker: String): Page.Kind =
        match Talk.speakerOf(speaker) |> Option.map(s -> (s, Talk.castOfSpeaker(s))) {
            case Some((_, Some(cast))) => Page.Kind.Post(cast)
            case Some((_, None))       => Page.Kind.Caption
            case None                  => Page.Kind.Thought
        }

    /// 台詞 1 行を今の行とバックログへ。#impostor の発言は、その人をここから偽物にする。新しいノードの最初の行ならオートセーブ。
    def showLine(res: Res.Res, replay: Replay, mark: Option[Saves.Mark], line: Yarn.Line, r: World.Read, w: World.World): World.World =
        let kind = kindOf(line#speaker);
        let stage = match kind {
            case Page.Kind.Post(cast) if Talk.isImpostor(line#tags) => Stage.withImpostor(cast, r#stage)
            case _                                                  => r#stage
        };
        let impostor = match kind {
            case Page.Kind.Post(cast) => List.memberOf(cast, stage#impostors)
            case _                    => false
        };
        let entry = { kind = kind, text = line#text, source = Yarn.sourceText(line#source), glitch = Talk.isGlitch(line#tags),
                      impostor = impostor, gap = Talk.gapOf(line#tags), posted = 0 };
        let page = Page.show(ruleOf(res, w), entry, r#page);
        let silent = replay == Replay.Silent;
        let shown = { page = if (silent) Page.revealAll(page) else page, stage = stage,
                      doneAt = if (silent) Some(World.now(w)) else None,
                      log = List.take(KindDoc.rec(res#kind)#logMax, World.Entry.Said(Option.getWithDefault(entry, page#current), mark) :: r#log) | r };
        if (silent) World.withRead(shown, w) else autosave(res, mark, shown, w)

    // ── 読み進める ──

    /// 押す 1 回分（読んでいる間・画面が閉じている時）。打っている途中なら全部出し（すぐ送信）、出し終えていれば次の行へ（間を飛ばす）。
    /// オートとスキップは止める（人が押したら人の速さに戻す）。
    pub def advance(res: Res.Res, w: World.World): World.World \ Emit[World.Event] =
        match World.readOf(w) {
            case Some(r) if World.isFree(w) and Option.isEmpty(r#hold) =>
                let manual = { playback = World.Playback.Manual | r };
                if (not Page.isDone(r#page)) {
                    Emit.emit(World.Event.Revealed);
                    World.withRead({ page = Page.revealAll(r#page) | manual }, w)
                } else next(res, manual, w)
            case _ => w
        }

    /// 今の行を既読にして、次の行へ送る。<<wait>> の途中は何もしない。[遷移: 行→次の行 / シナリオの終わり(Credits)]
    def next(res: Res.Res, r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        let marked = markSeen(r, w);
        match YarnRunner.shownOf(r#talk) {
            case YarnRunner.Shown.Line(_) =>
                Emit.emit(World.Event.Paged);
                let (talk, events) = YarnRunner.step(YarnRunner.Action.Advance, World.now(marked), r#talk);
                absorb(res, Replay.Live, events, { talk = talk | r }, marked)
            case YarnRunner.Shown.Closed => World.toCredits(res, World.withRead(r, marked))
            case _                       => World.withRead(r, marked)
        }

    /// 今の行を既読の印へ（初めて読んだ行の時だけ saves を変える = 書く）。
    def markSeen(r: World.Read, w: World.World): World.World =
        match r#page#current {
            case Some(line) if not String.isEmpty(line#source) and not Saves.isSeen(line#source, w#saves) =>
                World.withSaves(Saves.withSeen(line#source, w#saves), w)
            case _ => w
        }

    /// スキップが今の行を飛ばしてよいか（既読か、設定が「未読も」）。
    def isSkippable(r: World.Read, w: World.World): Bool =
        let seen = r#page#current |> Option.exists(line -> Saves.isSeen(line#source, w#saves));
        seen or World.configOf(w)#skipScope == Saves.SkipScope.Everything

    // ── 毎フレーム ──

    /// 毎フレーム（App が時計を進めた後）: <<wait>> が明けたら続きを流し、打つのを進め、出し終えた時刻を記し、間・オート・スキップを決める。
    /// 画面や確認のウィンドウを開いている間は物語の時計が止まるので、待ちも打つのも間も止まる。
    /// 素材を待っている間は、待ちの段だけを進める（dt = このフレームの実時間の秒。諦めるまでの秒を数える。確認のウィンドウの間は数えない）。
    pub def step(res: Res.Res, dt: Float64, w: World.World): World.World \ Emit[World.Event] =
        whileReading(r -> match r#hold {
            case Some(hold) => if (World.isFree(w)) stepHold(res, dt, hold, r, w) else w
            case None       => holdIfMissing(res, readOn(res, r, w))
        }, w)

    /// 今の行を打つ・出す速さ（1 秒の字数）。発言と字幕は話し手の速さに設定の倍率を掛け、地の文は設定の速さのまま。
    def cpsOf(res: Res.Res, cps: Float64, line: Page.Line): Float64 =
        let ratio = KindDoc.speedRatio(cps, res#kind);
        match line#kind {
            case Page.Kind.Post(Talk.Cast.Amanatsu) => PaceDoc.cpsOf(Talk.Speaker.Amanatsu, res#pace) * ratio
            case Page.Kind.Post(Talk.Cast.Kaabo)    => PaceDoc.cpsOf(Talk.Speaker.Kaabo, res#pace) * ratio
            case Page.Kind.Post(Talk.Cast.Kansai)   => PaceDoc.cpsOf(Talk.Speaker.Kansai, res#pace) * ratio
            case Page.Kind.Caption                  => PaceDoc.cpsOf(Talk.Speaker.Caster, res#pace) * ratio
            case _                                  => cps
        }

    /// 待っていない時の 1 歩（<<wait>>・打つ・出し終えた時刻とポコッ・間とオートとスキップ）。
    def readOn(res: Res.Res, r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        let waited = match YarnRunner.shownOf(r#talk) {
            case YarnRunner.Shown.Waiting =>
                // スキップ中は待ちも飛ばす（明ける時刻をそのまま渡す）。
                let at = if (r#playback == World.Playback.Skip) YarnRunner.waitUntilOf(r#talk) |> Option.getWithDefault(World.now(w)) else World.now(w);
                let (talk, events) = YarnRunner.step(YarnRunner.Action.Tick, at, r#talk);
                absorb(res, Replay.Live, events, { talk = talk | r }, w)
            case _ => w
        };
        whileReading(cur -> {
            let cps = World.configOf(waited)#cps;
            let noWait = KindDoc.isNoWait(cps, res#kind);
            let fast = noWait or (cur#playback == World.Playback.Skip and isSkippable(cur, waited));
            let page = match cur#page#current {
                case Some(line) if not fast => Page.step(cpsOf(res, cps, line), Clock.dtOf(waited#storyClock), cur#page)
                case _                      => Page.revealAll(cur#page)
            };
            let typed = { page = page | cur };
            let stamped = if (Page.isDone(page) and Option.isEmpty(typed#doneAt)) {
                if (cur#page#current |> Option.exists(Page.isPost)) Emit.emit(World.Event.Posted) else ();
                { doneAt = Some(World.now(waited)) | typed }
            } else typed;
            autoOrSkip(res, stamped, waited)
        }, waited)

    /// 出し終えた行が自分で流れるまでの秒（発言と字幕は間・地の文と行の無い所は None = 人が押す）。
    def flowSeconds(res: Res.Res, line: Option[Page.Line]): Option[Float64] = match line {
        case Some(l) if Page.isPost(l) or l#kind == Page.Kind.Caption => Some(PaceDoc.gapSeconds(String.length(l#text), l#gap, res#pace))
        case _                                                         => None
    }

    /// 間・オート・スキップ（行を出し終えてから、決めた間が過ぎたら送る）。
    /// スキップは読んでいない行で止まるか（設定の「スキップ」）。
    def autoOrSkip(res: Res.Res, r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        let manual = World.withRead({ playback = World.Playback.Manual | r }, w);
        if (not World.isFree(w)) World.withRead(r, w)
        else if (r#playback == World.Playback.Skip and Option.nonEmpty(r#page#current) and not isSkippable(r, w)) manual
        else match r#doneAt {
            case None     => World.withRead(r, w)
            case Some(at) =>
                let k = KindDoc.rec(res#kind);
                let waited = Clock.since(at, World.now(w));
                let chars = r#page#current |> Option.map(line -> String.length(line#text)) |> Option.getWithDefault(0);
                let autoWait = World.configOf(w)#autoWait + Int32.toFloat64(chars) * k#autoPerChar;
                match (r#playback, flowSeconds(res, r#page#current)) {
                    case (World.Playback.Skip, _)       => if (waited >= k#skipInterval) next(res, r, w) else World.withRead(r, w)
                    case (_, Some(gap))                 => if (waited >= gap) next(res, r, w) else World.withRead(r, w)
                    case (World.Playback.Auto, None)    => if (waited >= autoWait) next(res, r, w) else World.withRead(r, w)
                    case (World.Playback.Manual, None)  => World.withRead(r, w)
                }
        }

    /// オートかスキップを、点いていれば消し（人が押す）、そうでなければそれに替える。
    pub def togglePlayback(mode: World.Playback, w: World.World): World.World \ Emit[World.Event] =
        whileReading(r -> {
            Emit.emit(World.Event.Moved);
            World.withRead({ playback = if (r#playback == mode) World.Playback.Manual else mode | r }, w)
        }, w)

    // ── オートセーブ・今の所のデータ ──

    /// 今の所のデータ（読んでいなければ None）。セーブの画面とクイックセーブが書く。
    pub def slotHere(res: Res.Res, w: World.World): Option[Saves.Slot] =
        World.readOf(w) |> Option.flatMap(r -> slotAt(res, None, r, w))

    /// 画面の名前（セーブの枠の「場所」）。
    def placeOf(res: Res.Res, screen: Stage.Screen): String =
        let label = match screen {
            case Stage.Screen.Chat => StoryDoc.Label.PlaceChat
            case Stage.Screen.Tv   => StoryDoc.Label.PlaceNews
            case Stage.Screen.Dark => StoryDoc.Label.PlaceDark
        };
        StoryDoc.labelOf(label, res#story)

    /// 行の話し手の呼び名（地の文・入退室は空）。
    pub def speakerName(res: Res.Res, line: Page.Line): String = match line#kind {
        case Page.Kind.Post(cast) => StoryDoc.castName(cast, res#story)
        case Page.Kind.Caption    => StoryDoc.nameOf(Talk.speakerId(Talk.Speaker.Caster), res#story)
        case _                    => ""
    }

    /// mark を渡せばその戻れる所で、無ければ今のブックマークで作るデータ。
    def slotAt(res: Res.Res, mark: Option[Saves.Mark], r: World.Read, w: World.World): Option[Saves.Slot] =
        let here = match mark {
            case Some(m) => Some(m)
            case None    => markAt(YarnRunner.bookmarkOf(r#talk), 0, r#stage)
        };
        here |> Option.map(m -> {
            let (speaker, excerpt) = r#page#current |> Option.map(line -> (speakerName(res, line), String.takeLeft(80, line#text)))
                |> Option.getWithDefault(("", ""));
            { mark = m, place = placeOf(res, m#screen), speaker = speaker, excerpt = excerpt, savedAt = savedAtNow(w),
              serial = Saves.nextSerial(w#saves) }
        })

    /// 今のその土地の時刻（秒）。
    def savedAtNow(w: World.World): Int64 =
        w#clockBase + (Float64.tryToInt64(Float64.floor(Clock.secondsOf(w#realNow))) |> Option.getWithDefault(0i64))

    /// 新しいノードの最初の行でオートセーブ（オートのページの先頭へ。音も知らせも出さない）。
    def autosave(res: Res.Res, mark: Option[Saves.Mark], r: World.Read, w: World.World): World.World =
        let node = YarnRunner.nodeOf(r#talk);
        if (Option.isEmpty(node) or node == r#autosavedNode) World.withRead(r, w)
        else match slotAt(res, mark, r, w) {
            case Some(slot) =>
                World.withSaves(Saves.withPushed(Saves.Tab.Auto, slot, w#saves), World.withRead({ autosavedNode = node | r }, w))
            case None => World.withRead(r, w)
        }

    // ── 戻れる所へ戻す ──

    /// 戻れる所の舞台（前のノードから持ち越す物を Mark の値から始める。冷えは目標の値・水滴は付き切った形）。
    def carriedOf(mark: Saves.Mark): Stage.Stage =
        let e = Stage.empty();
        { screen = mark#screen, tv = mark#tv, ambience = mark#ambience,
          chill = { base = mark#chill, target = mark#chill | e#chill },
          dropsFrom = if (mark#drops) Some(Clock.never()) else None | e }

    /// 戻れる所へ戻す: ブックマークを当て直し、通ったコマンドを音を出さずに反映して舞台と履歴とバックログを作り直す。
    /// 前のノードから持ち越す画面・環境音・冷え・水滴は Mark の値から始め、演出の途中は終わりの形にする。
    /// 画面と確認のウィンドウは閉じる。[遷移: Title / Reading→Reading]
    pub def restore(res: Res.Res, mark: Saves.Mark, w: World.World): World.World \ Emit[World.Event] =
        let (talk, events) = YarnRunner.resume(res#dialogue, mark#bookmark, World.now(w));
        let gaveUp = World.readOf(w) |> Option.map(r -> r#gaveUp) |> Option.getWithDefault(Set.empty());
        settled(absorb(res, Replay.Silent, events, { talk = talk, stage = carriedOf(mark), gaveUp = gaveUp | World.emptyRead() },
                       { panel = World.Panel.Closed, ask = None | w }))

    /// 当て直した後の形: 演出の途中は終わりの形にし、今のノードはオートセーブ済みとして扱う（戻った所で同じ物を残さない）。
    def settled(w: World.World): World.World =
        World.mapRead(r -> { stage = Stage.settle(r#stage), autosavedNode = YarnRunner.nodeOf(r#talk) | r }, w)

    /// セーブの枠のサムネに映す画面: その枠の戻れる所へ音を出さずに戻した World（文は出し終え、画面・確認のウィンドウは閉じ、マウスはどこにも乗せない）。
    /// WhyNot: 保存の時に画面の絵を撮って残さない —— セーブの JSON に絵を入れると重く、描き出しと実機で同じ絵にならない。
    pub def screenOf(res: Res.Res, mark: Saves.Mark, w: World.World): World.World =
        let (back, _) = Emit.collect(() -> restore(res, mark, w));
        World.withPointer({ x = -1.0, y = -1.0 }, back)

    // ── 素材の待ち（ブラウザ版で後回しにした環境音がまだ届いていない時） ──
    //
    // 待つのは環境音だけ（一発の効果音は待たず、届いていなければ鳴らさない = Controls.sounds。絵は図形で描いて待たない）。
    // 段は FadingOut（黒へ重ねる・物語の時計は動く）→ Waiting（黒のまま・物語の時計を止める = World.paceOf）→ FadingIn（黒から戻す）。
    // Waiting は実時間で holdGiveUpSeconds まで待ち、届かなければその素材を諦め（gaveUp）、無いまま進む。
    // 入り口は 2 つ: 読み進めて未着の環境音を足す所（absorbFrom。続きの出来事を預ける）と、
    // 今の舞台の環境音が未着のまま止まった所（holdIfMissing。スキップが止まった・ロードや「戻る」で戻った）。

    /// pairs の頭が、まだ届いていない環境音を足すコマンドなら、次の台詞までに足す環境音のうち
    /// まだ届いていない物の名前（暗転 1 回でまとめて待つ）。頭がそうでない・スキップ中（止まった所で待つ）なら空。
    def namesToWait(res: Res.Res, pairs: List[(YarnRunner.Event, Int32)], w: World.World): List[String] =
        let cues = pairs |> List.map(fst) |> List.takeWhile(isCommand);
        match World.readOf(w) {
            case Some(r) if r#playback != World.Playback.Skip =>
                let head = List.head(cues) |> Option.map(event -> pendingNames(res, r, eventNames(event))) |> Option.getWithDefault(Nil);
                if (List.isEmpty(head)) Nil else pendingNames(res, r, List.flatMap(eventNames, cues))
            case _ => Nil
        }

    def isCommand(event: YarnRunner.Event): Bool = match event {
        case YarnRunner.Event.Command(_) => true
        case _                           => false
    }

    /// 出来事が足す環境音の名前（コマンドでなければ空）。
    def eventNames(event: YarnRunner.Event): List[String] = match event {
        case YarnRunner.Event.Command(command) =>
            Stage.cueOf(command) |> Result.toOption |> Option.map(cueNames) |> Option.getWithDefault(Nil)
        case _ => Nil
    }

    /// コマンドの意味が使う環境音の名前（project.json の sounds の name）。
    def cueNames(cue: Stage.Cue): List[String] = match cue {
        case Stage.Cue.Ambience(name, Some(_)) => Stage.ambienceSound(name) :: Nil
        case _                                 => Nil
    }

    /// 舞台が鳴らしている環境音の名前。
    def stageNames(stage: Stage.Stage): List[String] = stage#ambience |> List.map(l -> Stage.ambienceSound(l#name))

    /// names のうち、まだ届いていなくて、諦めてもいない物（重なりは 1 つに）。
    def pendingNames(res: Res.Res, r: World.Read, names: List[String]): List[String] =
        names |> List.filter(name -> Set.memberOf(name, res#missing) and not Set.memberOf(name, r#gaveUp)) |> List.distinct

    /// 素材の待ちに入る（黒へ重ね始める）。rest = 届いたら反映する続きの出来事、last = その台詞の戻れる所の元。
    def startHold(names: List[String], rest: List[(YarnRunner.Event, Int32)], last: Option[YarnRunner.Bookmark], w: World.World): World.World =
        let hold = { phase = World.HoldPhase.FadingOut, phaseFrom = World.now(w), waited = 0.0, names = names, rest = rest, last = last };
        World.mapRead(r -> { hold = Some(hold) | r }, w)

    /// 今の舞台の環境音がまだ届いていなければ、ここで待つ（続きは無い。届いたら黒から戻すだけ）。
    /// スキップ中と、画面や確認のウィンドウを開いている間は入らない（閉じた・止まった所で入る）。
    def holdIfMissing(res: Res.Res, w: World.World): World.World =
        match World.readOf(w) {
            case Some(r) if r#playback != World.Playback.Skip and World.isFree(w) =>
                let names = pendingNames(res, r, stageNames(r#stage));
                if (List.isEmpty(names)) w else startHold(names, Nil, YarnRunner.bookmarkOf(r#talk), w)
            case _ => w
        }

    /// 待ちの段を 1 歩進める。黒へ重ね切ったら Waiting、届いたら（か諦めたら）続きを反映して FadingIn、黒から戻し切ったら待ちを消す。
    def stepHold(res: Res.Res, dt: Float64, hold: World.Hold, r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        let k = KindDoc.rec(res#kind);
        let faded = Clock.since(hold#phaseFrom, World.now(w)) >= k#holdFadeSeconds;
        let withHold = (next: Option[World.Hold]) -> World.withRead({ hold = next | r }, w);
        match hold#phase {
            case World.HoldPhase.FadingOut => if (faded) withHold(Some({ phase = World.HoldPhase.Waiting, waited = 0.0 | hold })) else w
            case World.HoldPhase.FadingIn  => if (faded) withHold(None) else w
            case World.HoldPhase.Waiting   =>
                let left = pendingNames(res, r, hold#names);
                let waited = hold#waited + dt;
                if (List.isEmpty(left)) resumeHold(res, hold, r, w)
                else if (waited >= k#holdGiveUpSeconds) resumeHold(res, hold, { gaveUp = Set.union(r#gaveUp, List.toSet(left)) | r }, w)
                else withHold(Some({ waited = waited | hold }))
        }

    /// 届いた（か諦めた）: 黒から戻し始め、預けておいた続きの出来事を反映する。
    def resumeHold(res: Res.Res, hold: World.Hold, r: World.Read, w: World.World): World.World \ Emit[World.Event] =
        let opening = World.withRead({ hold = Some({ phase = World.HoldPhase.FadingIn, phaseFrom = World.now(w), rest = Nil | hold }) | r }, w);
        absorbFrom(res, Replay.Live, hold#last, hold#rest, opening)

    // ── 始まりの場面（Starts・描き出し） ──

    /// node の頭から、.yarn の line 行を出している所まで進めた World（Studio の会話のプレビュー・bin/fge talk goto）。
    /// 通ったコマンドは音を出さずに反映し、演出の途中は終わりの形にする。
    pub def openAt(res: Res.Res, storage: YarnStorage.Storage, node: String, line: Int32, w: World.World): World.World \ Emit[World.Event] =
        let (talk, events) = YarnRunner.startAtWith(storage, res#dialogue, node, line, World.now(w));
        settled(absorb(res, Replay.Silent, events, { talk = talk | World.emptyRead() }, { panel = World.Panel.Closed, ask = None | w }))

    /// 今の行を出し終えた形（描き出しが場面を作る時。時計を進めずに 1 行読み終える）。
    pub def revealLine(w: World.World): World.World = World.mapRead(r -> { page = Page.revealAll(r#page) | r }, w)

    /// シナリオを差し替えた後に World を収める（保存即反映。res は差し替えた後の描く元）。
    /// 読んでいる途中なら、開いているノードの頭から読み直す（編集がその場で画面に出る）。
    /// WhyNot: 読んでいた行から続けない —— 行の並びが変わると「同じ行」が決まらない。
    pub def settleDialogue(res: Res.Res, w: World.World): World.World =
        match World.readOf(w) {
            case Some(r) => reopenNode(res, r, w)
            case None    => w
        }

    /// 開いていたノードを新しいシナリオの頭から開き直す（ノードが消えていればタイトルへ）。
    def reopenNode(res: Res.Res, r: World.Read, w: World.World): World.World =
        match YarnRunner.nodeOf(r#talk) {
            case Some(node) if Option.nonEmpty(Yarn.nodeOf(node, res#dialogue)) =>
                let (talk, events) = YarnRunner.startWith(YarnRunner.storageOf(r#talk), res#dialogue, node, World.now(w));
                fst(Emit.collect(() -> absorb(res, Replay.Silent, events, { talk = talk, page = Page.empty(), hold = None | r }, w)))
            case Some(_) => World.toTitle(w)
            case None    => w
        }
}
