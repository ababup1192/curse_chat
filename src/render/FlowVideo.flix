// FlowVideo — e2e/<名前>.flow を実機と同じ 1 フレーム（Flow.play）で流し、動画のコマと音に描き出す。
// 実行: make video FLOW=e2e/showcase.flow → debug/video/showcase.mp4（mp4 に束ねるのは Makefile の ffmpeg）
//       PORTRAIT=1（または =390x844 の画面の大きさ CSS px）を渡すと、縦に持ったスマホの縦の design で流して撮る
//       （make showcase-portrait-video。Frame#viewport が縦長になるので、入力の当たりも縦の並べ方）。
//
// 書く物（FLOW_OUT。既定は debug/video/<名前>）:
//   f0000.png …（SoftRaster）か frames.mkv（GPU）・drawhash.txt・frames.json … エンジンの VideoOut が書く
//   audio.f64 … 左右 2 本の 44.1kHz の音（64bit 浮動小数・ビッグエンディアン・左右交互）。
//               実機と同じミキサー（Controls.mixerOf）で、そのフレームに鳴った音と鳴り続ける環境音を AudioMixdown が混ぜる。
//   fps.txt   … コマの速さ（flow の fps）
mod FlowVideo {
    use fge::{App, AudioMixdown, Display, DocJson, Flow, FontAtlas, HeadlessRender, JsonCodec, Render, Resources, Vec2, VideoOut}

    import java.io.BufferedOutputStream
    import java.io.DataOutputStream
    import java.io.File
    import java.io.FileOutputStream
    import java.io.FileWriter

    /// App の w（描く元と World の組）。
    type alias AppState = Resources.With[Res.Res, World.World]

    pub def play(): Unit \ IO = App.Headless.exitWith(playJob(App.Headless.requestFromProcess()))

    /// 常駐（App.Headless.serveJobs）が /run で流す入口の束。E2e.serveHeadless が束ねる。
    pub def jobs(): List[App.Headless.Job] =
        App.Headless.videoJob("FlowVideo", "play", req -> playJob(req)) :: Nil

