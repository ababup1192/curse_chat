// JSON とコードの橋渡しだけをテストする: コードが名前で引く物（画像・音・言葉の鍵・語彙）が Doc と素材の側に揃っているか。
mod TestDocs {

    use fge::{DocJson, JsonCodec, ProjectLoader, Yarn}

    /// project.json の配列 key の各要素の name。
    def namesIn(key: String): Set[String] \ Fs.FileRead =
        DocJson.readJson("project.json") |> Result.toOption |> Option.flatMap(JsonCodec.expectObject)
            |> Option.flatMap(root -> Map.get(key, root))
            |> Option.flatMap(JsonCodec.decodeList(j -> JsonCodec.expectObject(j) |> Option.map(obj -> JsonCodec.stringOr("name", "", obj))))
            |> Option.getWithDefault(Nil) |> List.toSet

    def commandArgs(name: String, program: Yarn.Program): List[List[String]] =
        def walk(body: List[Yarn.Statement]): List[Yarn.Command] = body |> List.flatMap(statement -> match statement {
            case Yarn.Statement.Command(c)      => c :: Nil
            case Yarn.Statement.Choose(cs)      => cs |> List.flatMap(choice -> walk(choice#body))
            case Yarn.Statement.If(branches, _) => branches |> List.flatMap(b -> walk(b#body))
            case _                              => Nil
        });
        Yarn.nodeNames(program) |> List.filterMap(n -> Yarn.nodeOf(n, program)) |> List.flatMap(node -> walk(node#body))
            |> List.filter(c -> c#name == name) |> List.map(c -> c#args)

    @Test
    def testProjectJsonLoads(): Unit \ {Assert, Fs.FileRead} =
        // project.json は実機の起動と同じ読み手で読める（欠けた欄があるとウィンドウが開く前に止まる）。
        let loaded = ProjectLoader.loadProject(".") |> Result.map(_ -> ());
        Assert.assertEq(expected = Ok(()), loaded)

    @Test
    def testEveryArtPartHasATexture(): Unit \ {Assert, Fs.FileRead} =
        // 画像を貼る部品は、どれも project.json の textures に名前がある（描き出しと実機が同じ名前で読む）。
        let textures = namesIn("textures");
        let missing = Art.parts() |> List.map(Art.textureOf) |> List.filter(t -> not Set.memberOf(t, textures));
        Assert.assertEq(expected = Nil, missing)

    @Test
    def testProjectHasTheMinchoFont(): Unit \ {Assert, Fs.FileRead} =
        // 地の文と血文字の字（View.minchoFont）と、既定の字が project.json の fonts にある（無いと明朝の字が黙って既定の字になる）。
        let fonts = namesIn("fonts");
        Assert.assertEq(expected = (true, true), (Set.memberOf(View.minchoFont(), fonts), Set.memberOf("default", fonts)))

    @Test
    def testEverySoundTheGameCanPlayIsRegistered(): Unit \ {Assert, Fs.FileRead} =
        // 返事の音・ポコッ・入退室・台本の <<se>> と <<ambience>>・タイトルの環境音は、どれも project.json の sounds にある。
        let res = TestKit.res();
        let sounds = namesIn("sounds");
        let replies = World.Event.Paged :: World.Event.Revealed :: World.Event.Posted :: World.Event.Moved ::
                      World.Event.Opened :: World.Event.Closed :: World.Event.Saved :: World.Event.Loaded :: World.Event.Rolled ::
                      World.Event.Cue("se_join") :: World.Event.Cue("se_leave") :: Nil;
        let ses = commandArgs("se", res#dialogue) |> List.filterMap(List.head) |> List.map(n -> World.Event.Cue("se_${n}"));
        let played = List.append(replies, ses) |> List.filterMap(Controls.soundOf);
        let ambiences = (StoryDoc.rec(res#story)#titleAmbience :: (commandArgs("ambience", res#dialogue) |> List.filterMap(List.head)))
            |> List.map(Stage.ambienceSound);
        let missing = List.append(played, ambiences) |> List.filter(n -> not Set.memberOf(n, sounds)) |> List.distinct;
        Assert.assertEq(expected = Nil, missing)

    @Test
    def testStoryDocHasEveryLabel(): Unit \ {Assert, Fs.FileRead} =
        // novel.story.json に、画面に出す言葉の鍵が全部ある（無ければ既定の言葉で出るが、Doc で直せない言葉が残る）。
        let res = TestKit.res();
        let missing = StoryDoc.labels() |> List.map(StoryDoc.labelKey)
            |> List.filter(key -> not Map.memberOf(key, StoryDoc.rec(res#story)#labels));
        Assert.assertEq(expected = Nil, missing)

    @Test
    def testEverySpeakerHasAName(): Unit \ {Assert, Fs.FileRead} =
        // 話し手の id（Talk.Speaker）は、どれも novel.story.json の names に呼び名がある。
        let res = TestKit.res();
        let missing = Talk.speakers() |> List.map(Talk.speakerId)
            |> List.filter(id -> not Map.memberOf(id, StoryDoc.rec(res#story)#names));
        Assert.assertEq(expected = Nil, missing)

    @Test
    def testVocabFileMatchesTalk(): Unit \ {Assert, Fs.FileRead} =
        // assets/talk/vocab.json（yarn build の検査の元）は、コードの語彙（Talk.vocabOf）を書いた物と同じ（make talk-vocab で書き直す）。
        let onDisk = Fs.FileRead.read(Talk.vocabPath()) |> Result.toOption |> Option.map(String.trim);
        Assert.assertEq(expected = Some(String.trim(Yarn.vocabJson(Talk.vocabOf()))), onDisk)

    @Test
    def testOpeningNodeExists(): Unit \ {Assert, Fs.FileRead} =
        // コードが開くノードが、build したシナリオにある。
        let res = TestKit.res();
        Assert.assertEq(expected = true, Option.nonEmpty(Yarn.nodeOf(Talk.nodeName(Talk.Node.Opening), res#dialogue)))

    // ── 絵（chat.art.json）──

    @Test
    def testBrokenArtDocFallsBackToRoom(): Unit \ Assert =
        // chat.art.json が壊れている時は defaults（部屋の絵）。
        let backdropOf = (text: String) -> Art.fromJson(text) |> Option.getWithDefault(Art.defaults()) |> Art.backdropOf;
        Assert.assertEq(expected = Art.Backdrop.Room, backdropOf("{ broken"))

    @Test
    def testOldArtDocWithVariantStillReadsBackdrop(): Unit \ Assert =
        // 古い JSON に variant 欄が残っていても読めて、backdrop はそのまま効く。
        Assert.assertEq(expected = Some(Art.Backdrop.Bare),
                        Art.fromJson("{\"version\": 1, \"variant\": \"engine\", \"backdrop\": \"none\"}") |> Option.map(Art.backdropOf))

    @Test
    def testArtDocBackdropDefaultsToRoom(): Unit \ Assert =
        // backdrop を書かない・知らない綴りなら部屋の絵（room）、none と書けば背景なし。
        let backdropOf = (text: String) -> Art.fromJson(text) |> Option.map(Art.backdropOf);
        Assert.assertEq(expected = (Some(Art.Backdrop.Room), Some(Art.Backdrop.Room), Some(Art.Backdrop.Bare)),
                        (backdropOf("{\"version\": 2}"), backdropOf("{\"backdrop\": \"fog\"}"), backdropOf("{\"backdrop\": \"none\"}")))

    @Test
    def testPartFallsBackToShapesWhenTextureMissing(): Unit \ Assert =
        // 画像がまだ届いていない部品はその部品だけ図形で描く（None）。届いている部品は画像を貼る。
        let missing = Set#{Art.textureOf(Art.Part.Tv)};
        Assert.assertEq(expected = (None, Some(Art.textureOf(Art.Part.Room))),
                        (Art.imageOf(missing, Art.Part.Tv), Art.imageOf(missing, Art.Part.Room)))

    // ── チャットの流れ（chat.pace.json）──

    @Test
    def testBrokenPaceDocFallsBackToDefaults(): Unit \ Assert =
        // chat.pace.json が壊れている時は既定の流れの数で起動する。
        Assert.assertEq(expected = None, PaceDoc.fromJson("{ broken") |> Option.map(d -> PaceDoc.rec(d)#feedMax))

    @Test
    def testPaceDocOverridesOneField(): Unit \ Assert =
        // 1 欄だけ書いた chat.pace.json はその欄だけが替わり、ほかは既定のまま。
        let d = PaceDoc.fromJson("{\"version\": 1, \"gapBase\": 2.0}") |> Option.map(PaceDoc.rec);
        let base = PaceDoc.rec(PaceDoc.defaults());
        Assert.assertEq(expected = Some((2.0, base#feedMax)), d |> Option.map(r -> (r#gapBase, r#feedMax)))

    @Test
    def testShotAnchorsPointAtSaidLines(): Unit \ {Assert, Fs.FileRead} =
        // 描き出しの場面が進める先の行（Shots.anchors のノードと .yarn の行番号）は、どれもそのノードの台詞の行を指している。
        let program = TestKit.res()#dialogue;
        let saidLines = (node: String) -> Yarn.nodeOf(node, program) |> Option.map(found -> found#body |> List.filterMap(statement -> match statement {
            case Yarn.Statement.Say(say) => Some(say#source#line)
            case _                       => None
        })) |> Option.getWithDefault(Nil) |> List.toSet;
        let broken = Shots.anchors() |> Map.toList |> List.filter(match (_, (node, line)) -> not Set.memberOf(line, saidLines(node))) |> List.map(fst);
        Assert.assertEq(expected = Nil, broken)

    @Test
    def testPortraitDocStartsFromTheDefaults(): Unit \ {Assert, Fs.FileRead} =
        // novel.portrait.json は読めて、最初と最後の欄（帯の高さ・クレジットの出典の字）がコードの既定値と同じ値から出発している。
        let readable = DocJson.readJson(PortraitDoc.path()) |> Result.isOk;
        let pick = (r: PortraitDoc.Rec) -> (r#headerHeight, r#creditsSmallSize);
        Assert.assertEq(expected = (true, pick(PortraitDoc.rec(PortraitDoc.defaults()))), (readable, pick(PortraitDoc.rec(PortraitDoc.load(PortraitDoc.path())))))
}
