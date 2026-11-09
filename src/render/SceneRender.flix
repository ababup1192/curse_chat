// SceneRender — ゲーム画面を画面なしで PNG に描き出す（スナップショット比較用）。
// 実行: make render-all → gallery/*.png と gallery/<場面>.json（場面と World は Shots。none-<場面> は背景なし）
//       make render SHOT=chat → debug/chat.png（1 枚だけ）。small-<場面> は同じ場面を小さい画面（スマホ）の並べ方で描く。
//       portrait-<場面> は縦に持ったスマホ（390×844 → 縦の design 540×1169）、portrait-short-<場面> は太い縦の画面（360×640 → 540×960）で描く。
// 走査線と砂嵐は宣言シェーダーの面なので、draw には渡さず ShaderEval が画素ごとに塗る（Render.shaderSurfaces）。
// 絵は project.json の textures をそのまま読む（実機と同じ名前 → 同じファイル）。字は 2 つ（丸ゴシック = default・明朝 = mincho）。
mod SceneRender {
    use fge::{App, DocJson, Display, FontAtlas, HeadlessFont, HeadlessRender, JsonCodec, ProjectLoader, Render, SoftRaster, Vec2}

    import java.io.File
    import java.lang.ProcessHandle

    pub def design(): Vec2.Vec2 = Layout.size(Layout.Fit.Regular)

    /// 描き出す画面の形: 横（区分 Large か Small）か、画面の大きさ view（CSS px）の縦のスマホ。
    pub enum Look {
        case Landscape(Display.SizeClass)
        case Portrait(Vec2.Vec2)
    }