    /// 終了コード: 0 = 撮れた・1 = flow が途中で止まった（そこまでは書く）・2 = flow を読めない。
    pub def playJob(req: App.Headless.Request): Int32 \ IO =
        let env = App.Headless.envOf(req);
        // WhyNot: 設定を字の用意より後に作らない —— GPU で塗る回は AWT より先に GL へ繋ぐ必要がある（VideoOut.settingsOf）。
        let settings = VideoOut.settingsOf(env);
        let path = Map.getWithDefault("FLOW", "", env);
        let out = Map.getWithDefault("FLOW_OUT", "debug/video/${nameOf(path)}", env);
        let look = lookOf(Map.getWithDefault("PORTRAIT", "", env));
        let landscape = SceneRender.cfgOf(out, SceneRender.fontsOf(), SceneRender.texturesOf());
        let (cfg, display) = SceneRender.lookOf(look, landscape);
        let played = run {
            let app = appOf();
            let design = cfg#design;
            let fresh = App.freshWorld(app, design);
            match Flow.Parse.parseFile(Flow.vocabOf(app, fresh), path, Flow.Cli.readText) {
                case Err(problems) => Err(Flow.Parse.problemsText(problems))
                case Ok(script)    =>
                    let start = { world = Flow.Cli.startWorld(app, design, fresh, script), state = App.freshStepState() };
                    Ok((script#fps, Flow.play(app, { design = design, limit = frameCap() }, script, start)))
            }
        } with Fs.FileRead.runWithIO;
        match played {
            case Err(why) => println("FAIL ${path} を読めない\n${why}"); 2
            case Ok((fps, Ok(outcome))) =>
                write(settings, fps, out, cfg, display, outcome);
                println("rendered: ${out} (${Int32.toString(List.length(outcome#frames))} frames)");
                0
            case Ok((fps, Err(failure))) =>
                write(settings, fps, out, cfg, display, failure#upTo);
                println("FAIL ${failure#at#file}:${Int32.toString(failure#at#number)}: ${failure#why}");
                println("    ${failure#at#text}");
                1
        }

    /// e2e と同じ App で、セーブの日時だけ描き出しと同じ「起動した時刻」に据える（e2e の 0 のままだと 1970/01/01 と出る）。
    def appOf(): App.App[AppState, {}] \ Fs.FileRead =
        let res = Controls.loadRes();
        Game.app(res, Saves.fresh(res#kind), Shots.clockBase())

    /// PORTRAIT の値 → 撮る画面の形。空は横（Large）、1 は縦のスマホの既定の大きさ、WxH はその大きさの縦のスマホ。
    def lookOf(text: String): SceneRender.Look =
        let parts = String.splitOn({ substr = "x" }, String.trim(text)) |> List.filterMap(Float64.fromString);
        match parts {
            case w :: h :: Nil if w > 0.0 and h > w => SceneRender.Look.Portrait({ x = w, y = h })
            case _ if String.isEmpty(String.trim(text)) or text == "0" => SceneRender.Look.Landscape(Display.SizeClass.Large)
            case _ => SceneRender.Look.Portrait(Display.defaultPortraitView())
        }

    /// 撮るコマの上限（30fps で 5 分。flow の until の max が先に当たる）。
    def frameCap(): Int32 = 9000

    /// cfg = 描き出しの設定（design は撮る画面の design）、display = ViewCtx に渡す画面の情報（縦なら縦のスマホ）。
    def write(settings: VideoOut.Settings, fps: Float64, out: String, cfg: HeadlessRender.RenderConfig, display: Display.Display,
              outcome: Flow.Outcome[AppState]): Unit \ IO =
        discard (new File(out)).mkdirs();
        let rate = Float64.tryToInt32(Float64.round(fps)) |> Option.getWithDefault(30);
        writeText("${out}/fps.txt", Int32.toString(rate));
        writeAudio("${out}/audio.f64", fps, outcome);
        let atlases = SceneRender.fontsOf();
        let soft = { fontAtlas = atlases#ui, outDir = out | cfg };
        let video = { outDir = out, fps = rate, soft = soft, softFonts = SceneRender.fontOfName(atlases), extraFonts = SceneRender.extraFontsOf(atlases),
                      images = Nil, scene = fonts -> h -> sceneOf(fonts, cfg#design, display, h), wanted = _ -> true, bakeSurfaces = false,
                      encoders = Nil };
        discard VideoOut.writeFrames(settings, video, Flow.worldsOf(outcome))

    /// 1 コマの絵（SceneRender.shootAs と同じ合流: 画面は frame、画面の上の窓は hud）。
    def sceneOf(fonts: String -> FontAtlas, design: Vec2.Vec2, display: Display.Display, h: AppState): List[Render.PlacedItem] =
        let ctx = { display = display | App.viewCtxOfFonts(fonts("default"), fonts, design) };
        App.composeScene(None, 1.0, design, { world = Resources.view(View.frame, ctx, h), hud = Resources.view(View.hud, ctx, h) })

    def sampleRate(): Int32 = 44100

    /// 各フレームに鳴った音と鳴り続ける音を、そのフレームの World のミキサーで混ぜて書く。
    def writeAudio(path: String, fps: Float64, outcome: Flow.Outcome[AppState]): Unit \ IO =
        let entries = soundFiles();
        let sounds = loadSounds(entries, Map.empty());
        let loops = loadLoops(entries, Map.empty());
        let frames = outcome#frames |> List.map(played ->
            { plays = played#step#sounds, sustained = played#step#sustained, mixer = Resources.read(Controls.mixerOf, played#step#after) });
        let mixed = AudioMixdown.mixdownStereo(sampleRate(), fps, sounds, loops, frames);
        writeSamples(path, mixed)

    def writeSamples(path: String, mixed: AudioMixdown.Stereo): Unit \ IO =
        let out = new DataOutputStream(new BufferedOutputStream(new FileOutputStream(path)));
        let n = Int32.min(Vector.length(mixed#left), Vector.length(mixed#right));
        def go(i: Int32): Unit \ IO =
            if (i >= n) ()
            else {
                out.writeDouble(Vector.get(i, mixed#left));
                out.writeDouble(Vector.get(i, mixed#right));
                go(i + 1)
            };
        go(0);
        out.close()

    def loadSounds(entries: List[(String, String, Bool)], acc: Map[String, AudioMixdown.Stereo]): Map[String, AudioMixdown.Stereo] \ IO =
        match entries {
            case (name, file, _) :: rest => loadSounds(rest, Map.insert(name, AudioMixdown.loadWavStereo(sampleRate(), file), acc))
            case Nil                     => acc
        }

    def loadLoops(entries: List[(String, String, Bool)], acc: Map[String, Int32]): Map[String, Int32] \ IO =
        match entries {
            case (name, file, true) :: rest => match AudioMixdown.loadLoopStart(sampleRate(), file) {
                case Some(at) => loadLoops(rest, Map.insert(name, at, acc))
                case None     => loadLoops(rest, acc)
            }
            case _ :: rest => loadLoops(rest, acc)
            case Nil       => acc
        }

    /// project.json の sounds（名前・ファイル・鳴り続けるか）。
    def soundFiles(): List[(String, String, Bool)] \ IO =
        let rows = run { DocJson.readJson("project.json") } with Fs.FileRead.runWithIO;
        rows |> Result.toOption |> Option.flatMap(JsonCodec.expectObject)
             |> Option.flatMap(root -> Map.get("sounds", root))
             |> Option.flatMap(JsonCodec.decodeList(j -> JsonCodec.expectObject(j) |> Option.map(obj ->
                    (JsonCodec.stringOr("name", "", obj), JsonCodec.stringOr("path", "", obj), JsonCodec.boolOr("looping", false, obj)))))
             |> Option.getWithDefault(Nil)

    /// e2e/showcase.flow → showcase。
    def nameOf(path: String): String =
        let base = String.splitOn({substr = "/"}, path) |> List.last |> Option.getWithDefault(path);
        String.stripSuffix({substr = ".flow"}, base) |> Option.getWithDefault(base)

    def writeText(path: String, text: String): Unit \ IO =
        let out = new FileWriter(path);
        out.write(text);
        out.close()
}
