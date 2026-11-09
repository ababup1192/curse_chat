// ルールと進行だけをテストする。座標・描き方・打つ速さの見た目はテストしない。
// シナリオは本物（curse_chat.yarn を build した木）。行の文字は写さず、ノードの名前・台本の木・Doc から期待値を導く。
mod TestRules {

    use fge::{App, AudioMixer, Clock, Emit, JsonCodec, Vec2, Yarn}
    use Util.Json.Json
    use TestKit.{advance, begun, isThought, nextLine, placeOf, playing, quiet, readUntil, settle, w0}

    def kind(res: Res.Res): KindDoc.Rec = KindDoc.rec(res#kind)

    /// 台本の木の台詞（Say）の話し手の id を、全部のノードから上から。
    def saySpeakers(res: Res.Res): List[String] =
        Yarn.nodeNames(res#dialogue) |> List.filterMap(n -> Yarn.nodeOf(n, res#dialogue)) |> List.flatMap(node ->
            node#body |> List.filterMap(statement -> match statement {
                case Yarn.Statement.Say(say) => Some(say#speaker)
                case _                       => None
            }))

    /// 今の行（無ければ None）。
    def currentOf(w: World.World): Option[Page.Line] = World.pageOf(w)#current

    /// 履歴の入退室の行の (人, 入退室)。
    def noticesOf(w: World.World): List[(Talk.Cast, Stage.Presence)] =
        Page.shownFeed(World.pageOf(w)) |> List.filterMap(line -> match line#kind {
            case Page.Kind.Notice(cast, presence) => Some((cast, presence))
            case _                                => None
        })

    def countOf(event: World.Event, events: List[World.Event]): Int32 = List.count(e -> e == event, events)

    /// dt 秒ずつ系を回し、until が真になった所（fuel で必ず止まる）。
    def stepsUntil(res: Res.Res, dt: Float64, until: World.World -> Bool, w: World.World): World.World =
        def go(fuel: Int32, cur: World.World): World.World =
            if (fuel <= 0 or until(cur)) cur else go(fuel - 1, TestKit.stepBy(res, dt, cur));
        go(3000, w)

    def screenOf(res: Res.Res, w: World.World): Stage.Screen = World.stageOf(res, w)#screen

    // ══ タイトルと始まり ══

    @Test
    def testNewGameOpensTheChatAfterTheJoins(): Unit \ {Assert, Fs.FileRead} =
        // はじめから: コードが開くノード（Talk.Node.Opening）をチャットの画面で開き、最初の発言を出すまでに 3 人が入室している。
        let res = TestKit.res();
        let w = begun(res);
        Assert.assertEq(expected = ("Reading", Talk.nodeName(Talk.Node.Opening), Stage.Screen.Chat, Talk.casts()),
                        (World.sceneName(w), World.talkNodeOf(w), screenOf(res, w), World.stageOf(res, w)#online))

    /// ギャラリーの場面は全部（背景なしの none- も）、実機と同じ App から shot:<名前> の始まりで組める。
    @Test
    def testEveryShotBuildsFromTheApp(): Unit \ {Assert, Fs.FileRead} =
        let res = TestKit.res();
        let app = TestKit.app(res, w0(res));
        Assert.assertEq(expected = Nil,
            Shots.names() |> List.filter(name -> Result.isErr(App.buildStart(app, Vec2.zero(), App.shotStartName(name), Map.empty()))))

    @Test
    def testShotNameChoosesTheBackdrop(): Unit \ {Assert, Fs.FileRead} =
        // 場面の名前の頭 none- は背景なし、頭が無ければ部屋の絵。
        let res = TestKit.res();
        let backdropOf = name -> Shots.shotOf(name, res) |> Option.map(match (r, _) -> Art.backdropOf(r#art));
        Assert.assertEq(expected = (Some(Art.Backdrop.Bare), Some(Art.Backdrop.Room)), (backdropOf("none-thought"), backdropOf("thought")))

    // ══ 発言が流れる ══

    @Test
    def testChatPostAdvancesWithoutInput(): Unit \ {Assert, Fs.FileRead} =
        // 発言は出し終えてから間（chat.pace.json の gapBase + 字数 × gapPerChar + タグの段）が過ぎると、押さなくても次へ流れる。
        // 間の半ばではまだ流れない。
        let res = TestKit.res();
        let w = begun(res);
        let line = currentOf(w);
        let gap = line |> Option.map(l -> PaceDoc.gapSeconds(String.length(l#text), l#gap, res#pace)) |> Option.getWithDefault(0.0);
        let early = TestKit.stepBy(res, gap * 0.5, w);
        let late = TestKit.stepBy(res, gap + 0.1, w);
        Assert.assertEq(expected = (placeOf(w), true), (placeOf(early), placeOf(late) != placeOf(w)))

    @Test
    def testClickWhileTypingPostsAtOnce(): Unit \ {Assert, Fs.FileRead} =
        // 打っている途中に押すと、行は動かずにすぐ全部出る（すぐ送信）。
        let res = TestKit.res();
        let typing = TestKit.stepBy(res, 0.05, advance(res, begun(res)));
        let pressed = advance(res, typing);
        Assert.assertEq(expected = (false, true, placeOf(typing)), (Page.isDone(World.pageOf(typing)), Page.isDone(World.pageOf(pressed)), placeOf(pressed)))

    @Test
    def testClickAfterPostSkipsTheGap(): Unit \ {Assert, Fs.FileRead} =
        // 出し終えた後に押すと、間を待たずに次の行へ送る（送った行は既読になる）。
        let res = TestKit.res();
        let w = begun(res);
        let pressed = advance(res, w);
        Assert.assertEq(expected = (true, true), (placeOf(pressed) != placeOf(w), Saves.isSeen(World.talkLineOf(w), pressed#saves)))

    @Test
    def testThoughtLineWaitsForInput(): Unit \ {Assert, Fs.FileRead} =
        // 地の文は出し終えても勝手には流れない（人が押す）。押せば次へ。
        let res = TestKit.res();
        let atThought = readUntil(res, isThought, begun(res));
        let later = TestKit.stepBy(res, 30.0, atThought);
        Assert.assertEq(expected = (true, placeOf(atThought), true), (isThought(atThought), placeOf(later), placeOf(advance(res, later)) != placeOf(atThought)))

    @Test
    def testAutoSendsAThoughtAfterTheWait(): Unit \ {Assert, Fs.FileRead} =
        // オート: 地の文も、出し終えてから「待ち + 字数 × autoPerChar」が過ぎると次へ。その前は送らない。
        let res = TestKit.res();
        let w = playing(World.Playback.Auto, readUntil(res, isThought, begun(res)));
        let chars = currentOf(w) |> Option.map(line -> String.length(line#text)) |> Option.getWithDefault(0);
        let wait = Saves.configOf(w#saves)#autoWait + Int32.toFloat64(chars) * kind(res)#autoPerChar;
        let early = TestKit.stepBy(res, wait * 0.5, w);
        let late = TestKit.stepBy(res, wait + 0.1, w);
        Assert.assertEq(expected = (placeOf(w), true), (placeOf(early), placeOf(late) != placeOf(w)))

    @Test
    def testWaitCannotBeClickedThrough(): Unit \ {Assert, Fs.FileRead} =
        // 台本の <<wait>> の間は、押しても先へ進まない（劇的な間を飛ばさせない）。
        let res = TestKit.res();
        let opened = quiet(() -> WorldRead.newGame(res, w0(res)));
        let pressed = advance(res, advance(res, opened));
        Assert.assertEq(expected = (true, true, placeOf(opened)), (TestKit.isWaiting(opened), TestKit.isWaiting(pressed), placeOf(pressed)))

    @Test
    def testJoinAddsASystemLine(): Unit \ {Assert, Fs.FileRead} =
        // <<join 名>> は履歴に入室の行を入れる（台本の頭の 3 つの入室が、その順で並ぶ）。
        let res = TestKit.res();
        let joined = Talk.casts() |> List.map(c -> (c, Stage.Presence.Join));
        Assert.assertEq(expected = joined, noticesOf(begun(res)))

    @Test
    def testImpostorChangesOnlyLaterPosts(): Unit \ {Assert, Fs.FileRead} =
        // #impostor の発言から、その人の発言は偽物の印が付く（それより前に履歴へ入った同じ人の発言は本物のまま）。
        let res = TestKit.res();
        let w = settle(res, advance(res, readUntil(res, cur -> currentOf(cur) |> Option.exists(l -> l#impostor), begun(res))));
        let cast = World.stageOf(res, w)#impostors |> List.head;
        let flags = Page.shownFeed(World.pageOf(w)) |> List.filter(l -> Option.nonEmpty(cast) and Page.castOf(l) == cast and Page.isPost(l))
            |> List.map(l -> l#impostor);
        Assert.assertEq(expected = (false, true), (List.exists(f -> f, List.take(List.length(flags) - 1, flags)), List.last(flags) == Some(true)))

    @Test
    def testFeedKeepsOnlyFeedMaxLines(): Unit \ {Assert, Fs.FileRead} =
        // 履歴は chat.pace.json の feedMax 行まで（古い方から落とす）。
        let res = TestKit.res();
        let small = Res.withPace(PaceDoc.Doc.Doc({ feedMax = 2 | PaceDoc.rec(res#pace) }), res);
        let w = begun(small) |> nextLine(small) |> nextLine(small);
        Assert.assertEq(expected = true, List.length(World.pageOf(w)#feed) <= 2)

    // ══ ポコッ ══

    @Test
    def testEveryCastLinePopsOnce(): Unit \ {Assert, Fs.FileRead} =
        // 頭からクレジットまで読むと、チャットの 3 人の発言の数（台本の木の Say のうち話し手が 3 人の物）だけポコッ（Posted）が鳴る。
        let res = TestKit.res();
        let (opened, e0) = Emit.collect(() -> WorldRead.newGame(res, w0(res)));
        let (settled, e1) = TestKit.settleHearing(res, opened);
        let (end, e2) = TestKit.readHearing(res, World.isCredits, settled);
        let castIds = Talk.casts() |> List.map(Talk.castId);
        let posts = saySpeakers(res) |> List.count(id -> List.memberOf(id, castIds));
        Assert.assertEq(expected = (true, posts), (World.isCredits(end), countOf(World.Event.Posted, List.flatten(e0 :: e1 :: e2 :: Nil))))

    @Test
    def testCasterLinesDoNotPop(): Unit \ {Assert, Fs.FileRead} =
        // テレビの字幕（キャスター）・入退室・地の文ではポコッは鳴らない（ニュースのノードを終わりまで読んでも 0）。
        let res = TestKit.res();
        let (_, heard) = TestKit.readHearing(res, World.isCredits, TestKit.openNode(res, "News"));
        Assert.assertEq(expected = (0, true), (countOf(World.Event.Posted, heard), countOf(World.Event.Paged, heard) > 0))

    @Test
    def testRestoreDoesNotPop(): Unit \ {Assert, Fs.FileRead} =
        // 戻れる所へ戻した時（ロード・戻る）と、その直後に時計が進んでも、当て直した発言のポコッは鳴らない。
        let res = TestKit.res();
        let w = begun(res) |> nextLine(res) |> nextLine(res);
        let mark = WorldRead.slotHere(res, w) |> Option.map(s -> s#mark);
        let heard = mark |> Option.map(m -> {
            let (back, e0) = Emit.collect(() -> WorldRead.restore(res, m, w));
            let (_, e1) = Emit.collect(() -> WorldRead.step(res, 0.1, TestKit.tickClocks(res, 0.1, back)));
            List.append(e0, e1)
        }) |> Option.getWithDefault(World.Event.Posted :: Nil);
        Assert.assertEq(expected = 0, countOf(World.Event.Posted, heard))

    @Test
    def testPopsAtMostOncePerFrame(): Unit \ {Assert} =
        // 1 フレームに出来事が何度出ても、同じ音は 1 回だけ鳴らす（スキップでポコッが束になって割れない）。
        Assert.assertEq(expected = "se_post" :: Nil, Controls.soundsOf(Set.empty(), World.Event.Posted :: World.Event.Posted :: World.Event.Paged :: Nil))

    // ══ 舞台 ══

    @Test
    def testEveryCommandInTheScriptIsUnderstood(): Unit \ {Assert, Fs.FileRead} =
        // 台本のコマンドは全部 Stage が読める（入退室の名・テレビの映り・数の引数）。wait は実行器が待つ。
        let res = TestKit.res();
        let bad = commandsOf(res#dialogue) |> List.filter(c -> c#name != "wait")
            |> List.filterMap(c -> match Stage.cueOf(c) {
                case Ok(_)    => None
                case Err(why) => Some(why)
            });
        Assert.assertEq(expected = Nil, bad)

    def commandsOf(program: Yarn.Program): List[Yarn.Command] =
        def walk(body: List[Yarn.Statement]): List[Yarn.Command] = body |> List.flatMap(statement -> match statement {
            case Yarn.Statement.Command(c)      => c :: Nil
            case Yarn.Statement.Choose(cs)      => cs |> List.flatMap(choice -> walk(choice#body))
            case Yarn.Statement.If(branches, _) => branches |> List.flatMap(b -> walk(b#body))
            case _                              => Nil
        });
        Yarn.nodeNames(program) |> List.filterMap(name -> Yarn.nodeOf(name, program)) |> List.flatMap(node -> walk(node#body))

    @Test
    def testAmbienceLayersSoundTogether(): Unit \ {Assert, Fs.FileRead} =
        // <<ambience 名 音量>> は層を足していき、鳴り続ける音は層の数だけ、それぞれの音量で重なる（ニュースの砂嵐の裏に水の音）。
        let res = TestKit.res();
        let w = readUntil(res, cur -> List.length(World.stageOf(res, cur)#ambience) >= 2, TestKit.openNode(res, "News"));
        let expected = World.stageOf(res, w)#ambience |> List.map(l -> (Stage.ambienceSound(l#name), l#volume));
        Assert.assertEq(expected = (2, expected), (List.length(expected), Controls.ambience(res, w) |> List.map(s -> (s#name, s#volume))))

    @Test
    def testSilenceStopsEveryLayer(): Unit \ Assert =
        // <<silence>> は重ねた層を全部すぐ止める。<<ambience 名 off>> はその層だけを外す。
        let now = Clock.zero();
        let two = Stage.empty() |> Stage.applyCue(now, Stage.Cue.Ambience("room", Some(0.5))) |> Stage.applyCue(now, Stage.Cue.Ambience("water", Some(0.5)));
        let off = Stage.applyCue(now, Stage.Cue.Ambience("room", None), two);
        let silent = Stage.applyCue(now, Stage.Cue.Silence, two);
        Assert.assertEq(expected = (2, "water" :: Nil, 0),
                        (List.length(two#ambience), off#ambience |> List.map(l -> l#name), List.length(silent#ambience)))

    @Test
    def testChillMovesToItsTargetOverItsSeconds(): Unit \ Assert =
        // <<chill 目標 秒>> は、秒の半ばでは途中・秒が過ぎると目標の冷えになる。
        let now = Clock.zero();
        let st = Stage.applyCue(now, Stage.Cue.Chill(1.0, 2.0), Stage.empty());
        let mid = Stage.chillAt(Clock.after(1.0, now), st);
        Assert.assertEq(expected = (true, 1.0), (mid > 0.0 and mid < 1.0, Stage.chillAt(Clock.after(2.0, now), st)))

    @Test
    def testScareHidesAfterScareSeconds(): Unit \ {Assert, Fs.FileRead} =
        // 血文字は出してから scareSeconds の間だけ出ていて、過ぎるとまた真っ暗に戻る。
        let res = TestKit.res();
        let seconds = PaceDoc.rec(res#pace)#scareSeconds;
        let now = Clock.zero();
        let st = Stage.applyCue(now, Stage.Cue.Scare("x"), Stage.empty());
        Assert.assertEq(expected = (Some("x"), None),
                        (Stage.scareShown(Clock.after(seconds * 0.5, now), seconds, st), Stage.scareShown(Clock.after(seconds + 0.01, now), seconds, st)))

    @Test
    def testSkipStopsAtDark(): Unit \ {Assert, Fs.FileRead} =
        // スキップ（未読も）でニュースを飛ばしても、真っ暗な画面に入ったところで送り方は人の手に戻る。
        let res = TestKit.res();
        let all = quiet(() -> WorldSettings.withSide(World.Pair.SkipScope, Layout.Side.Right, TestKit.openNode(res, "News")));
        let w = stepsUntil(res, 0.1, cur -> screenOf(res, cur) == Stage.Screen.Dark, playing(World.Playback.Skip, all));
        Assert.assertEq(expected = (Stage.Screen.Dark, World.Playback.Manual), (screenOf(res, w), World.playbackOf(w)))

    @Test
    def testStoryEndRollsTheCredits(): Unit \ {Assert, Fs.FileRead} =
        // シナリオの終わり（血文字の後）まで読むとクレジットへ。
        let res = TestKit.res();
        let done = readUntil(res, World.isCredits, TestKit.openNode(res, "News"));
        Assert.assertEq(expected = true, World.isCredits(done))

    // ══ オート・スキップ ══

    @Test
    def testSkipStopsAtUnreadLines(): Unit \ {Assert, Fs.FileRead} =
        // スキップ（既読のみ）は読んでいない行に来たら切れる。
        let res = TestKit.res();
        let w = TestKit.stepBy(res, kind(res)#skipInterval, playing(World.Playback.Skip, begun(res)));
        Assert.assertEq(expected = World.Playback.Manual, World.playbackOf(w))

    @Test
    def testSkipPassesReadLines(): Unit \ {Assert, Fs.FileRead} =
        // 読んだ行（既読）はスキップが間を待たずに送る。
        let res = TestKit.res();
        let first = begun(res);
        let seen = World.withSaves(Saves.withSeen(World.talkLineOf(first), first#saves), first);
        let w = TestKit.stepBy(res, kind(res)#skipInterval + 0.01, playing(World.Playback.Skip, seen));
        Assert.assertEq(expected = true, placeOf(w) != placeOf(first))

    @Test
    def testPressingStopsAutoAndSkip(): Unit \ {Assert, Fs.FileRead} =
        // 人が押したらオートもスキップも止める（人の速さに戻す）。
        let res = TestKit.res();
        let auto = advance(res, playing(World.Playback.Auto, begun(res)));
        let skip = advance(res, playing(World.Playback.Skip, begun(res)));
        Assert.assertEq(expected = (World.Playback.Manual, World.Playback.Manual), (World.playbackOf(auto), World.playbackOf(skip)))

    // ══ 画面と確認のウィンドウ ══

    @Test
    def testOpenPanelStopsTheStoryClock(): Unit \ {Assert, Fs.FileRead} =
        // 画面を開いている間は物語の時計が止まる（待ち・打つ・発言の間が進まない）。
        let res = TestKit.res();
        let w = quiet(() -> WorldLog.openLog(begun(res)));
        let later = TestKit.stepBy(res, 5.0, w);
        Assert.assertEq(expected = (Clock.nowOf(w#storyClock), placeOf(w)), (Clock.nowOf(later#storyClock), placeOf(later)))

    @Test
    def testAskingStopsTheStoryClockAndBlocksAdvance(): Unit \ {Assert, Fs.FileRead} =
        // 確認のウィンドウを開いている間も物語の時計は止まり、押しても本文は進まない。
        let res = TestKit.res();
        let w = quiet(() -> World.askFor(World.Ask.ToTitle, begun(res)));
        let later = advance(res, TestKit.stepBy(res, 5.0, w));
        Assert.assertEq(expected = (Clock.nowOf(w#storyClock), placeOf(w)), (Clock.nowOf(later#storyClock), placeOf(later)))

    @Test
    def testAnsweringNoKeepsReading(): Unit \ {Assert, Fs.FileRead} =
        // 「タイトルに戻りますか？」にいいえと答えると、ウィンドウが閉じて同じ所を読み続ける。はいならタイトルへ。
        let res = TestKit.res();
        let w = quiet(() -> World.askFor(World.Ask.ToTitle, begun(res)));
        let no = quiet(() -> WorldMenu.answer(res, World.Answer.No, w));
        let yes = quiet(() -> WorldMenu.answer(res, World.Answer.Yes, w));
        Assert.assertEq(expected = ((None, "Reading", placeOf(w)), "Title"),
                        ((World.askOf(no), World.sceneName(no), placeOf(no)), World.sceneName(yes)))

    @Test
    def testCloseButtonAsksBeforeQuitting(): Unit \ {Assert, Fs.FileRead} =
        // ウィンドウの閉じるボタンはすぐ終えず「終了しますか？」を出し、はいで終了の印が立つ。
        let res = TestKit.res();
        let asked = World.requestQuit(begun(res));
        let quit = quiet(() -> WorldMenu.answer(res, World.Answer.Yes, asked));
        Assert.assertEq(expected = (Some(World.Ask.Quit), false, true), (World.askOf(asked), asked#quitting, quit#quitting))

    @Test
    def testButtonsShowOnlyOnTheChat(): Unit \ Assert =
        // クイックメニューはチャットの画面の間だけ出す（テレビと真っ暗な画面には出さない）。
        Assert.assertEq(expected = (true, false, false),
                        (WorldMenu.showsButtons(Stage.Screen.Chat), WorldMenu.showsButtons(Stage.Screen.Tv), WorldMenu.showsButtons(Stage.Screen.Dark)))

    // ══ バックログと戻る ══

    def sourceOf(entry: World.Entry): String = match entry {
        case World.Entry.Said(line, _) => line#source
        case World.Entry.Joined(_)     => ""
    }

    @Test
    def testLogKeepsNewestFirstAndCapsAtLogMax(): Unit \ {Assert, Fs.FileRead} =
        // バックログは新しい順に積み（入退室の行も入る）、logMax を超えない。
        let res = TestKit.res();
        let w = nextLine(res, begun(res));
        let small = Res.withKind(KindDoc.Doc.Doc({ logMax = 1 | kind(res) }), res);
        let capped = nextLine(small, w);
        Assert.assertEq(expected = (Some(World.talkLineOf(w)), 1),
                        (List.head(World.logOf(w)) |> Option.map(sourceOf), List.length(World.logOf(capped))))

    @Test
    def testRollbackDropsLaterPosts(): Unit \ {Assert, Fs.FileRead} =
        // 戻るは 1 つ前の発言を出した所へ戻し、その後に入った発言は履歴から消える。
        let res = TestKit.res();
        let first = nextLine(res, begun(res));
        let second = nextLine(res, first);
        let back = settle(res, quiet(() -> WorldLog.rollback(res, second)));
        Assert.assertEq(expected = (placeOf(first), TestKit.feedTexts(first)), (placeOf(back), TestKit.feedTexts(back)))

    @Test
    def testRollbackAtTheFirstLineOnlyNotices(): Unit \ {Assert, Fs.FileRead} =
        // 最初の発言では戻れない（入室の行は戻れる所を持たない。知らせだけ）。
        let res = TestKit.res();
        let w = begun(res);
        let tried = quiet(() -> WorldLog.rollback(res, w));
        Assert.assertEq(expected = (placeOf(w), Some(StoryDoc.labelOf(StoryDoc.Label.NoRollback, res#story))),
                        (placeOf(tried), World.toastOf(res, tried)))

    @Test
    def testJumpFromLogGoesBackToThatLine(): Unit \ {Assert, Fs.FileRead} =
        // バックログの行を選び、確認のウィンドウではいと答えると、その行の場面へ戻り、バックログはその行までになる。
        let res = TestKit.res();
        let w = begun(res) |> nextLine(res) |> nextLine(res) |> nextLine(res);
        let k = 2;
        let target = List.nth(k, World.logOf(w)) |> Option.map(sourceOf);
        let asked = quiet(() -> WorldLog.askJump(k, quiet(() -> WorldLog.openLog(w))));
        let jumped = settle(res, quiet(() -> WorldMenu.answer(res, World.Answer.Yes, asked)));
        Assert.assertEq(expected = (Some(World.Ask.Jump(k)), target, List.length(World.logOf(w)) - k, "Closed"),
                        (World.askOf(asked), Some(World.talkLineOf(jumped)), List.length(World.logOf(jumped)), World.panelName(jumped)))

    // ══ セーブ・ロード ══

    def page1(): Saves.Tab = Saves.Tab.Numbered(1)

    @Test
    def testQuickLoadRebuildsTheFeed(): Unit \ {Assert, Fs.FileRead} =
        // クイックセーブして先へ読んでから Qロードすると、同じ行に戻り、チャットの履歴もセーブした時と同じに作り直される。
        let res = TestKit.res();
        let here = begun(res) |> nextLine(res) |> nextLine(res);
        let saved = quiet(() -> WorldMenu.press(res, World.Button.QuickSave, here));
        let moved = saved |> nextLine(res) |> nextLine(res) |> nextLine(res);
        let asked = quiet(() -> WorldMenu.press(res, World.Button.QuickLoad, moved));
        let loaded = settle(res, quiet(() -> WorldMenu.answer(res, World.Answer.Yes, asked)));
        Assert.assertEq(expected = (Some(World.Ask.QuickLoad), placeOf(here), TestKit.feedTexts(here)),
                        (World.askOf(asked), placeOf(loaded), TestKit.feedTexts(loaded)))

    @Test
    def testLoadingRestoresTheCarriedStage(): Unit \ {Assert, Fs.FileRead} =
        // ニュースの途中でセーブしてタイトルからロードすると、前のノードから持ち越す舞台（画面・テレビの映り・環境音の層）も戻る。
        let res = TestKit.res();
        let atNews = TestKit.openNode(res, "News");
        let saved = quiet(() -> WorldSaves.writeSlot(res, page1(), 0, atNews));
        let loaded = settle(res, quiet(() -> WorldSaves.loadFrom(res, page1(), 0, World.toTitle(saved))));
        let stageOf = (w: World.World) -> { let st = World.stageOf(res, w); (st#screen, st#tv, st#ambience |> List.map(l -> (l#name, l#volume))) };
        Assert.assertEq(expected = (placeOf(atNews), stageOf(atNews)), (placeOf(loaded), stageOf(loaded)))

    @Test
    def testSlotRemembersTheScreenName(): Unit \ {Assert, Fs.FileRead} =
        // データの「場所」は画面の名前（チャットは #ゲーム部屋・テレビはニュース）、日時は起動の時刻 + 実時間。
        let res = TestKit.res();
        let w = { clockBase = 1000i64, realNow = Clock.after(42.5, Clock.zero()) | begun(res) };
        let chat = quiet(() -> WorldSaves.writeSlot(res, page1(), 0, w));
        let news = quiet(() -> WorldSaves.writeSlot(res, page1(), 1, TestKit.openNode(res, "News")));
        let placeAt = (i: Int32, cur: World.World) -> Saves.slotOf(page1(), i, cur#saves) |> Option.map(s -> s#place);
        Assert.assertEq(expected = (Some(StoryDoc.labelOf(StoryDoc.Label.PlaceChat, res#story)), Some(StoryDoc.labelOf(StoryDoc.Label.PlaceNews, res#story)), Some(1042i64)),
                        (placeAt(0, chat), placeAt(1, news), Saves.slotOf(page1(), 0, chat#saves) |> Option.map(s -> s#savedAt)))

    @Test
    def testSavingOverAFilledSlotAsksFirst(): Unit \ {Assert, Fs.FileRead} =
        // 埋まっている枠を選ぶと上書きを尋ね、いいえなら前のデータのまま、はいなら今の所で書き直す。
        let res = TestKit.res();
        let first = begun(res);
        let saved = quiet(() -> WorldSaves.writeSlot(res, page1(), 0, first));
        let later = quiet(() -> WorldSaves.openSave(nextLine(res, saved)));
        let asked = quiet(() -> WorldSaves.withTab(page1(), later) |> (opened -> WorldSaves.chooseSlot(res, 0, opened)));
        let lineIn = (w: World.World) -> Saves.slotOf(page1(), 0, w#saves) |> Option.map(s -> List.length(s#mark#bookmark#steps));
        Assert.assertEq(expected = (Some(World.Ask.Overwrite(page1(), 0)), lineIn(saved), true),
                        (World.askOf(asked), lineIn(quiet(() -> WorldMenu.answer(res, World.Answer.No, asked))),
                         lineIn(quiet(() -> WorldMenu.answer(res, World.Answer.Yes, asked))) != lineIn(saved)))

    @Test
    def testDeletingASlotAsksThenRemovesIt(): Unit \ {Assert, Fs.FileRead} =
        // 削除は尋ねてから消す。
        let res = TestKit.res();
        let saved = quiet(() -> WorldSaves.writeSlot(res, page1(), 1, begun(res)));
        let asked = quiet(() -> WorldSaves.deleteSlot(1, WorldSaves.withTab(page1(), WorldSaves.openSave(saved))));
        let gone = quiet(() -> WorldMenu.answer(res, World.Answer.Yes, asked));
        Assert.assertEq(expected = (Some(World.Ask.Delete(page1(), 1)), false),
                        (World.askOf(asked), Option.nonEmpty(Saves.slotOf(page1(), 1, gone#saves))))

    @Test
    def testContinueLoadsTheNewestSave(): Unit \ {Assert, Fs.FileRead} =
        // タイトルの「つづきから」は、ページを問わずいちばん新しいデータを読む。
        let res = TestKit.res();
        let a = quiet(() -> WorldSaves.writeSlot(res, page1(), 0, begun(res)));
        let b = quiet(() -> WorldSaves.writeSlot(res, Saves.Tab.Numbered(3), 5, { saves = a#saves | TestKit.openNode(res, "News") }));
        let continued = settle(res, quiet(() -> WorldMenu.chooseTitle(res, World.TitleItem.Continue, World.toTitle(b))));
        Assert.assertEq(expected = (Some((Saves.Tab.Numbered(3), 5)), "News"), (Saves.latest(b#saves), World.talkNodeOf(continued)))

    @Test
    def testContinueWithoutSavesOnlyNotices(): Unit \ {Assert, Fs.FileRead} =
        // データが無い時の「つづきから」は知らせだけを出す（タイトルのまま）。
        let res = TestKit.res();
        let w = quiet(() -> WorldMenu.chooseTitle(res, World.TitleItem.Continue, w0(res)));
        Assert.assertEq(expected = ("Title", Some(StoryDoc.labelOf(StoryDoc.Label.NoSave, res#story))),
                        (World.sceneName(w), World.toastOf(res, w)))

    @Test
    def testAutosaveAtEachNewNode(): Unit \ {Assert, Fs.FileRead} =
        // 新しいノードに入って最初の行を出すとオートのページの先頭へ残り、前の物は 1 つ後ろへずれる。
        let res = TestKit.res();
        let atNews = readUntil(res, cur -> World.talkNodeOf(cur) == "News", begun(res));
        let nodeAt = (i: Int32, w: World.World) -> Saves.slotOf(Saves.Tab.Auto, i, w#saves) |> Option.map(s -> s#mark#bookmark#node);
        Assert.assertEq(expected = (Some("News"), Some(Talk.nodeName(Talk.Node.Opening))), (nodeAt(0, atNews), nodeAt(1, atNews)))

    @Test
    def testSaveScreenOnlyWritesNumberedPages(): Unit \ {Assert, Fs.FileRead} =
        // セーブ画面はページ 1〜3 だけを巡り、オートのページを開いていても書かない。
        let res = TestKit.res();
        let opened = quiet(() -> WorldSaves.openSave(begun(res)));
        let cycled = quiet(() -> WorldSaves.moveTab(1, quiet(() -> WorldSaves.moveTab(1, quiet(() -> WorldSaves.moveTab(1, opened))))));
        let tabOf = (cur: World.World) -> World.slotsOf(cur) |> Option.map(fst) |> Option.map(Saves.isWritable);
        Assert.assertEq(expected = (Some(true), Some(true), false),
                        (tabOf(opened), tabOf(cycled), List.exists(t -> not Saves.isWritable(t), WorldSaves.tabsOf(opened))))

    @Test
    def testSavesSurviveJson(): Unit \ {Assert, Fs.FileRead} =
        // セーブデータ（持ち越す舞台つき）・既読・設定は JSON を通しても同じ。
        let res = TestKit.res();
        let atNews = TestKit.openNode(res, "News");
        let tuned = quiet(() -> WorldSettings.withSide(World.Pair.Display, Layout.Side.Right, quiet(() -> WorldSettings.withSide(World.Pair.SkipScope, Layout.Side.Right, atNews))));
        let saves = quiet(() -> WorldSaves.writeSlot(res, page1(), 3, tuned))#saves;
        let back = Saves.fromJson(Saves.fresh(res#kind), Saves.toJson(saves));
        let shape = (whole: Saves.Saves) -> { let s = Saves.rec(whole); (Map.keysOf(s#slots), s#seen, s#serial, s#config#cps, s#config#skipScope, s#config#display,
                                        Map.valuesOf(s#slots) |> List.map(slot -> (slot#savedAt, slot#place, slot#mark#screen, slot#mark#tv,
                                                                                   slot#mark#ambience |> List.map(l -> (l#name, l#volume)), slot#mark#chill, slot#mark#drops, slot#mark#bookmark#node))) };
        Assert.assertEq(expected = shape(saves), shape(back))

    @Test
    def testOldSaveSlotsAreDroppedButSettingsStay(): Unit \ {Assert, Fs.FileRead} =
        // 古い形（version 2）のセーブは枠を捨て、設定は読む（戻れる所の舞台の形が違うので当て直さない）。
        let res = TestKit.res();
        let saves = quiet(() -> WorldSaves.writeSlot(res, page1(), 0, quiet(() -> WorldSettings.withLevel(res, World.Slider.TextSpeed, 90.0, begun(res)))))#saves;
        let old = match Saves.toJson(saves) {
            case Json.JObject(m) => Json.JObject(Map.insert("version", Json.JNumber(JsonCodec.floatToBd(2.0)), m))
            case other           => other
        };
        let back = Saves.fromJson(Saves.fresh(res#kind), old);
        Assert.assertEq(expected = (0, 90.0), (Map.size(Saves.slotsOf(back)), Saves.configOf(back)#cps))

    @Test
    def testDateText(): Unit \ {Assert} =
        // 日時の字: 1970-01-01 からの秒を 年/月/日 時:分 に（うるう年の 2 月末も）。
        Assert.assertEq(expected = ("1970/01/01 00:00", "2024/02/29 23:59", "2026/08/14 19:32"),
                        (Saves.dateText(0i64), Saves.dateText(1709251140i64), Saves.dateText(1786735920i64)))

    @Test
    def testPostClockStartsAtTheDocAndAdvances(): Unit \ {Assert, Fs.FileRead} =
        // 発言の時刻は chat.pace.json の chatClockStart から始まり、minutesPerPost × 番号だけ進む（24 時を回ると 0 時へ）。
        let res = TestKit.res();
        let pace = PaceDoc.Doc.Doc({ chatClockStart = "23:59", minutesPerPost = 1.0 | PaceDoc.rec(res#pace) });
        Assert.assertEq(expected = ("23:59", "00:01"), (PaceDoc.clockText(0, pace), PaceDoc.clockText(2, pace)))

    // ══ 設定 ══

    @Test
    def testSlidersStayInRange(): Unit \ {Assert, Fs.FileRead} =
        // つまみの値は範囲の端で止まる。
        let res = TestKit.res();
        let w = w0(res);
        let pushed = (slider, delta) -> List.range(0, 100) |> List.foldLeft((acc, _) -> quiet(() -> WorldSettings.adjust(res, World.Setting.Slider(slider), delta, acc)), w);
        let levelAt = (slider, cur) -> WorldSettings.levelOf(slider, Saves.configOf(cur#saves));
        let ends = WorldSettings.settings() |> List.filterMap(setting -> match setting {
            case World.Setting.Slider(slider) =>
                let range = WorldSettings.rangeOf(slider, res#kind);
                Some((levelAt(slider, pushed(slider, -1)) == range#min, levelAt(slider, pushed(slider, 1)) == range#max))
            case _ => None
        });
        Assert.assertEq(expected = List.map(_ -> (true, true), ends), ends)

    @Test
    def testHeldPointerDragsTheSlider(): Unit \ {Assert, Fs.FileRead} =
        // 押したまま帯の上を動かすと、クリックの拍が無くても値が付いて動く。帯の左端 → 右端で文字の速さは下限 → 上限（= ノーウェイト）。
        let res = TestKit.res();
        let fit = Layout.Fit.Regular;
        let bar = Layout.settingBar(fit, 0);
        let held = x -> { mouseDown = true, mouseMoved = true, cursor = { x = x, y = bar#position#y + bar#size#y / 2.0 } | App.emptyFrame() };
        let opened = quiet(() -> WorldSettings.openSettings(w0(res)));
        let left = Controls.interact(held(bar#position#x), res, opened);
        let right = Controls.interact(held(bar#position#x + bar#size#x), res, left);
        let cps = cur -> Saves.configOf(cur#saves)#cps;
        let range = kind(res)#cpsSlider;
        Assert.assertEq(expected = (range#min, range#max, true), (cps(left), cps(right), KindDoc.isNoWait(cps(right), res#kind)))

    @Test
    def testNoWaitShowsTheWholeLineAtOnce(): Unit \ {Assert, Fs.FileRead} =
        // 文字の速さが最大（ノーウェイト）なら、発言は出た拍に全部出る（打たない）。
        let res = TestKit.res();
        let fast = quiet(() -> WorldSettings.withLevel(res, World.Slider.TextSpeed, kind(res)#cpsSlider#max, begun(res)));
        let shown = TestKit.stepBy(res, 0.01, advance(res, fast));
        Assert.assertTrue(Page.isDone(World.pageOf(shown)))

    @Test
    def testTextSpeedScalesTheTyping(): Unit \ {Assert, Fs.FileRead} =
        // 設定の文字の速さを既定の 2 倍にすると、発言を打つ速さも 2 倍（同じ時間で 2 倍の字が出る）。
        let res = TestKit.res();
        let typed = (w: World.World) -> Page.visibleCount(World.pageOf(TestKit.stepBy(res, 0.2, advance(res, w))));
        let normal = begun(res);
        let doubled = quiet(() -> WorldSettings.withLevel(res, World.Slider.TextSpeed, kind(res)#cps * 2.0, normal));
        Assert.assertEq(expected = true, typed(doubled) > typed(normal))

    @Test
    def testVolumeSettingsReachTheMixer(): Unit \ {Assert, Fs.FileRead} =
        // 全体の音量を 0 にすると、環境音と効果音のどちらのバスも 0 になる。
        let res = TestKit.res();
        let w = quiet(() -> WorldSettings.withLevel(res, World.Slider.MasterVolume, 0.0, w0(res)));
        let mixer = Controls.mixerOf(res, w);
        let state = AudioMixer.initial();
        Assert.assertEq(expected = (0.0, 0.0), (AudioMixer.busGainOf(mixer, state, "ambience"), AudioMixer.busGainOf(mixer, state, "se")))

    @Test
    def testResetRestoresDefaults(): Unit \ {Assert, Fs.FileRead} =
        // 初期設定に戻すは、尋ねてから novel.kind.json の既定へ戻す。
        let res = TestKit.res();
        let start = w0(res);
        let changed = quiet(() -> WorldSettings.withLevel(res, World.Slider.TextSpeed, 120.0, quiet(() -> WorldSettings.withSide(World.Pair.Display, Layout.Side.Right, start))));
        let reset = quiet(() -> WorldMenu.answer(res, World.Answer.Yes, quiet(() -> WorldSettings.activate(World.Setting.Reset, changed))));
        Assert.assertEq(expected = (kind(res)#cps, false), (Saves.configOf(reset#saves)#cps, WorldSettings.isFullscreen(reset)))

    // ══ 返事の音 ══

    @Test
    def testScriptSoundsAreHeard(): Unit \ {Assert, Fs.FileRead} =
        // 入室は se_join、台本の <<se 名>> は se_<名> の出来事になり、Controls が同じ名前の音を鳴らす。
        let res = TestKit.res();
        let (opened, e0) = Emit.collect(() -> WorldRead.newGame(res, w0(res)));
        let (_, e1) = TestKit.settleHearing(res, opened);
        let (_, e2) = TestKit.readHearing(res, World.isCredits, TestKit.openNode(res, "News"));
        let heard = List.flatten(e0 :: e1 :: e2 :: Nil);
        Assert.assertEq(expected = (true, true, Some("se_thud")),
                        (List.memberOf(World.Event.Cue("se_join"), heard), List.memberOf(World.Event.Cue("se_thud"), heard), Controls.soundOf(World.Event.Cue("se_thud"))))

    @Test
    def testLoadingIsSilent(): Unit \ {Assert, Fs.FileRead} =
        // ロードで読み直す時、通り過ぎた入退室と <<se>> は鳴らさない（返事は Loaded の 1 つだけ）。
        let res = TestKit.res();
        let saved = quiet(() -> WorldSaves.writeSlot(res, Saves.Tab.Numbered(1), 0, nextLine(res, begun(res))));
        let (_, heard) = Emit.collect(() -> WorldSaves.loadFrom(res, Saves.Tab.Numbered(1), 0, saved));
        Assert.assertEq(expected = World.Event.Loaded :: Nil, heard)
}