    /// 縦の画面の design（project.json の web.portraitDesign と画面の大きさ view から。実機のブラウザと同じ決め方）。
    /// 縦の指定が読めなければ 540×960。
    pub def portraitDesignOf(view: Vec2.Vec2): Vec2.Vec2 \ IO =
        let loaded = run { ProjectLoader.loadProject(".") } with Fs.FileRead.runWithIO;
        loaded |> Result.toOption |> Option.flatMap(proj -> ProjectLoader.portraitConfigOf(proj, view))
               |> Option.map(c -> { x = Int32.toFloat64(c#designWidth), y = Int32.toFloat64(c#designHeight) })
               |> Option.getWithDefault({ x = 540.0, y = 960.0 })

    /// look の画面で描く時の描き出しの設定（縦は design と描き出しの大きさを縦の design に）と、ViewCtx に渡す画面の情報。
    pub def lookOf(look: Look, landscape: HeadlessRender.RenderConfig): (HeadlessRender.RenderConfig, Display.Display) \ IO = match look {
        case Look.Landscape(sizeClass) => (landscape, { sizeClass = sizeClass | Display.desktop(design()) })
        case Look.Portrait(view) =>
            let d = portraitDesignOf(view);
            ({ design = d, frameW = Float64.round(d#x) |> Float64.tryToInt32 |> Option.getWithDefault(540),
               frameH = Float64.round(d#y) |> Float64.tryToInt32 |> Option.getWithDefault(960) | landscape },
             Display.phonePortrait(view, d))
    }

    /// チャットアプリの字（project.json の fonts の default）と、地の文と血文字の字（mincho）。
    pub def uiTtf(): String = "assets/MPLUSRounded1c-Bold.subset.ttf"

    pub def minchoTtf(): String = "assets/ShipporiMincho-Regular.subset.ttf"

    /// 描き出しの字の本 2 つ（実機と同じ名前で組む）。
    pub type alias Fonts = { ui = FontAtlas, mincho = FontAtlas }

    pub def fontsOf(): Fonts \ IO =
        { ui = HeadlessFont.buildAtlas("default", uiTtf()), mincho = HeadlessFont.buildAtlas(View.minchoFont(), minchoTtf()) }

    /// 名前 → 字の本（実機の ViewCtx#fontOf と同じ引き方。知らない名前は default）。
    pub def fontOfName(fonts: Fonts): String -> FontAtlas = name -> if (name == View.minchoFont()) fonts#mincho else fonts#ui

    /// SoftRaster が既定の字の外で読む字（明朝）。
    pub def extraFontsOf(fonts: Fonts): Map[String, SoftRaster.FontEntry] =
        Map#{ fonts#mincho#textureName => { ttf = minchoTtf(), atlas = fonts#mincho } }

    /// 字の縁も面の縁もならす（UI と明朝の画面。格子に乗せる絵は無い）。
    pub def cfgOf(outDir: String, fonts: Fonts, textures: Map[String, String]): HeadlessRender.RenderConfig =
        { design = design(), scale = 1, background = { r = 0.0, g = 0.0, b = 0.0 },
          fontTtf = uiTtf(), fontAtlas = fonts#ui, texturePath = textures,
          outDir = outDir, frameW = 960, frameH = 540 | HeadlessRender.defaults() }

    /// project.json の textures（名前 → パス）。読めなければ空（画像の部品は描かれない）。
    pub def texturesOf(): Map[String, String] \ IO =
        let rows = run { DocJson.readJson("project.json") } with Fs.FileRead.runWithIO;
        rows |> Result.toOption |> Option.flatMap(JsonCodec.expectObject)
             |> Option.flatMap(root -> Map.get("textures", root))
             |> Option.flatMap(JsonCodec.decodeList(j -> JsonCodec.expectObject(j) |> Option.map(obj ->
                    (JsonCodec.stringOr("name", "", obj), JsonCodec.stringOr("path", "", obj)))))
             |> Option.getWithDefault(Nil) |> List.toMap

    def loadRes(): Res.Res \ IO = run { Controls.loadRes() } with Fs.FileRead.runWithIO

    pub def all(): Unit \ IO = App.Headless.exitWith(allJob(App.Headless.requestFromProcess()))

    pub def allJob(_req: App.Headless.Request): Int32 \ IO =
        discard allShots();
        0

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。E2e.serveHeadless が束ねる。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.job("SceneRender", "one", req -> oneJob(req)) ::
        App.Headless.job("SceneRender", "all", req -> allJob(req)) :: Nil


    pub def allShots(): List[String] \ IO = shotsInto("gallery", _ -> true)

    /// 渡した World を 1 枚描いて、そのパスを返す（App.onShotRequest。Studio の会話のプレビュー・bin/fge talk shot）。
    pub def shotOf(res: Res.Res, w: World.World): String \ IO =
        discard (new File("debug/shot")).mkdirs();
        let fonts = fontsOf();
        let cfg = cfgOf("debug/shot", fonts, texturesOf());
        shootAs(Look.Landscape(Display.SizeClass.Large), res, cfg, fonts, w, "shot-${ProcessHandle.current().pid()}")

    pub def one(): Unit \ IO = App.Headless.exitWith(oneJob(App.Headless.requestFromProcess()))

    pub def oneJob(req: App.Headless.Request): Int32 \ IO =
        let wanted = Map.getWithDefault("SHOT", "", App.Headless.envOf(req)) |> String.splitOn(substr = " ")
            |> List.map(String.trim) |> List.filter(n -> not String.isEmpty(n));
        let known = List.toSet(allNames());
        let unknown = wanted |> List.filter(n -> not Set.memberOf(n, known));
        if (List.isEmpty(wanted) or not List.isEmpty(unknown)) {
            println("[render] 描けない名前です: ${List.join(" ", unknown)}");
            println("[render] SHOT=<場面> に使えるのは: ${List.join(" ", allNames())}");
            1
        } else {
            let picked = List.toSet(wanted);
            discard shotsInto("debug", n -> Set.memberOf(n, picked));
            0
        }

    /// 小さい画面（スマホ）の並べ方で描く場面: (描き出しの名前, Shots の場面の名前)。World は同じ場面の物をそのまま使う。
    /// WhyNot: Shots.names に入れない — Shots.names は実機の START=shot: の口でもあり、デスクトップ版の実機はいつも Large で描く。
    def smallShots(): List[(String, String)] =
        ("small-title", "title") :: ("small-chat", "chat") :: ("small-thought", "thought")
            :: ("small-save", "save") :: ("small-settings", "settings") :: Nil

    /// 縦の画面で描く場面: (描き出しの名前, 場面の名前, 画面の大きさ)。World は Shots の同じ場面の物をそのまま使う（menu だけは Shots.portraitOnly）。
    /// 太い縦の画面（360×640）は縦の design の下限の高さで、並べ方がいちばん窮屈になる所を見る。
    def portraitShots(): List[(String, String, Vec2.Vec2)] =
        let tall = Display.defaultPortraitView();
        let short = { x = 360.0, y = 640.0 };
        let talls = ("title" :: "chat" :: "chat-kaabo" :: "join" :: "thought" :: "glitch" :: "chill" :: "tv" :: "tv-water" :: "dark" :: "scare" ::
                     "log" :: "save" :: "settings" :: "credits" :: "menu" :: "ask" :: "none-thought" :: Nil)
            |> List.map(scene -> ("portrait-${scene}", scene, tall));
        let shorts = ("title" :: "chat" :: "tv" :: "save" :: "settings" :: "menu" :: Nil)
            |> List.map(scene -> ("portrait-short-${scene}", scene, short));
        List.append(talls, shorts)

    /// 描き出せる名前の全部（Shots の場面と、小さい画面と縦の画面の場面）。
    def allNames(): List[String] =
        List.flatten(Shots.names() :: (smallShots() |> List.map(fst)) :: (portraitShots() |> List.map(match (name, _, _) -> name)) :: Nil)

    def shotsInto(outDir: String, keep: String -> Bool): List[String] \ IO =
        discard (new File(outDir)).mkdirs();
        let fonts = fontsOf();
        let cfg = cfgOf(outDir, fonts, texturesOf());
        let res = loadRes();
        let regular = Shots.names() |> List.map(name -> (name, name, Look.Landscape(Display.SizeClass.Large)));
        let small = smallShots() |> List.map(match (name, scene) -> (name, scene, Look.Landscape(Display.SizeClass.Small)));
        let portrait = portraitShots() |> List.map(match (name, scene, view) -> (name, scene, Look.Portrait(view)));
        List.flatten(regular :: small :: portrait :: Nil) |> List.filter(match (name, _, _) -> keep(name)) |> List.filterMap(match (name, scene, look) ->
            Shots.shotOf(scene, res) |> Option.map(match (shotRes, w) -> {
                let path = shootAs(look, shotRes, cfg, fonts, w, name);
                App.Headless.writeShotRecord(outDir, name, Some(E2e.fingerprint(shotRes, w)));
                path
            }))

    /// 1 場面を look の画面として PNG に描き出し、そのファイルパスを返す。hud の合流は実機と同じ App.composeScene を通し、
    /// シェーダーの面は surfaces として別に取り出して画素ごとに評価させる（draw に渡すと代表色のベタ塗りになる）。
    def shootAs(look: Look, res: Res.Res, landscape: HeadlessRender.RenderConfig, fonts: Fonts, w: World.World, name: String): String \ IO =
        let (cfg, display) = lookOf(look, landscape);
        let ctx = { display = display | App.viewCtxOfFonts(fonts#ui, fontOfName(fonts), cfg#design) };
        let items = App.composeScene(None, 1.0, cfg#design, { world = View.frame(ctx, res, w), hud = View.hud(ctx, res, w) });
        let (drawables, polygons) = Render.draw(Render.withoutShaders(items));
        let path = "${cfg#outDir}/${name}.png";
        let req = { drawables = drawables, polygons = polygons, design = cfg#design, scale = cfg#scale, background = cfg#background,
                    texturePath = cfg#texturePath, fontTtf = cfg#fontTtf, fontAtlas = cfg#fontAtlas, outPath = path,
                    shapeAntialias = cfg#shapeAntialias, textAntialias = cfg#textAntialias, scenes = Nil };
        SoftRaster.renderFull(req, Render.shaderSurfaces(items), extraFontsOf(fonts), Map.empty());
        println("rendered: ${path}");
        path
}
