// 素材の待ち（ブラウザ版で後回しにした環境音が、使う時にまだ届いていない間の暗転）と、届いた絵を登録する予算の決まり。
// 届いていない名前は Res の missing（実機は Game.withAssetLoading が downloads#missing() から写す）を外から決めて流す。
// 音の名前は Stage.ambienceSound から引き、秒は novel.kind.json から引く。
mod TestHold {

    use fge::{App, Clock, LoadProgress, Resources}
    use TestKit.{advance, begun, quiet, readUntil, settle, stepBy}

    def kind(res: Res.Res): KindDoc.Rec = KindDoc.rec(res#kind)

    /// names がまだ届いていない描く元。
    def missingOf(names: List[String], res: Res.Res): Res.Res = Res.withMissing(List.toSet(names), res)

    /// 水の環境音の名前（チャットの途中で足す層）。
    def water(): String = Stage.ambienceSound("water")

    /// 今の舞台の環境音の層の名前。
    def layersOf(w: World.World): List[String] =
        World.readOf(w) |> Option.map(r -> r#stage#ambience |> List.map(l -> l#name)) |> Option.getWithDefault(Nil)

    def hasWater(w: World.World): Bool = List.memberOf("water", layersOf(w))

    /// 全部届いている描く元で、押せば水の環境音を足す所（その手前の行を出し終えた所）。
    def beforeWater(res: Res.Res): World.World =
        readUntil(res, cur -> hasWater(advance(res, cur)), begun(res))

    def storyNow(w: World.World): Float64 = Clock.secondsOf(World.now(w))

    def gaveUpOf(w: World.World): Set[String] = World.readOf(w) |> Option.map(r -> r#gaveUp) |> Option.getWithDefault(Set.empty())

    /// 水の環境音が届いていない描く元で押し、黒へ重ね切った所（Waiting）。
    def waitingForWater(res: Res.Res): World.World =
        let held = missingOf(water() :: Nil, res);
        advance(held, beforeWater(res)) |> stepBy(held, kind(res)#holdFadeSeconds + 0.01)

    /// dt 秒ずつ系を回し、until が真になった所（fuel で必ず止まる）。
    def stepsUntil(res: Res.Res, dt: Float64, until: World.World -> Bool, w: World.World): World.World =
        def go(fuel: Int32, cur: World.World): World.World =
            if (fuel <= 0 or until(cur)) cur else go(fuel - 1, stepBy(res, dt, cur));
        go(2000, w)

    /// 偽の downloads: missing は Ref から引き、受けた予算を Ref に溜める。ほかは全部届いた機種と同じ。
    type alias Fake = {
        downloads = LoadProgress.AssetDownloads,
        missing = Ref[Set[String], Static],
        budgets = Ref[List[LoadProgress.DecodeBudget], Static]
    }

    def fakeOf(missing: Set[String]): Fake \ IO =
        let missingNow = Ref.fresh(Static, missing);
        let budgets = Ref.fresh(Static, Nil);
        let local = LoadProgress.localDownloads();
        { downloads = { missing = () -> Ref.get(missingNow),
                        setBudget = budget -> Ref.put(budget :: Ref.get(budgets), budgets) | local },
          missing = missingNow, budgets = budgets }

    // ══ 全部届いている ══

    @Test
    def testAllArrivedReadsToTheEndWithoutHolding(): Unit \ {Assert, Fs.FileRead} =
        // 全部届いていれば（デスクトップ・描き出し・テストの既定）、一度も待たずにクレジットまで読み切る。
        let res = TestKit.res();
        let w = readUntil(res, World.isHolding, begun(res));
        Assert.assertEq(expected = (true, false), (World.isCredits(w), World.isHolding(w)))

    // ══ 未着の環境音を足す ══

    @Test
    def testUnarrivedAmbienceHoldsBeforeTheCue(): Unit \ {Assert, Fs.FileRead} =
        // 届いていない環境音を足す所で押すと、黒へ重ね始め（FadingOut）、層も行も前のまま（足すのは届いてから）。
        let res = TestKit.res();
        let before = beforeWater(res);
        let w = advance(missingOf(water() :: Nil, res), before);
        Assert.assertEq(expected = (Some(World.HoldPhase.FadingOut), layersOf(before), World.talkLineOf(before)),
                        (World.holdPhaseOf(w), layersOf(w), World.talkLineOf(w)))

    @Test
    def testHoldStopsTheStoryClockOnlyOnceDark(): Unit \ {Assert, Fs.FileRead} =
        // 黒へ重ねる間（holdFadeSeconds）は物語の時計が動き、重ね切ったら Waiting で止まる（1 秒回しても進まない）。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let fading = advance(held, beforeWater(res));
        let dark = stepBy(held, kind(res)#holdFadeSeconds + 0.01, fading);
        let later = stepBy(held, 1.0, dark);
        Assert.assertEq(expected = (Some(World.HoldPhase.Waiting), true, storyNow(dark)),
                        (World.holdPhaseOf(dark), storyNow(dark) > storyNow(fading), storyNow(later)))

    @Test
    def testHoldIgnoresAdvanceAndAuto(): Unit \ {Assert, Fs.FileRead} =
        // 待つ間は押しても動かず、オートも送らない（物語の時計が止まり、実行器も進めない）。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let dark = TestKit.playing(World.Playback.Auto, waitingForWater(res));
        let w = advance(held, dark) |> stepBy(held, 5.0);
        Assert.assertEq(expected = (Some(World.HoldPhase.Waiting), World.talkLineOf(dark), World.Playback.Auto),
                        (World.holdPhaseOf(w), World.talkLineOf(w), World.playbackOf(w)))

    @Test
    def testArrivalFromTheDownloadsResumesTheCue(): Unit \ {Assert, Fs.FileRead, IO} =
        // 実機と同じ繋ぎ（Game.withAssetLoading と偽の downloads）: 黒のまま待つ間の予算は Covered、
        // 音が届くと次のコマで missing が空になり、黒から戻し始め（FadingIn）、預けていた層が足される。
        let res = TestKit.res();
        let fake = fakeOf(Set#{water()});
        let app = Game.withAssetLoading(fake#downloads, TestKit.app(res, TestKit.w0(res)));
        let dark = Resources.of(missingOf(water() :: Nil, res), waitingForWater(res)) |> App.stepBackgroundLoad(app);
        let budget = List.head(Ref.get(fake#budgets));
        Ref.put(Set.empty(), fake#missing);
        let arrived = App.stepBackgroundLoad(app, dark);
        let w = stepBy(arrived#resources, 1.0 / 60.0, arrived#world);
        Assert.assertEq(expected = (Some(LoadProgress.DecodeBudget.Covered(50.0)), Set.empty(), Some(World.HoldPhase.FadingIn), true),
                        (budget, arrived#resources#missing, World.holdPhaseOf(w), hasWater(w)))

    @Test
    def testFadingInEndsTheHold(): Unit \ {Assert, Fs.FileRead} =
        // 届いた後、黒から戻し切ると（holdFadeSeconds）待ちが消える。
        let res = TestKit.res();
        let resumed = stepBy(res, 1.0 / 60.0, waitingForWater(res));
        let w = stepBy(res, kind(res)#holdFadeSeconds + 0.01, resumed);
        Assert.assertEq(expected = (Some(World.HoldPhase.FadingIn), false), (World.holdPhaseOf(resumed), World.isHolding(w)))

    @Test
    def testHoldGivesUpAfterTheLimit(): Unit \ {Assert, Fs.FileRead} =
        // 黒のまま holdGiveUpSeconds 待っても届かなければ、その音を諦めて（gaveUp）層は足したまま黒から戻す。諦める 1 秒前はまだ待っている。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let almost = stepBy(held, kind(res)#holdGiveUpSeconds - 1.0, waitingForWater(res));
        let w = stepBy(held, 1.01, almost);
        Assert.assertEq(expected = (Some(World.HoldPhase.Waiting), Some(World.HoldPhase.FadingIn), true, true),
                        (World.holdPhaseOf(almost), World.holdPhaseOf(w), hasWater(w), Set.memberOf(water(), gaveUpOf(w))))

    @Test
    def testGaveUpSoundIsNotWaitedForAgain(): Unit \ {Assert, Fs.FileRead} =
        // 諦めた音は、黒から戻した後も待ち直さない（届かないまま読み進める）。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let w = stepBy(held, kind(res)#holdGiveUpSeconds + 0.01, waitingForWater(res))
            |> stepBy(held, kind(res)#holdFadeSeconds + 0.01) |> stepBy(held, 1.0 / 60.0);
        Assert.assertEq(expected = false, World.isHolding(w))

    // ══ 一発の効果音 ══

    @Test
    def testUnarrivedSeIsSkippedSilently(): Unit \ {Assert, Fs.FileRead} =
        // 一発の効果音（<<se drip>>）は届いていなくても待たずに読み進め、鳴らす音からは外す（届いていれば鳴る）。
        let res = TestKit.res();
        let drip = "se_drip";
        let held = missingOf(drip :: Nil, res);
        let (w, heard) = TestKit.readHearing(held, cur -> World.talkNodeOf(cur) == "News", beforeWater(res));
        Assert.assertEq(expected = ("News", false, true),
                        (World.talkNodeOf(w), List.memberOf(drip, Controls.soundsOf(Set#{drip}, heard)), List.memberOf(drip, Controls.soundsOf(Set.empty(), heard))))

    // ══ スキップ・ロード・タイトル ══

    @Test
    def testSkipPassesTheCueAndHoldsWhereItStops(): Unit \ {Assert, Fs.FileRead} =
        // スキップ中（設定で未読も飛ばす）は届いていない音の層を足しても待たずに進み、人がスキップを止めた所で待ちに入る（続きは無い）。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let everything = quiet(() -> WorldSettings.withSide(World.Pair.SkipScope, Layout.Side.Right, beforeWater(res)));
        let skipping = quiet(() -> WorldRead.togglePlayback(World.Playback.Skip, everything));
        let passed = stepsUntil(held, 0.1, hasWater, skipping);
        let stopped = stepBy(held, 1.0 / 60.0, quiet(() -> WorldRead.togglePlayback(World.Playback.Skip, passed)));
        Assert.assertEq(expected = (false, Some(World.HoldPhase.FadingOut), Some(0)),
                        (World.isHolding(passed), World.holdPhaseOf(stopped),
                         World.readOf(stopped) |> Option.flatMap(r -> r#hold) |> Option.map(h -> List.length(h#rest))))

    @Test
    def testLoadingIntoAnUnarrivedPlaceHolds(): Unit \ {Assert, Fs.FileRead} =
        // タイトルからロードで戻った所の環境音が届いていなければ、次のコマで待ちに入る。
        // 同じ所のサムネ（screenOf）は待ちを持たない（パネルの絵は止まらない）。
        let res = TestKit.res();
        let held = missingOf(water() :: Nil, res);
        let atWater = settle(res, advance(res, beforeWater(res)));
        let mark = WorldRead.slotHere(res, atWater) |> Option.map(slot -> slot#mark);
        let loaded = mark |> Option.map(m -> quiet(() -> WorldRead.restore(held, m, World.toTitle(atWater))) |> stepBy(held, 1.0 / 60.0));
        let thumb = mark |> Option.map(m -> World.isHolding(WorldRead.screenOf(held, m, atWater)));
        Assert.assertEq(expected = (Some(Some(World.HoldPhase.FadingOut)), Some(false)),
                        (loaded |> Option.map(World.holdPhaseOf), thumb))

    @Test
    def testToTitleDropsTheHold(): Unit \ {Assert, Fs.FileRead} =
        // タイトルへ戻ると待ちは消える（タイトルの音は後回しにしない決まりなので、タイトルでは待たない）。
        let res = TestKit.res();
        Assert.assertEq(expected = false, World.isHolding(World.toTitle(waitingForWater(res))))

    // ══ 届いた絵を登録する予算 ══

    @Test
    def testDecodeBudgetFollowsWhatIsOnScreen(): Unit \ {Assert, Fs.FileRead} =
        // タイトルと出し終えた後は Idle(4)（1 コマに 1 本と 4 ms）・打っている途中は Paused・待つ間は Covered(50)・クレジットは Paused。
        let res = TestKit.res();
        let budgetOf = (w: World.World) -> Controls.decodeBudget(Resources.of(res, w));
        let posted = begun(res);
        let typing = advance(res, posted) |> stepBy(res, 0.01);
        Assert.assertEq(expected = LoadProgress.DecodeBudget.Idle(4.0) :: LoadProgress.DecodeBudget.Idle(4.0) :: LoadProgress.DecodeBudget.Paused ::
                                   LoadProgress.DecodeBudget.Covered(50.0) :: LoadProgress.DecodeBudget.Paused :: Nil,
                        budgetOf(TestKit.w0(res)) :: budgetOf(posted) :: budgetOf(typing) :: budgetOf(waitingForWater(res)) ::
                        budgetOf(World.toCredits(res, posted)) :: Nil)
}
