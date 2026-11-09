// 縦の画面（縦の design で起動した時）の並べ方の当たり・押せる大きさ・画面に収まるかをテストする。
// 当たりの矩形は View が描く所と同じ Layout の関数から引く（座標の数を写さない）。Frame#viewport が縦長なら縦の並べ方になる。
mod TestPortrait {

    use fge::{App, Display}
    use fge::GameEngine.Key
    use TestKit.{begun, w0}

    type alias Box = { position = { x = Float64, y = Float64 }, size = { x = Float64, y = Float64 } }

    /// 縦に持ったスマホ（390×844）の縦の design。
    def tall(): { x = Float64, y = Float64 } = { x = 540.0, y = 1169.0 }

    /// 太い縦の画面（360×640）の縦の design（下限の高さ）。
    def short(): { x = Float64, y = Float64 } = { x = 540.0, y = 960.0 }

    def portrait(res: Res.Res, design: { x = Float64, y = Float64 }): Layout.Fit =
        Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Portrait, design, res#smallScreen, res#portrait)

    def center(r: Box): { x = Float64, y = Float64 } =
        { x = r#position#x + r#size#x / 2.0, y = r#position#y + r#size#y / 2.0 }

    /// 縦の design の画面で p を押した 1 フレーム。
    def press(res: Res.Res, design: { x = Float64, y = Float64 }, p: { x = Float64, y = Float64 }, w: World.World): World.World =
        Controls.interact({ mouseClicked = true, mouseDown = true, cursor = p, viewport = design, sizeClass = Display.SizeClass.Small | App.emptyFrame() }, res, w)

    /// 縦の design の画面でキーを押した 1 フレーム。
    def tap(res: Res.Res, design: { x = Float64, y = Float64 }, key: Key, w: World.World): World.World =
        Controls.interact({ justPressed = Set#{key}, down = Set#{key}, viewport = design | App.emptyFrame() }, res, w)

    /// 上の帯の ≡。
    def menuButton(fit: Layout.Fit): Box = Layout.button(fit, 0, List.length(WorldMenu.buttonsOf(fit)))

    def menuRect(fit: Layout.Fit, item: World.Button): Box =
        let all = WorldMenu.menuItems();
        let i = all |> List.zipWithIndex |> List.find(match (_, b) -> b == item) |> Option.map(fst) |> Option.getWithDefault(0);
        Layout.menuItem(fit, i, List.length(all))

    def opened(res: Res.Res): World.World = press(res, tall(), center(menuButton(portrait(res, tall()))), begun(res))

    def slotCursorOf(w: World.World): Int32 = match w#panel {
        case World.Panel.SaveSlots(_, i) => i
        case World.Panel.LoadSlots(_, i) => i
        case _                           => -1
    }

    /// 縦の画面で押せる物の矩形の全部（≡・メニューの項目・タイトル・確認・戻る・タブ・セーブの枠と削除・設定の行と 2 択）。
    def touchTargets(fit: Layout.Fit): List[Box] =
        let menuCount = List.length(WorldMenu.menuItems());
        let titleCount = List.length(WorldMenu.titleItems());
        let settingCount = List.length(WorldSettings.settings());
        List.flatten(
            (menuButton(fit) :: Layout.back(fit) :: Nil)
            :: (List.range(0, menuCount) |> List.map(i -> Layout.menuItem(fit, i, menuCount)))
            :: (List.range(0, titleCount) |> List.map(i -> Layout.titleItem(fit, i, titleCount)))
            :: (Layout.sides() |> List.map(Layout.askButton(fit)))
            :: (List.range(0, 5) |> List.map(Layout.tab(fit, 5)))
            :: (List.range(0, Saves.perPage()) |> List.flatMap(i -> Layout.slot(fit, i) :: Layout.remove(fit, i) :: Nil))
            :: (List.range(0, settingCount) |> List.flatMap(i -> Layout.settingRow(fit, i) :: (Layout.sides() |> List.map(Layout.settingSide(fit, i)))))
            :: Nil)

    /// 押せる物の短い辺が、画面の幅 width CSS px の端末で何 CSS px になるかの最小。
    def smallestCss(fit: Layout.Fit, width: Float64): Float64 =
        let k = width / Layout.width(fit);
        touchTargets(fit) |> List.map(r -> Float64.min(r#size#x, r#size#y) * k) |> List.minimum |> Option.getWithDefault(0.0)

    def inside(fit: Layout.Fit, r: Box): Bool =
        r#position#x >= 0.0 and r#position#y >= 0.0 and r#position#x + r#size#x <= Layout.width(fit) and r#position#y + r#size#y <= Layout.height(fit)

    // ── 並べ方の組 ──

    @Test
    def testPortraitViewportSelectsPortraitFit(): Unit \ {Assert, Fs.FileRead} =
        // 縦の design なら区分に関わらず縦の並べ方。
        let res = TestKit.res();
        Assert.assertTrue(Layout.isPortrait(Layout.fitOf(Display.SizeClass.Large, Display.Orientation.Portrait, tall(), res#smallScreen, res#portrait)))

    @Test
    def testLandscapeScreenNeverSelectsPortraitFit(): Unit \ {Assert, Fs.FileRead} =
        // 向きが Portrait でも画面が横長なら横の並べ方へ落とす。
        let res = TestKit.res();
        Assert.assertFalse(Layout.isPortrait(Layout.fitOf(Display.SizeClass.Small, Display.Orientation.Portrait, { x = 960.0, y = 540.0 }, res#smallScreen, res#portrait)))

    // ── 押せる大きさ・画面に収まる ──

    @Test
    def testTouchTargetsAreAtLeast44CssPxOnNarrowPhone(): Unit \ {Assert, Fs.FileRead} =
        // 360 CSS px 幅の縦の画面（太い方・高い方とも）で、押せる物はどれも 44 CSS px 以上。
        let res = TestKit.res();
        Assert.assertTrue(smallestCss(portrait(res, short()), 360.0) >= 43.99 and smallestCss(portrait(res, tall()), 360.0) >= 43.99)

    @Test
    def testTouchTargetsStayInsideTheShortScreen(): Unit \ {Assert, Fs.FileRead} =
        // 太い縦の画面でも、押せる物は画面の中に収まる。
        let fit = portrait(TestKit.res(), short());
        Assert.assertTrue(touchTargets(fit) |> List.forAll(inside(fit)))

    @Test
    def testTextAreasStayInsideTheShortScreen(): Unit \ {Assert, Fs.FileRead} =
        // 字を出す範囲（発言の列・入力欄・テレビの映りと字幕・バックログ・見本・メニュー）が、太い縦の画面の中に収まる。
        let fit = portrait(TestKit.res(), short());
        let areas = Layout.feed(fit) :: Layout.input(fit) :: Layout.tvPicture(fit) :: Layout.captionBand(fit) :: Layout.logView(fit)
                    :: Layout.preview(fit) :: Layout.menuBox(fit, List.length(WorldMenu.menuItems())) :: Layout.askBox(fit) :: Nil;
        Assert.assertTrue(areas |> List.forAll(inside(fit)))

    @Test
    def testChatTextColumnEndsInsideTheScreen(): Unit \ {Assert, Fs.FileRead} =
        // 発言の本文の折り返す列の右端・地の文の帯・字幕の字の右端が、縦の画面の幅の中にある。
        let fit = portrait(TestKit.res(), tall());
        let w = Layout.width(fit);
        let caption = Layout.captionText(fit);
        Assert.assertTrue(Layout.feedTextLeft(fit) + Layout.feedTextWidth(fit) <= w and Layout.thoughtWidth(fit) < w and caption#x + caption#width <= w)

    @Test
    def testFeedEndsAboveTheInputAndTheHomeBar(): Unit \ {Assert, Fs.FileRead} =
        // 発言の列の下端は入力欄の上、入力欄の下端はホームバーの余白（novel.portrait.json の homeBarGap）の上。
        let res = TestKit.res();
        let fit = portrait(res, short());
        let feed = Layout.feed(fit);
        let input = Layout.input(fit);
        Assert.assertTrue(feed#position#y + feed#size#y <= input#position#y
                          and input#position#y + input#size#y <= Layout.height(fit) - PortraitDoc.rec(res#portrait)#homeBarGap)

    // ── 当たり ──

    @Test
    def testMenuButtonOpensTheMenu(): Unit \ {Assert, Fs.FileRead} =
        // 縦の画面の上の帯の ≡ を押すと、≡ のメニューが開く。
        Assert.assertEq(expected = "Menu", World.panelName(opened(TestKit.res())))

    @Test
    def testMenuLogItemOpensTheLog(): Unit \ {Assert, Fs.FileRead} =
        // ≡ のメニューの「ログ」を押すとバックログが開く。
        let res = TestKit.res();
        let w = press(res, tall(), center(menuRect(portrait(res, tall()), World.Button.Log)), opened(res));
        Assert.assertEq(expected = "Log", World.panelName(w))

    @Test
    def testMenuAutoItemStartsAutoAndCloses(): Unit \ {Assert, Fs.FileRead} =
        // ≡ のメニューの「オート」でメニューが閉じてオートになる。
        let res = TestKit.res();
        let w = press(res, tall(), center(menuRect(portrait(res, tall()), World.Button.Auto)), opened(res));
        Assert.assertEq(expected = ("Closed", World.Playback.Auto), (World.panelName(w), World.playbackOf(w)))

    @Test
    def testTapOutsideMenuClosesIt(): Unit \ {Assert, Fs.FileRead} =
        // メニューの外（発言の列の左下）を押すとメニューが閉じる。
        let res = TestKit.res();
        let feed = Layout.feed(portrait(res, tall()));
        Assert.assertEq(expected = "Closed", World.panelName(press(res, tall(), { x = 20.0, y = feed#position#y + feed#size#y - 10.0 }, opened(res))))

    @Test
    def testLandscapeHasNoMenuButton(): Unit \ Assert =
        // 横の画面の帯には ≡ を出さない（ボタンは今の並びのまま）。
        Assert.assertEq(expected = WorldMenu.buttons(), WorldMenu.buttonsOf(Layout.Fit.Regular))

    @Test
    def testPortraitDownKeyMovesOneSlot(): Unit \ {Assert, Fs.FileRead} =
        // 縦の画面のセーブの枠は 1 列なので、下のキーで 1 枠動く。
        let res = TestKit.res();
        let save = press(res, tall(), center(menuRect(portrait(res, tall()), World.Button.Save)), opened(res));
        let down = KeysDoc.rec(res#keys)#next |> List.head |> Option.getWithDefault(Key.Down);
        Assert.assertEq(expected = 1, slotCursorOf(tap(res, tall(), down, save)))

    @Test
    def testPortraitTitleSettingsItemOpensSettings(): Unit \ {Assert, Fs.FileRead} =
        // 太い縦の画面のタイトルの「設定」の真ん中を押すと設定が開く。
        let res = TestKit.res();
        let fit = portrait(res, short());
        let all = WorldMenu.titleItems();
        let i = all |> List.zipWithIndex |> List.find(match (_, it) -> it == World.TitleItem.Settings) |> Option.map(fst) |> Option.getWithDefault(0);
        let w = press(res, short(), center(Layout.titleItem(fit, i, List.length(all))), w0(res));
        Assert.assertEq(expected = "Settings", World.panelName(w))

    // ── 行頭の禁則 ──

    @Test
    def testLeadingCommaPullsThePreviousCharDown(): Unit \ Assert =
        // 読点で始まる行は、前の行の最後の字ごと次の行へ送る（字の数の合計は変えない）。
        Assert.assertEq(expected = "あい" :: "う、えお" :: Nil, View.pushOutLeadingMarks("あいう" :: "、えお" :: Nil))

    @Test
    def testLeadingSmallKanaPullsThePreviousCharDown(): Unit \ Assert =
        // 小書きの字で始まる行も同じく送る。
        Assert.assertEq(expected = "あい" :: "うっえ" :: Nil, View.pushOutLeadingMarks("あいう" :: "っえ" :: Nil))
}
