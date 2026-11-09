// View — World から「(置き場所, 見せたい物) のリスト」への投影（純粋）。
//
// ── この画面の画風（AGENTS.local.md と同じ宣言）──
// 「深夜のチャットアプリの画面そのものが舞台。暗い UI の上で 3 色の名前が会話し、恐怖が進むほど画面が冷え、最後は UI ごと闇に呑まれる」
//   色は 3 つ: UI の地の暗い灰紺 / 3 人の色（黄・緑・赤）/ 水の青白（冷えと水滴）。血の赤は最後の 1 回だけ。
//   やらないこと: 恐怖の演出を先に見せない（水滴はテレビの場面まで取っておき、チャットは冷えだけ）。
// 字と枠（チャットの UI・字幕の帯・画面の枠）は図形で描き、「アバター・テレビ・地の文の背景・水滴・血文字・タイトルの絵」は
// assets/gpt/ の画像を貼る（View.imageOf を呼ぶ所）。画像がまだ届いていない部品は、その部品だけ図形で描く（Art.imageOf）。
//
// ── 画面の層（奥から手前へ）──
//   world（揺れはここだけに掛かる）:
//     チャット … 地（サーバー・チャンネル・会話・メンバーの列）→ 履歴の発言（アバター・名前・時刻・本文）→ 入力中の行と入力欄 → 上の帯
//                → 冷え（青白い覆いと四隅の翳り）→ 地の文の層（チャットを沈める幕・部屋の明かり・明朝の字）
//     テレビ   … 映り（スタジオとキャスター / 砂嵐）→ 走査線とノイズ → 字幕の帯 → 水滴 → 冷え
//     真っ暗   … 黒 → 血文字（一瞬だけ）
//     タイトル・クレジット
//   hud: 素材を待つ間の黒 → 画面（バックログ・セーブ・ロード・設定）→ 確認のウィンドウ → 知らせ
//
// ── 時計 ── 打つ・発言が入る動き・地の文の層の出入り・冷え・揺れ・キャスターが倒れる動きは物語の時計（画面を開くと止まる）、
//            入力中の点・カーソルの明滅・砂嵐・水滴・字の震え・タイトル・クレジットは実時間（env#realNow）。
// ── 触れている物 ── マウスの位置 env#pointer に乗っている物（ボタン・枠・行）を明るくする。押せる所は Layout の同じ矩形。
mod View {
    use fge::{App, Clock, Color, Curve, DrawCmd, FontAtlas, Fx, Num, RawDraw, Rect2, Render, RichText, ShaderDoc, TextDraw, UiScroll, Vec2}
    use fge::ShaderDoc.{BinOp, Field, Shade, Out, UnOp}

    /// どの場面でも使う描く元: Doc とシナリオ（res）・セーブデータ（既読と設定と枠）・マウスの位置・2 本の時計の今・
    /// 並べ方の組（fit。Controls が当たりを取る時と同じ組）。
    pub type alias Env = {
        res = Res.Res,
        saves = Saves.Saves,
        pointer = { x = Float64, y = Float64 },
        realNow = Clock.Time[Clock.Real],
        storyNow = Clock.Time[Stage.Story],
        fit = Layout.Fit
    }

    /// 字の本 2 つ。ui = チャットアプリの字（丸ゴシック）、mincho = 地の文と血文字の字（明朝）。
    pub type alias Fonts = { ui = FontAtlas, mincho = FontAtlas }

    pub def envOf(fit: Layout.Fit, res: Res.Res, w: World.World): Env =
        { res = res, saves = w#saves, pointer = w#pointer, realNow = w#realNow, storyNow = World.now(w), fit = fit }

    /// project.json の fonts の名前（明朝）。丸ゴシックは default。
    pub def minchoFont(): String = "mincho"

    def fontsOf(ctx: App.ViewCtx): Fonts = { ui = ctx#atlas, mincho = ctx#fontOf(minchoFont()) }

    // WhyNot: ctx#visible#size を design の大きさとして読んでよいのは、このゲームが camera を使わないから（HUD は常に design 全体）。
    def fitOfCtx(ctx: App.ViewCtx, res: Res.Res): Layout.Fit =
        Layout.fitOf(ctx#display#sizeClass, ctx#display#orientation, ctx#visible#size, res#smallScreen, res#portrait)

    // ── z（小さいほど奥） ──
    // world
    def zGround(): Int32 = 0
    def zColumn(): Int32 = 2
    def zAvatar(): Int32 = 8
    def zText(): Int32 = 10
    def zInput(): Int32 = 14
    def zHeader(): Int32 = 16
    def zTvOverlay(): Int32 = 20
    def zTelop(): Int32 = 24
    def zChill(): Int32 = 30
    def zThought(): Int32 = 34
    def zThoughtText(): Int32 = 38
    def zDrops(): Int32 = 42
    def zScare(): Int32 = 48
    // hud
    def zHold(): Int32 = 45
    def zHoldMark(): Int32 = 46
    def zPanel(): Int32 = 50
    def zCard(): Int32 = 52
    /// サムネの縮めた画面は zThumb + 元の z（元は 0..zScare の少し上）に入る。縁と印は zThumbTop から。
    def zThumb(): Int32 = 60
    def zThumbTop(): Int32 = 115
    def zPanelText(): Int32 = 120
    def zAsk(): Int32 = 140
    def zToast(): Int32 = 160

    pub def frame(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        let fonts = fontsOf(ctx);
        let env = envOf(fitOfCtx(ctx, res), res, w);
        let k = kindOf(env);
        let stage = World.stageOf(res, w);
        let (dx, dy) = Stage.shakeOffset(env#storyNow, k#shakeSeconds, k#shakePx, stage);
        let items = match w#scene {
            case World.Scene.Title(item)           => title(fonts, env, item)
            case World.Scene.Credits(startedAt, _) => credits(fonts, env, startedAt)
            case World.Scene.Reading(r)            => readingScene(fonts, env, r)
        };
        items |> List.map(placed -> { at = { x = placed#at#x + dx, y = placed#at#y + dy } | placed })

    pub def hud(ctx: App.ViewCtx, res: Res.Res, w: World.World): List[Render.PlacedItem] =
        let fonts = fontsOf(ctx);
        let env = envOf(fitOfCtx(ctx, res), res, w);
        let holding = World.readOf(w) |> Option.flatMap(r -> r#hold) |> Option.map(holdLayer(env)) |> Option.getWithDefault(Nil);
        List.flatten(holding :: panel(res, fonts, env, w) :: askLayer(fonts, env, w#ask) :: toast(fonts, env, World.toastOf(res, w)) :: Nil)

    def realSeconds(env: Env): Float64 = Clock.secondsOf(env#realNow)

    def theme(env: Env): ThemeDoc.Rec = ThemeDoc.rec(env#res#theme)

    def kindOf(env: Env): KindDoc.Rec = KindDoc.rec(env#res#kind)

    def paceOf(env: Env): PaceDoc.Rec = PaceDoc.rec(env#res#pace)

    def label(l: StoryDoc.Label, env: Env): String = StoryDoc.labelOf(l, env#res#story)

    def isOver(r: Rect2.Rect2, env: Env): Bool = Layout.contains(r, env#pointer)

    /// 部品を貼る画像（無ければ None = 図形で描く）。
    def imageOf(env: Env, part: Art.Part): Option[String] = Art.imageOf(env#res#missing, part)

    def at(x: Float64, y: Float64, item: Render.Item): Render.PlacedItem = { at = { x = x, y = y }, item = item }

    def textAt(x: Float64, y: Float64, text: String, atlas: FontAtlas, size: Float64, color: Color, z: Int32): Render.PlacedItem =
        at(x, y, Render.textTinted(text, atlas, size, color, z))

    /// 右端を right に合わせた字。
    def textRight(right: Float64, y: Float64, text: String, atlas: FontAtlas, size: Float64, color: Color, z: Int32): Render.PlacedItem =
        textAt(right - TextDraw.width(text, atlas, size), y, text, atlas, size, color, z)

    /// 矩形の真ん中に置いた 1 行。
    def textIn(r: Rect2.Rect2, text: String, atlas: FontAtlas, size: Float64, color: Color, z: Int32): Render.PlacedItem =
        TextDraw.centered({ text = text, atlas = atlas, size = size, color = color, z = z,
                            centerX = r#position#x + r#size#x / 2.0, y = r#position#y + (r#size#y - size) / 2.0 - 1.0 })

    def fadeTo(alpha: Float64): Render.PlacedItem -> Render.PlacedItem = placed -> Render.overItem(item -> Render.fade(alpha, item), placed)

    /// 横で描く絵（960×540）の全体の矩形の地（揺れても端が覗かないよう一回り大きく）。縦の画面では寄せた範囲だけが見える。
    def wholeGrad(colors: { top = Color, bottom = Color }, z: Int32): Render.PlacedItem =
        at(-14.0, -14.0, Render.vgrad({ x = 988.0, y = 568.0 }, colors, z))

    /// 画面全体の矩形の地（横は wholeGrad と同じ・縦は縦の画面いっぱい）。
    def screenGrad(env: Env, colors: { top = Color, bottom = Color }, z: Int32): Render.PlacedItem =
        let s = Layout.size(env#fit);
        at(-14.0, -14.0, Render.vgrad({ x = s#x + 28.0, y = s#y + 28.0 }, colors, z))

    /// 画面全体を 1 色で覆う（揺れても端が覗かないよう一回り大きく）。
    def screenBox(env: Env, color: Color, z: Int32): Render.PlacedItem =
        let s = Layout.size(env#fit);
        at(-14.0, -14.0, RawDraw.box({ x = s#x + 28.0, y = s#y + 28.0 }, color, z))

    /// 画面の真ん中。
    def screenCenter(env: Env): Vec2.Vec2 = { x = Layout.width(env#fit) / 2.0, y = Layout.height(env#fit) / 2.0 }

    /// 画面の四隅。
    def screenCorners(env: Env): List[Vec2.Vec2] =
        let w = Layout.width(env#fit);
        let h = Layout.height(env#fit);
        { x = 0.0, y = 0.0 } :: { x = w, y = 0.0 } :: { x = 0.0, y = h } :: { x = w, y = h } :: Nil

    /// 横で描いた絵（960×540 の座標の物）の範囲 crop を、画面の dst いっぱいに縮め・寄せて、dst の外を切る。
    def intoFrame(crop: Rect2.Rect2, dst: Rect2.Rect2, items: List[Render.PlacedItem]): List[Render.PlacedItem] =
        let k = dst#size#x / crop#size#x;
        items |> Render.scaledAllAround(k, { x = 0.0, y = 0.0 })
              |> Render.movedAll({ x = dst#position#x - crop#position#x * k, y = dst#position#y - crop#position#y * k })
              |> Render.clippedAll(dst)

    /// 横で描いた絵を、横の画面ではそのまま・縦の画面では crop を dst に寄せて出す。
    def landscapeInto(env: Env, crop: Rect2.Rect2, dst: Rect2.Rect2, items: List[Render.PlacedItem]): List[Render.PlacedItem] =
        if (Layout.isPortrait(env#fit)) intoFrame(crop, dst, items) else items

    /// 平らなボタンの地と縁（lit = 選んでいる・触れている）。
    def plate(r: Rect2.Rect2, lit: Bool, env: Env, z: Int32): Render.PlacedItem =
        let t = theme(env);
        let fill = if (lit) Color.mix(t#sidebar, t#accent, 0.22) else Color.lighten(t#sidebar, 0.05);
        at(r#position#x, r#position#y,
           Render.vgrad(r#size, { top = Color.lighten(fill, 0.04), bottom = fill }, z) |> Render.fade(0.95)
               |> Render.outlineA({ color = if (lit) t#accent else Color.mix(t#ink, t#sidebar, 0.75), alpha = if (lit) 0.9 else 0.6, width = 1.0 })
               |> Render.rounded(4.0))

    /// 字幅の見積もり（全角は size・半角は size の 0.56）。描く行の折り方と、当たり・スクロールの量の勘定が同じ折り方を使う。
    def charWidth(size: Float64): Char -> Float64 = ch -> if (Char.toBmpCodePoint(ch) < 128) size * 0.56 else size

    /// text を幅 width で折った行（空の字は 1 行の空）。
    pub def wrapRows(size: Float64, width: Float64, text: String): List[String] =
        let rows = RichText.wrapLinesBy(charWidth(size), width, RichText.plain(text) :: Nil) |> List.map(RichText.plainText);
        if (List.isEmpty(rows)) "" :: Nil else rows

    /// 画面の行の折り方。縦の画面は、行の頭に来た句読点と閉じ括弧を前の行の最後の字ごと次の行へ送る。
    // WhyNot: 横の画面で送らない — 横の絵はスナップショット（reference）で止めてあり、狭い縦の行ほど行頭の句読点が目立つ。
    def wrapRowsOf(env: Env, size: Float64, width: Float64, text: String): List[String] =
        let rows = wrapRows(size, width, text);
        if (Layout.isPortrait(env#fit)) pushOutLeadingMarks(rows) else rows

    /// 行の頭に置かない字（句読点・閉じ括弧・小書きの字・のばし・三点）。
    // WhyNot: 禁則の字を全部は並べない — フォントのサブセットに無い字をここへ書くと、ブラウザ版の書き出しが「出ない字」として止める（サブセットに無い字は台本にも出ない）。
    def isLeadingMark(ch: Char): Bool = String.contains(substr = Char.toString(ch), "、。」』）！？…ー〜ぇっゃょァィェォッャュョ")

    /// 頭が isLeadingMark の行があれば、前の行の最後の 1 字をその行の頭へ移す（字の数の合計は変えない）。
    pub def pushOutLeadingMarks(rows: List[String]): List[String] =
        let (done, last) = rows |> List.foldLeft((acc, row) -> {
            let (out, prev) = acc;
            match (prev, String.toList(row)) {
                case (Some(p), first :: _) if isLeadingMark(first) and String.length(p) >= 2 =>
                    (String.dropRight(1, p) :: out, Some("${String.takeRight(1, p)}${row}"))
                case (Some(p), _) => (p :: out, Some(row))
                case (None, _)    => (out, Some(row))
            }
        }, (Nil, None));
        List.reverse(last |> Option.map(l -> l :: done) |> Option.getWithDefault(done))

    /// 行の列を上から並べる（visible = 頭から見せる字の数）。
    def placeRows(rows: List[String], pos: Vec2.Vec2, lineHeight: Float64, look: { atlas = FontAtlas, size = Float64, color = Color, z = Int32 },
                  visible: Int32): List[Render.PlacedItem] =
        let (items, _, _) = rows |> List.foldLeft((acc, row) -> {
            let (done, y, left) = acc;
            let shown = String.takeLeft(Int32.max(0, left), row);
            let placed = if (String.isEmpty(shown)) done else textAt(pos#x, y, shown, look#atlas, look#size, look#color, look#z) :: done;
            (placed, y + lineHeight, left - String.length(row))
        }, (Nil, pos#y, visible));
        List.reverse(items)

    /// 字が震える行: 1 字ずつ少しずらし、ときどき色をずらした影を重ねる（実時間で揺れ続ける）。
    def glitchRows(rows: List[String], pos: Vec2.Vec2, lineHeight: Float64, look: { atlas = FontAtlas, size = Float64, color = Color, z = Int32 },
                   env: Env, visible: Int32): List[Render.PlacedItem] =
        let t = realSeconds(env);
        let tick = Float64.floor(t * 14.0);
        let water = theme(env)#water;
        let (items, _, _) = rows |> List.foldLeft((acc, row) -> {
            let (done, y, left) = acc;
            let chars = String.toList(String.takeLeft(Int32.max(0, left), row)) |> List.zipWithIndex;
            let placed = chars |> List.flatMap(match (i, ch) -> {
                let text = Char.toString(ch);
                let x = pos#x + TextDraw.width(String.takeLeft(i, row), look#atlas, look#size);
                let seed = Int32.toFloat64(i) * 12.9898 + tick * 78.233 + y;
                let jx = (Num.fract(Num.sin(seed) * 43758.5453) - 0.5) * 3.2;
                let jy = (Num.fract(Num.sin(seed * 1.7) * 24634.6345) - 0.5) * 3.6;
                let split = Num.fract(Num.sin(seed * 0.37) * 9631.13) > 0.72;
                let main = textAt(x + jx, y + jy, text, look#atlas, look#size, look#color, look#z + 1);
                if (split) main :: (textAt(x + jx + 2.0, y + jy, text, look#atlas, look#size, water, look#z) |> fadeTo(0.55)) :: Nil
                else main :: Nil
            });
            (placed :: done, y + lineHeight, left - String.length(row))
        }, (Nil, pos#y, visible));
        items |> List.reverse |> List.flatten

    // ── 読んでいる間の画面 ──

    /// 読んでいる間の 1 画面（揺れの前）。サムネも同じ関数で描く。
    def readingScene(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let stage = r#stage;
        let screen = match stage#screen {
            case Stage.Screen.Chat => chatScreen(fonts, env, r)
            case Stage.Screen.Tv   => tvScreen(fonts, env, r)
            case Stage.Screen.Dark => darkScreen(fonts, env, stage)
        };
        let drops = match (stage#screen, stage#dropsFrom) {
            case (Stage.Screen.Dark, _) => Nil
            case (_, Some(start))       => dropsLayer(env, start)
            case (_, None)              => Nil
        };
        let chill = if (stage#screen == Stage.Screen.Dark) Nil else chillLayer(env, Stage.chillAt(env#storyNow, stage));
        List.flatten(screen :: drops :: chill :: Nil)

    // ── チャット ──

    def chatScreen(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        List.flatten(chatFrame(fonts, env, r#stage) :: feedLayer(fonts, env, r) :: inputLayer(fonts, env, r)
                     :: headerLayer(fonts, env, r) :: thoughtLayer(fonts, env, r) :: Nil)

    /// チャットアプリの地: サーバーの列・チャンネルの列・会話の地・メンバーの列（奥ほど暗い灰紺）。
    def chatFrame(fonts: Fonts, env: Env, stage: Stage.Stage): List[Render.PlacedItem] =
        let t = theme(env);
        let fit = env#fit;
        let col = Layout.chatColumn(fit);
        let ground = screenGrad(env, { top = Color.lighten(t#chat, 0.03), bottom = Color.darken(t#chat, 0.12) }, zGround());
        // WhyNot: 会話の地をベタにしない — 画面の光が上から落ちる階調が無いと、モニターの面ではなく板に見える。
        let glow = Render.lightAt({ at = { x = col#position#x + col#size#x / 2.0, y = 40.0 }, radius = 520.0, color = Color.cool(t#chat, 0.3), strength = 0.18, z = zGround() + 1 });
        List.flatten((ground :: glow :: Nil) :: railLayer(fonts, env) :: sidebarLayer(fonts, env, stage) :: membersLayer(fonts, env, stage) :: Nil)

    /// サーバーの列: 選んでいるサーバー（大学ゲーム部）の角丸の印と、左の白い棒・ほかの薄い印。
    def railLayer(fonts: Fonts, env: Env): List[Render.PlacedItem] =
        let t = theme(env);
        let rail = Layout.rail(env#fit);
        if (rail#size#x <= 0.0) Nil
        else {
            let x = rail#position#x + (rail#size#x - 40.0) / 2.0;
            let icon = (y: Float64, fill: Color, text: String, lit: Bool) ->
                at(x, y, Render.vgrad({ x = 40.0, y = 40.0 }, { top = Color.lighten(fill, 0.12), bottom = fill }, zColumn() + 1)
                         |> Render.rounded(if (lit) 13.0 else 20.0))
                :: textIn({ position = { x = x, y = y }, size = { x = 40.0, y = 40.0 } }, text, fonts#ui, 17.0,
                          if (lit) t#ink else t#inkDim, zColumn() + 2) :: Nil;
            let server = StoryDoc.labelOf(StoryDoc.Label.ServerName, env#res#story);
            List.flatten(
                (at(0.0, 0.0, Render.vgrad({ x = rail#size#x, y = rail#size#y }, { top = t#rail, bottom = Color.darken(t#rail, 0.25) }, zColumn())) ::
                 at(x + 8.0, 62.0, RawDraw.box({ x = 24.0, y = 2.0 }, Color.mix(t#rail, t#ink, 0.18), zColumn() + 1)) ::
                 at(0.0, 76.0, RawDraw.box({ x = 4.0, y = 40.0 }, t#ink, zColumn() + 2) |> Render.rounded(2.0)) :: Nil)
                :: icon(12.0, Color.mix(t#sidebar, t#rail, 0.3), "＃", false)
                :: icon(76.0, Color.mix(t#accent, t#rail, 0.45), String.takeLeft(1, server), true)
                :: icon(128.0, Color.mix(t#sidebar, t#rail, 0.2), "ゲ", false)
                :: icon(180.0, Color.mix(t#sidebar, t#rail, 0.2), "＋", false) :: Nil)
        }

    /// チャンネルの列: サーバーの名前・テキストチャンネルの一覧（ゲーム部屋を選んでいる）・下の自分（かーぼー）の欄。
    def sidebarLayer(fonts: Fonts, env: Env, stage: Stage.Stage): List[Render.PlacedItem] =
        let t = theme(env);
        let side = Layout.sidebar(env#fit);
        if (side#size#x <= 0.0) Nil
        else {
            let x = side#position#x;
            let w = side#size#x;
            let header = Layout.header(env#fit)#size#y;
            let channel = (i: Int32, name: StoryDoc.Label, lit: Bool) -> {
                let y = 92.0 + Int32.toFloat64(i) * 30.0;
                let box = if (lit) at(x + 8.0, y - 4.0, Render.vgrad({ x = w - 16.0, y = 26.0 }, { top = Color.lighten(t#sidebar, 0.1), bottom = Color.lighten(t#sidebar, 0.07) }, zColumn() + 1) |> Render.rounded(4.0)) :: Nil else Nil;
                let ink = if (lit) t#ink else t#inkDim;
                List.append(box, textAt(x + 16.0, y, "#", fonts#ui, 15.0, Color.mix(ink, t#sidebar, 0.25), zColumn() + 2) ::
                                 textAt(x + 32.0, y, label(name, env), fonts#ui, 14.0, ink, zColumn() + 2) :: Nil)
            };
            let me = Talk.me();
            let meOnline = List.memberOf(me, stage#online);
            let panelY = side#size#y - 54.0;
            List.flatten(
                (at(x, 0.0, Render.vgrad({ x = w, y = side#size#y }, { top = t#sidebar, bottom = Color.darken(t#sidebar, 0.15) }, zColumn())) ::
                 textAt(x + 16.0, (header - 15.0) / 2.0, label(StoryDoc.Label.ServerName, env), fonts#ui, 15.0, t#ink, zColumn() + 2) ::
                 at(x, header - 1.0, RawDraw.box({ x = w, y = 1.0 }, Color.darken(t#rail, 0.2), zColumn() + 2) |> Render.fade(0.8)) ::
                 textAt(x + 12.0, 66.0, label(StoryDoc.Label.TextChannels, env), fonts#ui, 11.0, t#inkDim, zColumn() + 2) ::
                 at(x, panelY, Render.vgrad({ x = w, y = 54.0 }, { top = Color.darken(t#sidebar, 0.18), bottom = Color.darken(t#sidebar, 0.3) }, zColumn() + 1)) :: Nil)
                :: channel(0, StoryDoc.Label.ChannelNews, false) :: channel(1, StoryDoc.Label.Channel, true) :: channel(2, StoryDoc.Label.ChannelTalk, false)
                :: avatar(fonts, env, Some(me), false, { x = x + 26.0, y = panelY + 27.0 }, 32.0, zColumn() + 3)
                :: statusDot(env, { x = x + 37.0, y = panelY + 38.0 }, meOnline, theme(env)#sidebar, zColumn() + 6)
                :: (textAt(x + 50.0, panelY + 11.0, StoryDoc.castName(me, env#res#story), fonts#ui, 13.0, ThemeDoc.castColor(me, env#res#theme), zColumn() + 3) ::
                    textAt(x + 50.0, panelY + 29.0, label(if (meOnline) StoryDoc.Label.Online else StoryDoc.Label.Offline, env), fonts#ui, 11.0, t#inkDim, zColumn() + 3) :: Nil)
                :: Nil)
        }

    /// オンラインの印（緑の点・オフラインは灰の輪）。cut = 印の周りを抜く地の色。
    def statusDot(env: Env, center: Vec2.Vec2, online: Bool, cut: Color, z: Int32): List[Render.PlacedItem] =
        let t = theme(env);
        RawDraw.circleAt(center, 6.0, cut, z) ::
        (if (online) RawDraw.circleAt(center, 4.0, t#kaabo, z + 1) :: Nil
         else RawDraw.circleAt(center, 4.0, t#inkDim, z + 1) :: RawDraw.circleAt(center, 2.0, cut, z + 2) :: Nil)

    /// メンバーの列: オンライン（入っている人・入った順）とオフライン（まだ入っていない・出て行った人）。
    def membersLayer(fonts: Fonts, env: Env, stage: Stage.Stage): List[Render.PlacedItem] =
        let t = theme(env);
        let m = Layout.members(env#fit);
        if (m#size#x <= 0.0) Nil
        else {
            let x = m#position#x;
            let online = stage#online;
            let offline = Talk.casts() |> List.filter(c -> not List.memberOf(c, online));
            let row = (i: Int32, top: Float64, cast: Talk.Cast, on: Bool) -> {
                let y = top + Int32.toFloat64(i) * 42.0;
                let alpha = if (on) 1.0 else 0.38;
                List.flatten(avatar(fonts, env, Some(cast), List.memberOf(cast, stage#impostors), { x = x + 26.0, y = y + 16.0 }, 30.0, zColumn() + 3)
                    :: statusDot(env, { x = x + 36.0, y = y + 26.0 }, on, Color.darken(t#chat, 0.06), zColumn() + 6)
                    :: (textAt(x + 50.0, y + 8.0, StoryDoc.castName(cast, env#res#story), fonts#ui, 13.0, ThemeDoc.castColor(cast, env#res#theme), zColumn() + 3) :: Nil) :: Nil)
                    |> List.map(fadeTo(alpha))
            };
            let heading = (y: Float64, l: StoryDoc.Label, n: Int32) ->
                textAt(x + 12.0, y, "${label(l, env)} — ${n}", fonts#ui, 11.0, t#inkDim, zColumn() + 2);
            let offTop = 52.0 + Int32.toFloat64(List.length(online)) * 42.0 + 26.0;
            List.flatten(
                (at(x, m#position#y, Render.vgrad(m#size, { top = Color.darken(t#chat, 0.06), bottom = Color.darken(t#chat, 0.16) }, zColumn())) ::
                 heading(m#position#y + 16.0, StoryDoc.Label.Online, List.length(online)) ::
                 heading(m#position#y + offTop - 22.0, StoryDoc.Label.Offline, List.length(offline)) :: Nil)
                :: (online |> List.zipWithIndex |> List.flatMap(match (i, c) -> row(i, m#position#y + 36.0, c, true)))
                :: (offline |> List.zipWithIndex |> List.flatMap(match (i, c) -> row(i, m#position#y + offTop, c, false))) :: Nil)
        }

    /// 上の帯: 「# ゲーム部屋」と、右にクイックメニュー（チャットの画面の間だけ）。下に影の線。
    /// 縦の画面はチャンネル名の下に入っている人数（メンバーの列の代わり）を添え、右に ≡ を置く。
    def headerLayer(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let t = theme(env);
        let h = Layout.header(env#fit);
        let text = Layout.headerText(env#fit);
        let titleSize = text#title;
        let ty = h#position#y + text#titleTop;
        let ground = at(h#position#x, 0.0, Render.vgrad(h#size, { top = Color.lighten(t#chat, 0.02), bottom = t#chat }, zHeader()));
        let shadow = at(h#position#x, h#size#y, Render.vgrad({ x = h#size#x, y = 6.0 }, { top = Color.darken(t#rail, 0.2), bottom = t#chat }, zHeader()) |> Render.fade(0.7));
        let markX = if (Layout.isPortrait(env#fit)) 24.0 else 16.0;
        let mark = textAt(h#position#x + markX, ty, "#", fonts#ui, titleSize + 4.0, t#inkDim, zHeader() + 1);
        let nameX = if (Layout.isPortrait(env#fit)) markX + titleSize + 4.0 else 36.0;
        let name = textAt(h#position#x + nameX, ty, label(StoryDoc.Label.Channel, env), fonts#ui, titleSize, t#ink, zHeader() + 1);
        let count = if (text#sub <= 0.0) Nil
            else {
                let sy = h#position#y + text#subTop;
                let x = h#position#x + nameX;
                let online = List.length(r#stage#online);
                RawDraw.circleAt({ x = x + text#sub * 0.35, y = sy + text#sub * 0.55 }, text#sub * 0.3, if (online > 0) t#kaabo else t#inkDim, zHeader() + 1)
                :: textAt(x + text#sub, sy, "${label(StoryDoc.Label.Online, env)} — ${online}", fonts#ui, text#sub, t#inkDim, zHeader() + 1) :: Nil
            };
        let buttons = if (WorldMenu.showsButtons(r#stage#screen)) quickMenu(fonts, env, r) else Nil;
        List.flatten((ground :: shadow :: mark :: name :: Nil) :: count :: buttons :: Nil)

    /// 履歴の 1 行の置き方。head = 名前と時刻とアバターを付ける（同じ人が続く時は付けない）。
    type alias Block = { line = Page.Line, head = Bool, rows = List[String], height = Float64 }

    def rowHeightOf(env: Env): Float64 =
        let sizes = Layout.chatSizes(env#fit, kindOf(env));
        sizes#body + kindOf(env)#lineGap

    /// 履歴の行の置き方（古い順）。
    def feedBlocks(env: Env, lines: List[Page.Line]): List[Block] =
        let sizes = Layout.chatSizes(env#fit, kindOf(env));
        let rowH = rowHeightOf(env);
        let width = Layout.feedTextWidth(env#fit);
        List.zip(lines, None :: List.map(l -> Some(l), lines)) |> List.map(match (line, prev) -> {
            let rows = wrapRowsOf(env, sizes#body, width, line#text);
            let n = Int32.toFloat64(List.length(rows));
            let continued = match (line#kind, prev) {
                case (Page.Kind.Post(cast), Some(p)) => p#kind == Page.Kind.Post(cast) and p#impostor == line#impostor
                case _                               => false
            };
            match line#kind {
                case Page.Kind.Notice(_, _) => { line = line, head = false, rows = rows, height = rowH + 14.0 }
                case _ =>
                    if (continued) { line = line, head = false, rows = rows, height = n * rowH + 4.0 }
                    else { line = line, head = true, rows = rows, height = sizes#name + 8.0 + n * rowH + 12.0 }
            }
        })

    /// 履歴: 新しい発言を下端にそろえて上へ積む。出し終えたばかりの発言は下から入り、前の行を押し上げる。
    def feedLayer(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let area = Layout.feed(env#fit);
        let blocks = feedBlocks(env, Page.shownFeed(r#page));
        let slide = match (r#page#current, r#doneAt) {
            case (Some(line), Some(done)) if Page.isPost(line) =>
                let p = paceOf(env)#slideSeconds;
                let u = if (p <= 0.0) 1.0 else Num.clamp01(Clock.since(done, env#storyNow) / p);
                let last = List.last(blocks) |> Option.map(b -> b#height) |> Option.getWithDefault(0.0);
                (1.0 - Curve.pieces((0.0, 0.0) :: (0.45, 0.82) :: (1.0, 1.0) :: Nil, u)) * last
            case _ => 0.0
        };
        let (items, _) = List.reverse(blocks) |> List.foldLeft((acc, b) -> {
            let (done, bottom) = acc;
            let top = bottom - b#height;
            if (bottom < area#position#y) (done, top)
            else (List.append(feedBlock(fonts, env, b, top), done), top)
        }, (Nil, area#position#y + area#size#y + slide));
        Render.clippedAll(area, items)

    /// 履歴の 1 行。
    def feedBlock(fonts: Fonts, env: Env, b: Block, top: Float64): List[Render.PlacedItem] =
        let t = theme(env);
        let fit = env#fit;
        let sizes = Layout.chatSizes(fit, kindOf(env));
        let rowH = rowHeightOf(env);
        let left = Layout.feedTextLeft(fit);
        let clock = "${label(StoryDoc.Label.Today, env)} ${PaceDoc.clockText(b#line#posted, env#res#pace)}";
        let look = { atlas = fonts#ui, size = sizes#body, color = t#ink, z = zText() };
        let body = (y: Float64) -> if (b#line#glitch) glitchRows(b#rows, { x = left, y = y }, rowH, look, env, String.length(b#line#text))
                                   else placeRows(b#rows, { x = left, y = y }, rowH, look, String.length(b#line#text));
        match b#line#kind {
            case Page.Kind.Notice(cast, presence) =>
                let (arrow, color) = match presence {
                    case Stage.Presence.Join  => ("→", t#kaabo)
                    case Stage.Presence.Leave => ("←", t#kansai)
                };
                let y = top + 7.0;
                let size = sizes#body * 0.92;
                let name = StoryDoc.castName(cast, env#res#story);
                let rest = String.dropLeft(String.length(name), b#line#text);
                let nameW = TextDraw.width(name, fonts#ui, size);
                textAt(left - 30.0, y, arrow, fonts#ui, size, color, zText())
                :: textAt(left, y, name, fonts#ui, size, ThemeDoc.castColor(cast, env#res#theme), zText())
                :: textAt(left + nameW, y, rest, fonts#ui, size, t#inkDim, zText())
                :: textAt(left + nameW + TextDraw.width(rest, fonts#ui, size) + 10.0, y + 2.0, clock, fonts#ui, sizes#body * 0.72, Color.mix(t#inkDim, t#chat, 0.3), zText()) :: Nil
            case Page.Kind.Post(cast) if b#head =>
                let nameText = StoryDoc.castName(cast, env#res#story);
                let nameY = top + 8.0;
                let a = Layout.avatarSize(fit);
                List.flatten(
                    avatar(fonts, env, Some(cast), b#line#impostor, { x = Layout.feed(fit)#position#x + 16.0 + a / 2.0, y = top + 8.0 + a / 2.0 }, a, zAvatar())
                    :: (textAt(left, nameY, nameText, fonts#ui, sizes#name, ThemeDoc.castColor(cast, env#res#theme), zText())
                        :: textAt(left + TextDraw.width(nameText, fonts#ui, sizes#name) + 10.0, nameY + sizes#name * 0.2, clock, fonts#ui, sizes#name * 0.72, t#inkDim, zText()) :: Nil)
                    :: body(nameY + sizes#name + 8.0) :: Nil)
            case _ => body(top + 2.0)
        }

    /// 入力中の行（ほかの人が打っている間）と、下の入力欄（自分が打っている間は字が一字ずつ出る）。
    def inputLayer(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let t = theme(env);
        let fit = env#fit;
        let box = Layout.input(fit);
        let size = Layout.chatSizes(fit, kindOf(env))#body;
        let typing = Page.typingOf(r#page);
        let mine = typing == Some(Talk.me());
        let ground = at(box#position#x, box#position#y,
                        Render.vgrad(box#size, { top = Color.lighten(t#chat, 0.07), bottom = Color.lighten(t#chat, 0.04) }, zInput())
                            |> Render.outlineA({ color = if (mine) ThemeDoc.castColor(Talk.me(), env#res#theme) else Color.darken(t#rail, 0.1), alpha = if (mine) 0.5 else 0.6, width = 1.0 })
                            |> Render.rounded(8.0));
        let textY = box#position#y + (box#size#y - size) / 2.0 - 1.0;
        let plus = textIn({ position = { x = box#position#x + 8.0, y = box#position#y + 6.0 }, size = { x = box#size#y - 12.0, y = box#size#y - 12.0 } },
                          "＋", fonts#ui, size, t#inkDim, zInput() + 1);
        let textX = box#position#x + box#size#y + 2.0;
        let blink = Num.fract(realSeconds(env) * 1.1) < 0.55;
        let line = if (mine) {
            let typed = r#page#current |> Option.map(l -> String.takeLeft(Page.visibleCount(r#page), l#text)) |> Option.getWithDefault("");
            let room = box#position#x + box#size#x - 16.0 - textX;
            // 入力欄に入り切らない時は、打っている所（末尾）が見えるよう頭から隠す。
            let (kept, _) = String.toList(typed) |> List.reverse |> List.foldLeft((acc, ch) -> {
                let (out, used) = acc;
                let next = used + TextDraw.width(Char.toString(ch), fonts#ui, size);
                if (next <= room or List.isEmpty(out)) (ch :: out, next) else (out, room + 1.0)
            }, (Nil, 0.0));
            let shown = if (TextDraw.width(typed, fonts#ui, size) <= room) typed else List.join("", kept |> List.map(Char.toString));
            let caret = if (blink) at(textX + TextDraw.width(shown, fonts#ui, size) + 1.0, textY, RawDraw.box({ x = 1.5, y = size + 2.0 }, t#ink, zInput() + 2)) :: Nil else Nil;
            textAt(textX, textY, shown, fonts#ui, size, t#ink, zInput() + 1) :: caret
        } else textAt(textX, textY, label(StoryDoc.Label.InputHint, env), fonts#ui, size, Color.mix(t#inkDim, t#chat, 0.25), zInput() + 1) :: Nil;
        let typingRow = match typing {
            case Some(cast) if cast != Talk.me() =>
                let p = Layout.typingRow(fit);
                let ts = Layout.typingSize(fit);
                let k = if (Layout.isPortrait(fit)) ts / 12.0 else 1.0;
                let dots = List.range(0, 3) |> List.map(i -> {
                    let phase = realSeconds(env) * 5.0 - Int32.toFloat64(i) * 0.7;
                    let lift = Float64.max(0.0, Num.sin(phase)) * 2.5 * k;
                    RawDraw.circleAt({ x = p#x + (4.0 + Int32.toFloat64(i) * 7.0) * k, y = p#y + ts / 2.0 + 1.0 - lift }, 2.2 * k, t#ink, zInput() + 1)
                        |> fadeTo(0.45 + 0.55 * Float64.max(0.0, Num.sin(phase)))
                });
                let name = StoryDoc.castName(cast, env#res#story);
                let nx = p#x + 28.0 * k;
                List.append(dots, textAt(nx, p#y, name, fonts#ui, ts, ThemeDoc.castColor(cast, env#res#theme), zInput() + 1)
                                  :: textAt(nx + TextDraw.width(name, fonts#ui, ts), p#y, "${label(StoryDoc.Label.Typing, env)}…", fonts#ui, ts, t#inkDim, zInput() + 1) :: Nil)
            case _ => Nil
        };
        List.flatten((ground :: plus :: Nil) :: line :: typingRow :: Nil)

    // ── クイックメニュー（上の帯の右） ──

    def quickMenu(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        if (Layout.isPortrait(env#fit)) menuButton(fonts, env, r) else quickStrip(fonts, env, r)

    /// 縦の画面の上の帯の右の ≡（3 本の線）と、オート・スキップの間はその左に今の送り方のラベル。
    def menuButton(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let t = theme(env);
        let rect = Layout.button(env#fit, 0, 1);
        let over = isOver(rect, env);
        let pill = if (over) at(rect#position#x + 6.0, rect#position#y + 6.0, RawDraw.box({ x = rect#size#x - 12.0, y = rect#size#y - 12.0 }, Color.lighten(t#chat, 0.08), zHeader() + 1) |> Render.rounded(10.0)) :: Nil else Nil;
        let barW = rect#size#x * 0.42;
        let cx = rect#position#x + rect#size#x / 2.0;
        let cy = rect#position#y + rect#size#y / 2.0;
        let bars = (-1.0 :: 0.0 :: 1.0 :: Nil) |> List.map(k ->
            at(cx - barW / 2.0, cy + k * rect#size#x * 0.14 - 2.0, RawDraw.box({ x = barW, y = 4.0 }, if (over) t#ink else t#inkDim, zHeader() + 2) |> Render.rounded(2.0)));
        let playing = match r#playback {
            case World.Playback.Auto   => Some(StoryDoc.Label.Auto)
            case World.Playback.Skip   => Some(StoryDoc.Label.Skip)
            case World.Playback.Manual => None
        };
        let tag = playing |> Option.map(l -> {
            let size = Layout.headerText(env#fit)#sub;
            let text = label(l, env);
            let w = TextDraw.width(text, fonts#ui, size) + 24.0;
            let box = { position = { x = rect#position#x - 8.0 - w, y = cy - size * 0.8 }, size = { x = w, y = size * 1.6 } };
            at(box#position#x, box#position#y, RawDraw.box(box#size, Color.mix(t#chat, t#accent, 0.25), zHeader() + 1) |> Render.rounded(size * 0.8))
            :: textIn(box, text, fonts#ui, size, t#accent, zHeader() + 2) :: Nil
        }) |> Option.getWithDefault(Nil);
        List.flatten(pill :: bars :: tag :: Nil)

    /// 横の画面の上の帯の右のボタンの列。
    def quickStrip(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let t = theme(env);
        let all = WorldMenu.buttons();
        let n = List.length(all);
        all |> List.zipWithIndex |> List.flatMap(match (i, button) -> {
            let rect = Layout.button(env#fit, i, n);
            let lit = (button == World.Button.Auto and r#playback == World.Playback.Auto) or (button == World.Button.Skip and r#playback == World.Playback.Skip);
            let over = isOver(rect, env);
            let color = if (not isButtonOpen(button, env, r)) Color.mix(t#inkDim, t#chat, 0.5)
                        else if (lit) t#accent
                        else if (over) t#ink
                        else t#inkDim;
            let pill = if (lit or over)
                at(rect#position#x + 2.0, rect#position#y + 2.0, RawDraw.box({ x = rect#size#x - 4.0, y = rect#size#y - 4.0 }, if (lit) Color.mix(t#chat, t#accent, 0.25) else Color.lighten(t#chat, 0.08), zHeader() + 1) |> Render.rounded(5.0)) :: Nil
                else Nil;
            textIn(rect, label(buttonLabel(button), env), fonts#ui, Layout.buttonTextSize(env#fit), color, zHeader() + 2) :: pill
        })

    /// 押して何か起きるボタンか（戻れない時の「戻る」・クイックセーブが無い時の「Qロード」は薄く出す）。
    def isButtonOpen(button: World.Button, env: Env, r: World.Read): Bool = match button {
        case World.Button.Rollback  => r#log |> List.zipWithIndex |> List.exists(match (i, entry) -> i >= 1 and WorldLog.isJumpable(entry))
        case World.Button.QuickLoad => Option.nonEmpty(Saves.slotOf(Saves.Tab.Quick, 0, env#saves))
        case _                      => true
    }

    pub def buttonLabel(button: World.Button): StoryDoc.Label = match button {
        case World.Button.Rollback  => StoryDoc.Label.Rollback
        case World.Button.Log       => StoryDoc.Label.Log
        case World.Button.Auto      => StoryDoc.Label.Auto
        case World.Button.Skip      => StoryDoc.Label.Skip
        case World.Button.QuickSave => StoryDoc.Label.QuickSave
        case World.Button.QuickLoad => StoryDoc.Label.QuickLoad
        case World.Button.Save      => StoryDoc.Label.Save
        case World.Button.Load      => StoryDoc.Label.Load
        case World.Button.Settings  => StoryDoc.Label.Config
        case World.Button.ToTitle   => StoryDoc.Label.ToTitle
        case World.Button.Menu      => StoryDoc.Label.Menu
    }

    // ── 地の文の層 ──

    /// 地の文の層の濃さ（0〜1）と、出す行（今の地の文のまとまりか、消えていく直前のまとまり）。
    def thoughtShown(env: Env, page: Page.Page): (Float64, List[Page.Line]) =
        let fade = paceOf(env)#thoughtFadeSeconds;
        let u = if (fade <= 0.0) 1.0 else Num.clamp01(Clock.since(page#shownAt, env#storyNow) / fade);
        let block = Page.thoughtBlock(page);
        if (not List.isEmpty(block)) (if (List.isEmpty(page#thoughts)) Curve.pieces((0.0, 0.0) :: (1.0, 1.0) :: Nil, u) else 1.0, block)
        else if (not List.isEmpty(page#fading)) (1.0 - u, page#fading)
        else (0.0, Nil)

    /// 地の文の層: チャットを沈め、部屋の明かり（画像を貼る部品）の上に、続いている地の文を画面の中央に明朝で出す。前の行は薄く。
    def thoughtLayer(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let (alpha, lines) = thoughtShown(env, r#page);
        if (alpha <= 0.001 or List.isEmpty(lines)) Nil
        else {
            let t = theme(env);
            let fit = env#fit;
            let size = Layout.thoughtSize(fit, kindOf(env));
            let width = Layout.thoughtWidth(fit);
            let rowH = size * 1.75;
            let gap = size * 0.9;
            let isCurrent = (line: Page.Line) -> r#page#current |> Option.exists(c -> c#source == line#source and Page.isThought(c));
            let all = lines |> List.map(line -> (line, wrapRowsOf(env, size, width, line#text)));
            let heightOf = (rows: List[String]) -> Int32.toFloat64(List.length(rows)) * rowH;
            let room = Layout.height(fit) * 0.78;
            let (kept, _) = List.reverse(all) |> List.foldLeft((acc, pair) -> {
                let (taken, used) = acc;
                let (_, rows) = pair;
                let next = used + heightOf(rows) + (if (List.isEmpty(taken)) 0.0 else gap);
                if (List.isEmpty(taken) or next <= room) (pair :: taken, next) else (taken, room + 1.0)
            }, (Nil, 0.0));
            let total = kept |> List.foldLeft((sum, pair) -> sum + heightOf(snd(pair)) + gap, 0.0 - gap);
            let left = (Layout.width(fit) - width) / 2.0;
            let (texts, endY) = kept |> List.foldLeft((acc, pair) -> {
                let (done, y) = acc;
                let (line, rows) = pair;
                let current = isCurrent(line);
                let visible = if (current) Page.visibleCount(r#page) else String.length(line#text);
                let color = if (current) t#thought else Color.mix(t#thought, t#rail, 0.45);
                let shadow = placeRows(rows, { x = left + 1.5, y = y + 2.0 }, rowH, { atlas = fonts#mincho, size = size, color = { r = 0.0, g = 0.0, b = 0.0 }, z = zThoughtText() }, visible) |> List.map(fadeTo(0.6));
                let body = placeRows(rows, { x = left, y = y }, rowH, { atlas = fonts#mincho, size = size, color = color, z = zThoughtText() + 1 }, visible);
                (List.flatten(done :: shadow :: body :: Nil), y + heightOf(rows) + gap)
            }, (Nil, (Layout.height(fit) - total) / 2.0));
            let mark = waitMark(env, r, { x = left + width - 8.0, y = endY - gap + 6.0 });
            // WhyNot: 縦の画面で横と同じ濃さにしない — 縦は発言の字が大きく行が詰まっていて、透けた発言が地の文の字に重なって読める。
            let veil = screenBox(env, Color.darken(t#rail, 0.6), zThought()) |> fadeTo(Layout.thoughtDim(fit, paceOf(env)));
            List.flatten((veil :: roomLayer(env, r#stage)) :: texts :: mark :: Nil) |> List.map(Render.overItem(timesAlpha(alpha)))
        }

    /// 送りの印（地の文を出し終えて、人が押して送る時だけ明滅する。オートの間は点けたまま）。
    def waitMark(env: Env, r: World.Read, pos: Vec2.Vec2): List[Render.PlacedItem] =
        let thought = r#page#current |> Option.exists(Page.isThought);
        if (not thought or not Page.isDone(r#page)) Nil
        else {
            let a = if (r#playback == World.Playback.Auto) 0.85 else 0.3 + 0.6 * (0.5 + 0.5 * Num.sin(realSeconds(env) * 3.6));
            let bob = Curve.sine(2.0, 3.6, 0.0, realSeconds(env));
            at(pos#x, pos#y + bob, RawDraw.polygon({ x = 0.0, y = 0.0 } :: { x = 12.0, y = 0.0 } :: { x = 6.0, y = 8.0 } :: Nil, theme(env)#thought, zThoughtText() + 2) |> Render.fade(a)) :: Nil
        }

    // ── テレビ ──

    def tvScreen(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let stage = r#stage;
        let since = Clock.since(stage#tvFrom, env#storyNow);
        let frame = Layout.tvPicture(env#fit);
        let picture = landscapeInto(env, Layout.tvCrop(env#fit), frame, match stage#tv {
            case Stage.TvShot.Noise  => wholeGrad({ top = { r = 0.08, g = 0.09, b = 0.1 }, bottom = { r = 0.02, g = 0.02, b = 0.03 } }, zGround()) :: Nil
            case Stage.TvShot.Caster => tvPicture(env, Art.Part.Tv, since, false)
            case Stage.TvShot.Fallen => tvPicture(env, Art.Part.TvFallen, since, true)
        });
        let burst = Float64.max(0.0, 1.0 - since / 0.45);
        let noise = match stage#tv {
            case Stage.TvShot.Noise  => 1.0
            case Stage.TvShot.Caster => 0.035 + 0.9 * burst
            case Stage.TvShot.Fallen => 0.12 + 0.9 * burst
        };
        let overlay = Render.shaderFill(tvNoiseSpec(), frame, realSeconds(env), zTvOverlay())
            |> Render.withShaderParams(Map#{ "noise" => noise, "lines" => 0.07 });
        let fx = frame#position#x;
        let fy = frame#position#y;
        let fw = frame#size#x;
        let fh = frame#size#y;
        let vignette = Render.darkAt({ at = { x = fx + fw / 2.0, y = fy + fh / 2.0 }, radius = 640.0, strength = 0.0, z = zTvOverlay() + 1 });
        let cornerRadius = 360.0 * fh / 540.0;
        let corners = List.map(c -> Render.darkAt({ at = c, radius = cornerRadius, strength = 0.55, z = zTvOverlay() + 1 }),
                               { x = fx, y = fy } :: { x = fx + fw, y = fy } :: { x = fx, y = fy + fh } :: { x = fx + fw, y = fy + fh } :: Nil);
        List.flatten(tvRoom(env, frame) :: picture :: (overlay :: vignette :: corners) :: telop(fonts, env, r) :: Nil)

    /// 縦の画面でテレビの映りの外（上と下）: 暗い部屋に、映りの青い光が漏れて落ちる。横の画面は映りが画面いっぱいなので何も置かない。
    def tvRoom(env: Env, frame: Rect2.Rect2): List[Render.PlacedItem] =
        if (not Layout.isPortrait(env#fit)) Nil
        else {
            let t = theme(env);
            let mid = { x = frame#position#x + frame#size#x / 2.0, y = frame#position#y + frame#size#y / 2.0 };
            screenGrad(env, { top = Color.darken(t#rail, 0.7), bottom = Color.darken(t#rail, 0.45) }, zGround() - 1)
            :: Render.lightAt({ at = mid, radius = Layout.height(env#fit) * 0.6, color = { r = 0.35, g = 0.5, b = 0.8 }, strength = 0.22, z = zGround() - 1 })
            :: at(0.0, frame#position#y - 2.0, RawDraw.box({ x = frame#size#x, y = 2.0 }, t#water, zTvOverlay() + 2) |> Render.fade(0.35))
            :: Nil
        }

    /// テレビの映り（画像を貼る部品）。fallen = キャスターが倒れた後（図形で描く時は画面外へ落ちて画面が傾く）。
    def tvPicture(env: Env, part: Art.Part, since: Float64, fallen: Bool): List[Render.PlacedItem] =
        match imageOf(env, part) {
            case Some(name) => fullImage(name, 1.0, zGround()) :: Nil
            case None       => tvStudio(env, since, fallen)
        }

    /// 画面いっぱいの画像（960×540 の絵を真ん中に等倍で）。
    def fullImage(name: String, alpha: Float64, z: Int32): Render.PlacedItem =
        at(480.0, 270.0, Render.sprite(name, z) |> Render.fade(alpha))

    /// 走査線と砂嵐の面。noise = 砂嵐の濃さ（1 で映りが見えない）、lines = 走査線の濃さ（面に渡す数）。
    def tvNoiseSpec(): ShaderDoc.Spec =
        let grain = Field.Scaled({ factor = 1.0, scroll = { x = 0.0, y = 47.0 }, of = Field.Hash1({ scale = 240.0, seed = 11, bucket = None }) });
        let lines = Field.Smoothstep({ lo = 0.35, hi = 0.65, of = Field.Un({ op = UnOp.Fract, of = Field.Bin({ op = BinOp.Mul, a = Field.Uv({ axis = ShaderDoc.Axis.V }), b = Field.Const(180.0) }) }) });
        { name = "tv_noise", cycleRate = 0.0,
          bindings = ("grain", grain) :: ("lines", lines) :: Nil,
          out = Out.Fill({ shade = Shade.Ramp({ lo = { r = 0.02, g = 0.03, b = 0.05 }, hi = { r = 0.86, g = 0.9, b = 0.94 }, field = Field.Ref("grain") }),
                           alpha = Field.Un({ op = UnOp.Sat, of = Field.Bin({ op = BinOp.Add,
                               a = Field.Bin({ op = BinOp.Mul, a = Field.Ref("grain"), b = Field.Param({ name = "noise" }) }),
                               b = Field.Bin({ op = BinOp.Mul, a = Field.Ref("lines"), b = Field.Param({ name = "lines" }) }) }) }) }) }

    /// テレビの画像が届いていない時の映り: 夜景の窓のスタジオと机、キャスターのシルエット（記号）。倒れた後はシルエットが画面の下へ落ち、画面が傾く。
    def tvStudio(env: Env, since: Float64, fallen: Bool): List[Render.PlacedItem] =
        let t = realSeconds(env);
        let night = wholeGrad({ top = { r = 0.03, g = 0.07, b = 0.16 }, bottom = { r = 0.07, g = 0.17, b = 0.33 } }, zGround());
        let buildings = (40.0, 70.0, 230.0) :: (120.0, 60.0, 170.0) :: (190.0, 80.0, 260.0) :: (300.0, 50.0, 200.0) :: (560.0, 70.0, 250.0) ::
                        (640.0, 90.0, 210.0) :: (740.0, 60.0, 280.0) :: (810.0, 80.0, 190.0) :: (900.0, 70.0, 240.0) :: Nil;
        let skyline = buildings |> List.map(match (x, w, h) ->
            at(x, 400.0 - h, Render.vgrad({ x = w, y = h }, { top = { r = 0.06, g = 0.1, b = 0.2 }, bottom = { r = 0.03, g = 0.05, b = 0.1 } }, zGround() + 1)));
        let windows = Fx.derive(160, t, (_i, rand, now) -> {
            let b = List.nth(Float64.tryToInt32(Float64.floor(rand(0) * 9.0)) |> Option.getWithDefault(0), buildings) |> Option.getWithDefault((0.0, 10.0, 10.0));
            let (bx, bw, bh) = b;
            let x = bx + 6.0 + Float64.floor(rand(1) * (bw - 12.0) / 8.0) * 8.0;
            let y = 400.0 - bh + 10.0 + Float64.floor(rand(2) * (bh - 20.0) / 10.0) * 10.0;
            let lit = 0.35 + 0.65 * (0.5 + 0.5 * Num.sin(now * (0.2 + rand(3)) + rand(4) * 6.28));
            (x, y, lit, rand(5) > 0.6)
        }) |> List.map(match (x, y, lit, warm) ->
            at(x, y, RawDraw.box({ x = 4.0, y = 5.0 }, if (warm) { r = 1.0, g = 0.85, b = 0.6 } else { r = 0.8, g = 0.92, b = 1.0 }, zGround() + 2) |> Render.fade(lit * 0.85)));
        let pillars = (70.0 :: 340.0 :: 610.0 :: 870.0 :: Nil) |> List.map(x ->
            at(x, -14.0, Render.vgrad({ x = 18.0, y = 430.0 }, { top = { r = 0.17, g = 0.27, b = 0.42 }, bottom = { r = 0.32, g = 0.45, b = 0.62 } }, zGround() + 3)));
        let desk = at(0.0, 0.0, Render.gradPolygon(
            { pos = { x = -14.0, y = 404.0 }, color = { r = 0.74, g = 0.8, b = 0.88 }, alpha = 1.0 } ::
            { pos = { x = 974.0, y = 404.0 }, color = { r = 0.74, g = 0.8, b = 0.88 }, alpha = 1.0 } ::
            { pos = { x = 974.0, y = 554.0 }, color = { r = 0.36, g = 0.42, b = 0.52 }, alpha = 1.0 } ::
            { pos = { x = -14.0, y = 554.0 }, color = { r = 0.36, g = 0.42, b = 0.52 }, alpha = 1.0 } :: Nil, zGround() + 6));
        let deskTop = at(-14.0, 404.0, RawDraw.box({ x = 988.0, y = 3.0 }, { r = 0.92, g = 0.95, b = 1.0 }, zGround() + 7) |> Render.fade(0.8));
        let drop = if (fallen) Curve.pieces((0.0, 0.0) :: (0.18, 40.0) :: (0.55, 380.0) :: (1.0, 420.0) :: Nil, since) else 0.0;
        let lean = if (fallen) Curve.pieces((0.0, 0.0) :: (0.3, -0.03) :: (0.7, -0.09) :: (1.0, -0.1) :: Nil, since) else 0.0;
        let breathe = if (fallen) 0.0 else Curve.sine(1.2, 1.4, 0.0, t);
        let caster = casterSilhouette({ x = 480.0, y = 160.0 + breathe }) |> Render.turnedAll(lean, { x = 480.0, y = 404.0 }) |> Render.movedAll({ x = 0.0, y = drop });
        let rim = Render.glowAt({ x = 480.0, y = 200.0 + drop }, 190.0, { r = 0.45, g = 0.65, b = 0.95 }, { alpha = if (fallen) 0.12 else 0.22, blend = DrawCmd.BlendMode.Add }, zGround() + 3);
        let tilt = if (fallen) Curve.pieces((0.0, 0.0) :: (0.35, 0.016) :: (1.0, 0.012) :: Nil, since) else 0.0;
        List.flatten((night :: Nil) :: skyline :: windows :: pillars :: rim :: caster :: (desk :: deskTop :: Nil) :: Nil)
            |> Render.turnedAll(tilt, { x = 480.0, y = 270.0 })

    /// キャスターのシルエット（頭・首・肩とスーツの襟）。head = 頭の中心。机（y 404）の後ろに座っている。
    def casterSilhouette(head: Vec2.Vec2): List[Render.PlacedItem] =
        let suit = { r = 0.05, g = 0.06, b = 0.09 };
        let skin = { r = 0.16, g = 0.15, b = 0.17 };
        let hair = { r = 0.03, g = 0.03, b = 0.05 };
        let z = zGround() + 4;
        let shoulders = at(0.0, 0.0, RawDraw.polygon(
            { x = head#x - 190.0, y = 420.0 } :: { x = head#x - 170.0, y = head#y + 140.0 } :: { x = head#x - 70.0, y = head#y + 98.0 } ::
            { x = head#x + 70.0, y = head#y + 98.0 } :: { x = head#x + 170.0, y = head#y + 140.0 } :: { x = head#x + 190.0, y = 420.0 } :: Nil, suit, z));
        let collar = at(0.0, 0.0, RawDraw.polygon(
            { x = head#x - 30.0, y = head#y + 98.0 } :: { x = head#x + 30.0, y = head#y + 98.0 } :: { x = head#x, y = head#y + 190.0 } :: Nil, { r = 0.1, g = 0.11, b = 0.15 }, z + 1));
        let neck = at(head#x - 20.0, head#y + 40.0, RawDraw.box({ x = 40.0, y = 64.0 }, skin, z + 1));
        let face = RawDraw.ellipseAt({ x = head#x, y = head#y + 6.0 }, { x = 44.0, y = 56.0 }, skin, z + 2);
        let hairBack = RawDraw.ellipseAt({ x = head#x, y = head#y - 8.0 }, { x = 52.0, y = 58.0 }, hair, z + 1);
        let bangs = RawDraw.ellipseAt({ x = head#x - 6.0, y = head#y - 30.0 }, { x = 48.0, y = 26.0 }, hair, z + 3);
        shoulders :: collar :: neck :: hairBack :: face :: bangs :: Nil

    /// ニュースの字幕の帯: 下の帯に「ニュース」のラベルと、キャスターの言葉を一字ずつ。
    def telop(fonts: Fonts, env: Env, r: World.Read): List[Render.PlacedItem] =
        let fit = env#fit;
        let band = Layout.captionBand(fit);
        let t = theme(env);
        let size = Layout.captionSize(fit, kindOf(env));
        let lp = Layout.live(fit);
        let k = lp#size / 15.0;
        let live = textAt(lp#x, lp#y, label(StoryDoc.Label.Live, env), fonts#ui, lp#size, { r = 0.95, g = 0.96, b = 1.0 }, zTelop() + 2);
        let liveDot = (RawDraw.circleAt({ x = lp#x - 12.0 * k, y = lp#y + 9.0 * k }, 5.0 * k, { r = 0.9, g = 0.25, b = 0.25 }, zTelop() + 2)
            |> fadeTo(0.5 + 0.5 * Float64.max(0.0, Num.sin(realSeconds(env) * 3.0)))) :: Nil;
        match r#page#current {
            case Some(line) if line#kind == Page.Kind.Caption =>
                let text = Layout.captionText(fit);
                let rows = wrapRowsOf(env, size, text#width, line#text);
                let ground = at(band#position#x, band#position#y, Render.vgrad(band#size, { top = { r = 0.04, g = 0.09, b = 0.2 }, bottom = { r = 0.02, g = 0.04, b = 0.1 } }, zTelop()) |> Render.fade(0.88));
                let rule = at(band#position#x, band#position#y, RawDraw.box({ x = band#size#x, y = 2.0 }, t#water, zTelop() + 1) |> Render.fade(0.7));
                let tag = Layout.captionTag(fit);
                let tagGround = at(tag#position#x, tag#position#y, Render.vgrad(tag#size, { top = { r = 0.2, g = 0.4, b = 0.7 }, bottom = { r = 0.1, g = 0.24, b = 0.5 } }, zTelop() + 1));
                let look = { atlas = fonts#ui, size = size, color = { r = 0.97, g = 0.98, b = 1.0 }, z = zTelop() + 2 };
                let rowH = size * 1.45;
                let top = band#position#y + (band#size#y - Int32.toFloat64(List.length(rows)) * rowH) / 2.0 + 2.0;
                let body = if (line#glitch) glitchRows(rows, { x = text#x, y = top }, rowH, look, env, Page.visibleCount(r#page))
                           else placeRows(rows, { x = text#x, y = top }, rowH, look, Page.visibleCount(r#page));
                List.flatten((ground :: rule :: tagGround :: textIn(tag, label(StoryDoc.Label.NewsTitle, env), fonts#ui, Layout.captionTagTextSize(fit), { r = 1.0, g = 1.0, b = 1.0 }, zTelop() + 2) :: live :: liveDot) :: body :: Nil)
            case _ => live :: liveDot
        }

    // ── 真っ暗・血文字 ──

    /// 真っ暗な画面（UI もボタンも出さない）。血文字を出している間だけ、その字（画像を貼る部品）。
    def darkScreen(fonts: Fonts, env: Env, stage: Stage.Stage): List[Render.PlacedItem] =
        let black = screenBox(env, { r = 0.0, g = 0.0, b = 0.0 }, zGround());
        let scare = Stage.scareShown(env#storyNow, paceOf(env)#scareSeconds, stage) |> Option.map(text -> {
            let since = stage#scare |> Option.map(match (_, shownAt) -> Clock.since(shownAt, env#storyNow)) |> Option.getWithDefault(0.0);
            match imageOf(env, Art.Part.Blood) {
                case Some(name) => bloodImage(env, name)
                case None       => bloodText(fonts, env, text, since)
            }
        }) |> Option.getWithDefault(Nil);
        black :: scare

    /// 血文字の画像。縦の画面は横一列の字を 2 段に切り分けて積む（「ウシロニ」と「イルヨ」）。画像の地は黒なので切り口は見えない。
    def bloodImage(env: Env, name: String): List[Render.PlacedItem] =
        if (not Layout.isPortrait(env#fit)) fullImage(name, 1.0, zScare()) :: Nil
        else {
            let image = fullImage(name, 1.0, zScare()) :: Nil;
            let c = screenCenter(env);
            let w = Layout.width(env#fit);
            let rowOf = (x0: Float64, x1: Float64, top: Float64) -> {
                let crop = { position = { x = x0, y = 160.0 }, size = { x = x1 - x0, y = 240.0 } };
                let k = Float64.min(1.0, (w - 24.0) / crop#size#x);
                let dst = { position = { x = (w - crop#size#x * k) / 2.0, y = top }, size = { x = crop#size#x * k, y = crop#size#y * k } };
                intoFrame(crop, dst, image)
            };
            List.append(rowOf(28.0, 556.0, c#y - 250.0), rowOf(556.0, 936.0, c#y + 10.0))
        }

    /// 血文字の画像が届いていない時の字: 明朝の大きな字に、にじみ（暗い赤のずれた写し）と、字の下から垂れていく筋を描き足す。
    def bloodText(fonts: Fonts, env: Env, text: String, since: Float64): List[Render.PlacedItem] =
        let t = theme(env);
        let size = Float64.min(96.0, (Layout.width(env#fit) - 48.0) / Int32.toFloat64(Int32.max(1, String.length(text))));
        let w = TextDraw.width(text, fonts#mincho, size);
        let mid = screenCenter(env);
        let x0 = mid#x - w / 2.0;
        let y0 = mid#y - size * 0.62;
        let dark = Color.darken(t#blood, 0.45);
        let smear = ((-2.5, 1.0) :: (2.0, -1.5) :: (1.0, 3.0) :: (-1.5, -2.0) :: Nil) |> List.map(match (dx, dy) ->
            textAt(x0 + dx, y0 + dy, text, fonts#mincho, size, dark, zScare()) |> fadeTo(0.55));
        let glow = Render.lightAt({ at = mid, radius = 420.0, color = t#blood, strength = 0.22, z = zScare() });
        let main = textAt(x0, y0, text, fonts#mincho, size, t#blood, zScare() + 1);
        let grow = Curve.pieces((0.0, 0.15) :: (0.4, 0.7) :: (1.0, 1.0) :: Nil, since / Float64.max(0.05, paceOf(env)#scareSeconds));
        let drips = Fx.derive(11, 0.0, (_i, rand, _t) -> {
            let x = x0 + 8.0 + rand(0) * (w - 16.0);
            let top = y0 + size * (0.78 + rand(1) * 0.12);
            let length = (8.0 + rand(2) * rand(2) * 60.0) * grow;
            let width = 1.2 + rand(3) * 2.2;
            (x, top, length, width)
        }) |> List.flatMap(match (x, top, length, width) ->
            RawDraw.lineSeg({ x = x, y = top }, { x = x, y = top + length }, width, t#blood, zScare() + 1)
            :: RawDraw.circleAt({ x = x, y = top + length }, width * 0.9, t#blood, zScare() + 1) :: Nil);
        List.flatten((glow :: Nil) :: smear :: (main :: Nil) :: drips :: Nil)

    // ── 冷え・水滴・地の文の背景（画像を貼る部品と、図形の覆い） ──

    /// 画面の冷え（0〜1）: 青白い覆いと、四隅から寄る翳り。冷えが強いほど画面がかすかに明滅する。
    def chillLayer(env: Env, chill: Float64): List[Render.PlacedItem] =
        if (chill <= 0.001) Nil
        else {
            let t = theme(env);
            let flicker = 1.0 - chill * chill * 0.12 * (0.5 + 0.5 * Num.sin(realSeconds(env) * 9.0 + Num.sin(realSeconds(env) * 2.3) * 3.0));
            let wash = screenGrad(env, { top = Color.cool(t#water, 0.2), bottom = Color.darken(t#water, 0.55) }, zChill()) |> fadeTo(0.3 * chill * flicker);
            let corners = screenCorners(env)
                |> List.map(c -> Render.darkAt({ at = c, radius = 300.0 + 220.0 * chill, strength = 0.7 * chill, z = zChill() + 1 }));
            wash :: corners
        }

    /// 画面の内側の水滴（画像を貼る部品）。start = 付け始めた物語の時刻（付き切るまでは数が増えていく）。
    /// 画像を重ねたうえで、伝い落ちる滴を少しだけ足す（止まった絵にしない）。
    def dropsLayer(env: Env, start: Clock.Time[Stage.Story]): List[Render.PlacedItem] =
        let grown = Num.clamp01(Clock.since(start, env#storyNow) / 2.5);
        match imageOf(env, Art.Part.Drops) {
            case Some(name) => List.append(dropsImage(env, name, 0.9 * grown), drips(env, 10, grown))
            case None       => drips(env, 54, grown)
        }

    /// 水滴の画像。縦の画面は高さに合わせて寄せ、左右を切る。
    // WhyNot: 縦の画面で等倍の絵を縦に積まない — 絵の上下の端に粒が寄っていて、継ぎ目が横の線になって見える。
    def dropsImage(env: Env, name: String, alpha: Float64): List[Render.PlacedItem] =
        landscapeInto(env, Layout.screenCrop(env#fit), Layout.screen(env#fit), fullImage(name, alpha, zDrops()) :: Nil)

    /// 伝い落ちる水滴の粒（番号と実時間だけから導く）。grown = 見えている数の割合。
    def drips(env: Env, count: Int32, grown: Float64): List[Render.PlacedItem] =
        let t = theme(env);
        let shown = Float64.tryToInt32(Float64.floor(Int32.toFloat64(count) * grown)) |> Option.getWithDefault(count);
        Fx.derive(count, realSeconds(env), (i, rand, now) -> {
            let r = 2.5 + rand(0) * rand(0) * 9.0;
            let speed = 2.0 + r * r * 0.35;
            let span = 140.0 + rand(1) * 260.0;
            let slide = Curve.loop(speed, span, now + rand(2) * 40.0);
            let x = rand(3) * Layout.width(env#fit);
            let y = rand(4) * (Layout.height(env#fit) - 80.0) + slide;
            let alpha = 1.0 - Num.clamp01((slide / span - 0.8) * 5.0);
            (i, x, y, r, slide, alpha)
        }) |> List.filter(match (i, _, _, _, _, _) -> i < shown)
           |> List.flatMap(match (_, x, y, r, slide, alpha) ->
            (RawDraw.lineSeg({ x = x, y = y - Float64.min(slide, r * 6.0) }, { x = x, y = y }, r * 0.55, t#water, zDrops()) |> fadeTo(0.12 * alpha))
            :: (RawDraw.ellipseAt({ x = x, y = y }, { x = r, y = r * 1.2 }, Color.darken(t#water, 0.35), zDrops() + 1) |> fadeTo(0.28 * alpha))
            :: (RawDraw.ellipseAt({ x = x, y = y - r * 0.15 }, { x = r * 0.82, y = r * 0.95 }, t#water, zDrops() + 2) |> fadeTo(0.22 * alpha))
            :: (RawDraw.circleAt({ x = x - r * 0.35, y = y - r * 0.45 }, Float64.max(0.8, r * 0.26), { r = 1.0, g = 1.0, b = 1.0 }, zDrops() + 3) |> fadeTo(0.75 * alpha)) :: Nil)

    /// 地の文の層の奥（画像を貼る部品）: 部屋の写真（届いていなければモニターの光が顔のあたりへ落ちる明かり）。水の地の文の後は水浸しの部屋。
    /// 背景なし（Art.Backdrop.Bare）の時は絵を置かない（チャットの UI を沈める幕と、字の後ろの翳りだけが残る）。
    def roomLayer(env: Env, stage: Stage.Stage): List[Render.PlacedItem] =
        let part = if (Stage.isFlooded(stage)) Art.Part.RoomFlooded else Art.Part.Room;
        let picture = if (Art.backdropOf(env#res#art) == Art.Backdrop.Bare) Nil
            else match imageOf(env, part) {
                case Some(name) => fullImage(name, 0.72, zThought() + 1) :: Nil
                case None       => roomDrawn(env, Stage.isFlooded(stage))
            };
        // 字の後ろだけをもう一段沈める（背景なしの時は、透けたチャットと字が重ならないように）。
        Render.darkAt({ at = screenCenter(env), radius = Float64.max(520.0, Layout.height(env#fit) * 0.6), strength = 0.55, z = zThought() + 3 })
            :: landscapeInto(env, Layout.roomCrop(env#fit), Layout.screen(env#fit), picture)

    /// 部屋の画像が届いていない時の明かり: 正面のモニターの青白い光と、手前の机の縁。水浸しなら床に光の揺らめき。
    def roomDrawn(env: Env, flooded: Bool): List[Render.PlacedItem] =
        let t = theme(env);
        let now = realSeconds(env);
        // 光源はモニター（読む人の目の高さ・画面の手前）。顔のあたりから下へ落ちて、部屋の奥は暗いまま。
        let screenGlow = Render.lightAt({ at = { x = 480.0, y = 600.0 }, radius = 620.0, color = Color.cool(t#water, 0.3), strength = 0.26 + Curve.sine(0.025, 2.1, 0.0, now), z = zThought() + 1 });
        let wall = at(0.0, 0.0, Render.gradPolygon(
            { pos = { x = -14.0, y = -14.0 }, color = Color.darken(t#rail, 0.7), alpha = 0.0 } :: { pos = { x = 974.0, y = -14.0 }, color = Color.darken(t#rail, 0.7), alpha = 0.0 } ::
            { pos = { x = 974.0, y = 554.0 }, color = Color.mix(t#water, t#rail, 0.82), alpha = 0.5 } :: { pos = { x = -14.0, y = 554.0 }, color = Color.mix(t#water, t#rail, 0.82), alpha = 0.5 } :: Nil, zThought() + 1));
        let water = if (flooded)
            Fx.derive(18, now, (_i, rand, s) -> (rand(0) * 960.0, 470.0 + rand(1) * 60.0, 30.0 + rand(2) * 90.0, 0.5 + 0.5 * Num.sin(s * (0.8 + rand(3)) + rand(4) * 6.28)))
                |> List.map(match (x, y, w, a) -> RawDraw.lineSeg({ x = x, y = y }, { x = x + w, y = y }, 1.5, t#water, zThought() + 2) |> fadeTo(0.25 * a))
            else Nil;
        List.flatten((wall :: screenGlow :: Nil) :: water :: Nil)

    /// アバター（画像を貼る部品）。cast = None は誰でもない物、impostor = 偽物に入れ替わった後（顔の無いアバターに替える）。
    /// 縁は 3 人の色（偽物も同じ色の縁のまま = 名前だけが同じ別の物）。
    def avatar(fonts: Fonts, env: Env, cast: Option[Talk.Cast], impostor: Bool, center: Vec2.Vec2, diameter: Float64, z: Int32): List[Render.PlacedItem] =
        let t = theme(env);
        let ring = cast |> Option.map(c -> ThemeDoc.castColor(c, env#res#theme)) |> Option.getWithDefault(t#inkDim);
        let rim = RawDraw.circleAt(center, diameter / 2.0 + 2.0, ring, z) |> fadeTo(0.9);
        let part = match cast {
            case Some(c) if not impostor => Art.Part.Avatar(c)
            case _                       => Art.Part.AvatarUnknown
        };
        let face = match imageOf(env, part) {
            case Some(name) =>
                let k = diameter / 128.0;
                at(center#x, center#y, Render.sprite(name, z + 1) |> Render.masked(circlePoly(64.0, { x = 64.0, y = 64.0 }) :: Nil) |> Render.scaled(k)) :: Nil
            case None => avatarDrawn(fonts, env, cast, impostor, center, diameter, z + 1)
        };
        rim :: face

    /// 原点の (c) を中心にした半径 r の円の頂点の列（24 角形）。
    def circlePoly(r: Float64, c: Vec2.Vec2): List[Vec2.Vec2] =
        List.range(0, 24) |> List.map(i -> {
            let a = Int32.toFloat64(i) * Num.pi() * 2.0 / 24.0;
            { x = c#x + r * Num.cos(a), y = c#y + r * Num.sin(a) }
        })

    /// アバターの画像が届いていない時の丸: 色の丸に上からの光と下の翳り、真ん中に名前の頭の字。偽物は灰の丸に何も書かない。
    def avatarDrawn(fonts: Fonts, env: Env, cast: Option[Talk.Cast], impostor: Bool, center: Vec2.Vec2, diameter: Float64, z: Int32): List[Render.PlacedItem] =
        let t = theme(env);
        let base = match cast {
            case Some(c) if not impostor => Color.mix(ThemeDoc.castColor(c, env#res#theme), t#rail, 0.35)
            case _                       => Color.mix(t#inkDim, t#rail, 0.55)
        };
        let r = diameter / 2.0;
        let disc = at(center#x, center#y, Render.gradPolygon(circlePoly(r, { x = 0.0, y = 0.0 }) |> List.map(p ->
            { pos = p, color = if (p#y < 0.0) Color.lighten(base, 0.18 * (0.0 - p#y) / r) else Color.darken(base, 0.35 * p#y / r), alpha = 1.0 }), z));
        // WhyNot: 小さいアバターに照りを描かない — 数 px の楕円は角が立ち、白い染みに見える。
        let shine = if (diameter < 34.0) Nil
                    else (RawDraw.ellipseAt({ x = center#x - r * 0.3, y = center#y - r * 0.45 }, { x = r * 0.36, y = r * 0.14 }, { r = 1.0, g = 1.0, b = 1.0 }, z + 1) |> fadeTo(0.07)) :: Nil;
        let initial = match cast {
            case Some(c) if not impostor =>
                let name = StoryDoc.castName(c, env#res#story);
                TextDraw.centeredAt({ text = String.takeLeft(1, name), atlas = fonts#ui, size = diameter * 0.46, color = Color.lighten(base, 0.75), z = z + 2, center = { x = center#x, y = center#y - 1.0 } }) :: Nil
            case _ =>
                // WhyNot: 偽物のアバターに顔や記号を描かない — 何も無い丸が、名前だけ同じ「誰でもない物」に見える。
                RawDraw.ellipseAt({ x = center#x, y = center#y + r * 0.1 }, { x = r * 0.34, y = r * 0.4 }, Color.darken(base, 0.4), z + 2) :: Nil
        };
        List.flatten((disc :: Nil) :: shine :: initial :: Nil)

    // ── 素材の待ち（ブラウザ版で環境音がまだ届いていない間の暗転） ──

    /// 画面を夜の地の色で覆う（黒へ重ねる・黒のまま・黒から戻す）。黒のまま holdMarkSeconds を過ぎたら右下に待ちの印。
    def holdLayer(env: Env): World.Hold -> List[Render.PlacedItem] = hold ->
        let k = kindOf(env);
        let progress = if (k#holdFadeSeconds <= 0.0) 1.0
                       else Float64.min(1.0, Float64.max(0.0, Clock.since(hold#phaseFrom, env#storyNow) / k#holdFadeSeconds));
        let alpha = match hold#phase {
            case World.HoldPhase.FadingOut => progress
            case World.HoldPhase.Waiting   => 1.0
            case World.HoldPhase.FadingIn  => 1.0 - progress
        };
        let veil = screenBox(env, Color.darken(theme(env)#rail, 0.5), zHold()) |> fadeTo(alpha);
        let marked = hold#phase == World.HoldPhase.Waiting and hold#waited >= k#holdMarkSeconds;
        let mark = if (marked) waitDots(env, { x = Layout.width(env#fit) - 60.0, y = Layout.height(env#fit) - 36.0 }, 1.0, zHoldMark()) else Nil;
        veil :: mark

    /// 待ちの印: 小さな点 3 つが左から順に明滅する（入力中の点と同じ形）。origin = 左の点の中心、scale = 大きさの倍率。
    def waitDots(env: Env, origin: Vec2.Vec2, scale: Float64, z: Int32): List[Render.PlacedItem] =
        let color = theme(env)#accent;
        let t = realSeconds(env);
        List.range(0, 3) |> List.map(i -> {
            let pulse = 0.5 + 0.5 * Num.sin(t * 4.2 - Int32.toFloat64(i) * 0.9);
            RawDraw.circleAt({ x = origin#x + Int32.toFloat64(i) * 14.0 * scale, y = origin#y }, 3.0 * scale, color, z) |> fadeTo(0.2 + 0.8 * pulse * pulse)
        })

    // ── タイトル ──

    def title(fonts: Fonts, env: Env, cursor: World.TitleItem): List[Render.PlacedItem] =
        let t = theme(env);
        let s = StoryDoc.rec(env#res#story);
        let fit = env#fit;
        let picture = landscapeInto(env, Layout.titleCrop(fit), Layout.titlePicture(fit), match imageOf(env, Art.Part.Title) {
            case Some(name) => fullImage(name, 1.0, zGround()) :: Nil
            case None       => titleDrawn(env)
        });
        // WhyNot: 字の下の沈みを矩形で敷かない — 絵の上に箱の縁が線になって残る。左から右へ消えていく面にする。
        let ink = Color.darken(t#rail, 0.55);
        let w = Layout.width(fit);
        let h = Layout.height(fit);
        let center = if (Layout.isSmall(fit) or Layout.isPortrait(fit)) w / 2.0 else 190.0;
        let fadeBand = (x0, x1, a0, a1) -> at(0.0, 0.0, Render.gradPolygon(
            { pos = { x = x0, y = -14.0 }, color = ink, alpha = a0 } :: { pos = { x = x1, y = -14.0 }, color = ink, alpha = a1 } ::
            { pos = { x = x1, y = h + 14.0 }, color = ink, alpha = a1 } :: { pos = { x = x0, y = h + 14.0 }, color = ink, alpha = a0 } :: Nil, zText()));
        // WhyNot: 小さい画面で左寄せの沈みのままにしない — 字の列が画面の中央へ来てモニターの光に重なる。列の真ん中を一番濃くして両脇へ消す。
        let rowBand = (y0, y1, a0, a1) -> at(0.0, 0.0, Render.gradPolygon(
            { pos = { x = -14.0, y = y0 }, color = ink, alpha = a0 } :: { pos = { x = w + 14.0, y = y0 }, color = ink, alpha = a0 } ::
            { pos = { x = w + 14.0, y = y1 }, color = ink, alpha = a1 } :: { pos = { x = -14.0, y = y1 }, color = ink, alpha = a1 } :: Nil, zText()));
        // 縦の画面: 題の後ろの上の暗がりと、絵の下の端からメニューへ溶けていく暗がり。
        let frame = Layout.titlePicture(fit);
        let pictureTop = frame#position#y;
        let pictureBottom = pictureTop + frame#size#y;
        let fall = Float64.min(240.0, frame#size#y * 0.4);
        let shade = if (Layout.isPortrait(fit))
            rowBand(-14.0, Layout.titleWarningY(fit) + 60.0, 0.8, 0.0) :: rowBand(pictureBottom - fall, pictureBottom, 0.0, 1.0)
                :: rowBand(pictureBottom, h + 14.0, 1.0, 1.0) :: rowBand(-14.0, pictureTop, 1.0, 1.0) :: rowBand(pictureTop, pictureTop + 50.0, if (pictureTop > 0.0) 1.0 else 0.0, 0.0) :: Nil
            else if (Layout.isSmall(fit))
            fadeBand(center - 300.0, center, 0.0, 0.9) :: fadeBand(center, center + 300.0, 0.9, 0.0) :: Nil
            else fadeBand(-14.0, 560.0, 0.82, 0.0) :: Nil;
        let floor = at(0.0, 0.0, Render.gradPolygon(
            { pos = { x = -14.0, y = h - 70.0 }, color = ink, alpha = 0.0 } :: { pos = { x = w + 14.0, y = h - 70.0 }, color = ink, alpha = 0.0 } ::
            { pos = { x = w + 14.0, y = h + 14.0 }, color = ink, alpha = 0.85 } :: { pos = { x = -14.0, y = h + 14.0 }, color = ink, alpha = 0.85 } :: Nil, zText()));
        let headSize = Layout.titleHeadingSize(fit);
        let breathe = 0.85 + 0.15 * (0.5 + 0.5 * Num.sin(realSeconds(env) * 0.9));
        let headY = Layout.titleHeadingY(fit);
        let heading = TextDraw.centered({ text = s#title, atlas = fonts#mincho, size = headSize, color = Color.mix(t#thought, t#water, 0.25), z = zText() + 2, centerX = center, y = headY });
        let headShadow = TextDraw.centered({ text = s#title, atlas = fonts#mincho, size = headSize, color = { r = 0.0, g = 0.0, b = 0.0 }, z = zText() + 1, centerX = center + 2.0, y = headY + 3.0 }) |> fadeTo(0.7);
        let headGlow = Render.glowAt({ x = center, y = headY + headSize / 2.0 }, 150.0, t#water, { alpha = 0.12 * breathe, blend = DrawCmd.BlendMode.Add }, zText() + 1);
        let warning = TextDraw.centered({ text = s#warning, atlas = fonts#ui, size = Layout.noteSize(fit), color = Color.mix(t#water, t#inkDim, 0.4), z = zText() + 2, centerX = center, y = Layout.titleWarningY(fit) });
        let placed = WorldMenu.titleItems() |> List.zipWithIndex;
        let count = List.length(placed);
        let items = placed |> List.flatMap(match (i, item) -> {
            let r = Layout.titleItem(fit, i, count);
            let on = item == cursor;
            let color = if (not WorldMenu.isTitleItemOpen(item, env#saves)) Color.mix(t#inkDim, t#rail, 0.5) else if (on) t#ink else t#inkDim;
            let bar = if (on) at(r#position#x + 30.0, r#position#y + r#size#y - 3.0, RawDraw.box({ x = r#size#x - 60.0, y = 1.0 }, t#water, zText() + 2) |> Render.fade(0.7)) :: Nil else Nil;
            textIn(r, label(titleLabel(item), env), fonts#ui, Layout.titleItemTextSize(fit), color, zText() + 2) :: bar
        });
        let hintText = if (Layout.isPortrait(fit)) label(StoryDoc.Label.TapHint, env) else s#hint;
        let hint = TextDraw.centered({ text = hintText, atlas = fonts#ui, size = Layout.noteSize(fit), color = Color.mix(t#inkDim, t#rail, 0.3), z = zText() + 2,
                                       centerX = w / 2.0, y = Layout.titleHintY(fit) });
        List.flatten(picture :: shade :: (floor :: headShadow :: heading :: warning :: hint :: Nil) :: headGlow :: items :: Nil)

    /// タイトルの画像が届いていない時の絵: 暗い部屋の机のモニター。画面に吹き出しがぼやけて浮かび、モニターの縁から水が垂れる。
    def titleDrawn(env: Env): List[Render.PlacedItem] =
        let t = theme(env);
        let now = realSeconds(env);
        let room = wholeGrad({ top = Color.darken(t#rail, 0.55), bottom = Color.darken(t#rail, 0.3) }, zGround());
        let spill = Render.lightAt({ at = { x = 560.0, y = 290.0 }, radius = 520.0, color = Color.cool(t#water, 0.3), strength = 0.32 + Curve.sine(0.03, 1.7, 0.0, now), z = zGround() + 1 });
        let bezel = at(394.0, 178.0, RawDraw.box({ x = 332.0, y = 196.0 }, Color.darken(t#rail, 0.5), zGround() + 2) |> Render.rounded(6.0));
        let screen = at(404.0, 188.0, Render.vgrad({ x = 312.0, y = 176.0 }, { top = Color.mix(t#water, { r = 1.0, g = 1.0, b = 1.0 }, 0.15), bottom = Color.darken(t#water, 0.35) }, zGround() + 3));
        let bubbles = ((428.0, 210.0, 150.0) :: (540.0, 252.0, 150.0) :: (428.0, 294.0, 120.0) :: (520.0, 334.0, 170.0) :: Nil)
            |> List.map(match (x, y, w) -> at(x, y, RawDraw.box({ x = w, y = 26.0 }, { r = 0.92, g = 0.97, b = 1.0 }, zGround() + 4) |> Render.rounded(13.0) |> Render.fade(0.55)));
        let stand = at(0.0, 0.0, RawDraw.polygon({ x = 540.0, y = 374.0 } :: { x = 580.0, y = 374.0 } :: { x = 590.0, y = 426.0 } :: { x = 530.0, y = 426.0 } :: Nil, Color.darken(t#rail, 0.4), zGround() + 2));
        let base = RawDraw.ellipseAt({ x = 560.0, y = 430.0 }, { x = 80.0, y = 9.0 }, Color.darken(t#rail, 0.35), zGround() + 2);
        let desk = at(-14.0, 432.0, Render.vgrad({ x = 988.0, y = 122.0 }, { top = Color.mix(t#water, t#rail, 0.78), bottom = Color.darken(t#rail, 0.6) }, zGround() + 1));
        let reflection = Render.lightAt({ at = { x = 560.0, y = 470.0 }, radius = 260.0, color = t#water, strength = 0.18, z = zGround() + 2 });
        let fall = Fx.derive(7, now, (_i, rand, s) -> {
            let x = 412.0 + rand(0) * 296.0;
            let span = 54.0 + rand(1) * 40.0;
            let y = 374.0 + Curve.loop(22.0 + rand(2) * 30.0, span, s + rand(3) * 9.0);
            (x, y, 1.0 - Num.clamp01((y - 374.0) / span))
        }) |> List.flatMap(match (x, y, a) ->
            (RawDraw.ellipseAt({ x = x, y = y }, { x = 2.2, y = 3.0 }, t#water, zGround() + 5) |> fadeTo(0.7 * a))
            :: (RawDraw.lineSeg({ x = x, y = 374.0 }, { x = x, y = y }, 1.0, t#water, zGround() + 4) |> fadeTo(0.18 * a)) :: Nil);
        List.flatten((room :: spill :: desk :: reflection :: bezel :: screen :: stand :: base :: Nil) :: bubbles :: fall :: Nil)

    pub def titleLabel(item: World.TitleItem): StoryDoc.Label = match item {
        case World.TitleItem.NewGame  => StoryDoc.Label.NewGame
        case World.TitleItem.Continue => StoryDoc.Label.Continue
        case World.TitleItem.LoadGame => StoryDoc.Label.LoadGame
        case World.TitleItem.Settings => StoryDoc.Label.Settings
        case World.TitleItem.Credits  => StoryDoc.Label.Credits
        case World.TitleItem.Quit     => StoryDoc.Label.Quit
    }

    // ── クレジット（実時間で下から上へ流れる） ──

    def credits(fonts: Fonts, env: Env, startedAt: Clock.Time[Clock.Real]): List[Render.PlacedItem] =
        let t = theme(env);
        let scrolled = Clock.since(startedAt, env#realNow) * kindOf(env)#creditsSpeed;
        let screenH = Layout.height(env#fit);
        let ground = screenGrad(env, { top = { r = 0.0, g = 0.0, b = 0.0 }, bottom = Color.darken(t#rail, 0.55) }, zGround());
        let sizes = Layout.creditsSizes(env#fit);
        let (items, _) = CreditsDoc.rec(env#res#credits)#rows |> List.foldLeft((acc, row) -> {
            let (done, y) = acc;
            let (size, color, atlas) = match row#style {
                case CreditsDoc.Style.Heading => (sizes#heading, Color.mix(t#thought, t#water, 0.3), fonts#mincho)
                case CreditsDoc.Style.Body    => (sizes#body, t#ink, fonts#ui)
                case CreditsDoc.Style.Small   => (sizes#small, t#inkDim, fonts#ui)
                case CreditsDoc.Style.Gap     => (0.0, t#ink, fonts#ui)
            };
            let visible = y > -60.0 and y < screenH + 10.0 and size > 0.0;
            let placed = if (visible)
                TextDraw.centered({ text = row#text, atlas = atlas, size = size, color = color, z = zText(),
                                    centerX = Layout.width(env#fit) / 2.0, y = y }) :: done
                else done;
            (placed, y + World.creditsRowHeight(row#style))
        }, (Nil, screenH - scrolled));
        ground :: items

    // ── 画面（バックログ・セーブ・ロード・設定） ──

    /// 開いている画面。サムネはその枠の戻れる所へ戻した画面（WorldRead.screenOf）なので、ここだけ World を使う。
    def panel(res: Res.Res, fonts: Fonts, env: Env, w: World.World): List[Render.PlacedItem] =
        let screenOf = (mark: Saves.Mark) -> World.readOf(WorldRead.screenOf(res, mark, w));
        match w#panel {
            case World.Panel.Closed            => Nil
            case World.Panel.Log(offset)       => logPanel(fonts, env, World.logOf(w), offset)
            case World.Panel.SaveSlots(tab, i) =>
                slotsPanel(fonts, env, StoryDoc.Label.SaveTitle, { tabs = Saves.writableTabs(), tab = tab, cursor = i }, screenOf)
            case World.Panel.LoadSlots(tab, i) =>
                slotsPanel(fonts, env, StoryDoc.Label.LoadTitle, { tabs = Saves.tabs(), tab = tab, cursor = i }, screenOf)
            case World.Panel.Settings(at)      => settingsPanel(fonts, env, at)
            case World.Panel.Menu(at)          => menuPanel(fonts, env, World.readOf(w) |> Option.map(r -> r#playback) |> Option.getWithDefault(World.Playback.Manual), at)
        }

    /// ≡ から開くメニュー: チャットを少し沈め、上の帯の下の右に項目のボタンを縦に並べる。オート・スキップは点いている間は差し色。
    def menuPanel(fonts: Fonts, env: Env, playback: World.Playback, cursor: Int32): List[Render.PlacedItem] =
        let t = theme(env);
        let fit = env#fit;
        let items = WorldMenu.menuItems();
        let count = List.length(items);
        let box = Layout.menuBox(fit, count);
        let shade = screenBox(env, Color.darken(t#rail, 0.5), zPanel()) |> fadeTo(0.55);
        let ground = at(box#position#x, box#position#y,
                        Render.vgrad(box#size, { top = Color.lighten(t#sidebar, 0.04), bottom = Color.darken(t#sidebar, 0.08) }, zPanel() + 1)
                            |> Render.outlineA({ color = Color.mix(t#ink, t#sidebar, 0.7), alpha = 0.6, width = 1.0 }) |> Render.rounded(10.0));
        let size = Layout.menuItemTextSize(fit);
        let rows = items |> List.zipWithIndex |> List.flatMap(match (i, button) -> {
            let r = Layout.menuItem(fit, i, count);
            let on = (button == World.Button.Auto and playback == World.Playback.Auto) or (button == World.Button.Skip and playback == World.Playback.Skip);
            let picked = i == cursor or isOver(r, env);
            let lit = if (picked) at(r#position#x, r#position#y + 2.0, RawDraw.box({ x = r#size#x, y = r#size#y - 4.0 }, Color.lighten(t#sidebar, 0.1), zPanel() + 2) |> Render.rounded(6.0)) :: Nil else Nil;
            let rule = if (i == 0) Nil else at(r#position#x + 12.0, r#position#y, RawDraw.box({ x = r#size#x - 24.0, y = 1.0 }, Color.mix(t#ink, t#sidebar, 0.85), zPanel() + 2)) :: Nil;
            let mark = if (on) RawDraw.circleAt({ x = r#position#x + r#size#x - 24.0, y = r#position#y + r#size#y / 2.0 }, 6.0, t#accent, zPanel() + 3) :: Nil else Nil;
            let color = if (on) t#accent else if (picked) t#ink else Color.mix(t#ink, t#inkDim, 0.4);
            List.flatten(lit :: rule :: mark :: (textAt(r#position#x + 20.0, r#position#y + (r#size#y - size) / 2.0 - 1.0, label(buttonLabel(button), env), fonts#ui, size, color, zPanel() + 3) :: Nil) :: Nil)
        });
        List.flatten((shade :: ground :: Nil) :: rows :: Nil)

    /// 画面の地・左上の見出しと下の線・右上の「戻る」・下の案内（空なら出さない）。
    def panelFrame(fonts: Fonts, heading: String, hint: String, env: Env): List[Render.PlacedItem] =
        let t = theme(env);
        let back = Layout.back(env#fit);
        let h = Layout.heading(env#fit);
        let sizes = Layout.panelText(env#fit);
        let ground = screenGrad(env, { top = Color.darken(t#sidebar, 0.15), bottom = Color.darken(t#rail, 0.3) }, zPanel());
        let rule = at(h#x, Layout.rule(env#fit), RawDraw.box({ x = Layout.width(env#fit) - 2.0 * h#x, y = 1.0 }, t#accent, zPanelText()) |> Render.fade(0.35));
        let hintRow = if (String.isEmpty(hint)) Nil
            else textAt(h#x, Layout.hintY(env#fit) + 6.0, hint, fonts#ui, sizes#hint, Color.mix(t#inkDim, t#sidebar, 0.2), zPanelText()) :: Nil;
        ground :: rule :: textAt(h#x, h#y, heading, fonts#ui, sizes#heading, t#ink, zPanelText())
            :: plate(back, isOver(back, env), env, zPanelText())
            :: textIn(back, label(StoryDoc.Label.Back, env), fonts#ui, Layout.backTextSize(env#fit), if (isOver(back, env)) t#accent else t#ink, zPanelText() + 1)
            :: hintRow

    // ── バックログ（チャットを遡る画面） ──

    /// バックログの字の大きさ。
    def logSize(env: Env): Float64 = Layout.logTextSize(env#fit, kindOf(env))

    /// バックログの 1 行の高さ。Controls がスクロールの量に使う。
    pub def logRowHeight(fit: Layout.Fit, res: Res.Res, w: World.World): Float64 = logRowOf(envOf(fit, res, w))

    def logRowOf(env: Env): Float64 = logSize(env) + kindOf(env)#lineGap + 2.0

    /// 項目の名前の行（発言と字幕だけ）。
    def logNameOf(env: Env, entry: World.Entry): String = match entry {
        case World.Entry.Said(line, _) => WorldRead.speakerName(env#res, line)
        case World.Entry.Joined(_)     => ""
    }

    def entryLine(entry: World.Entry): Page.Line = match entry {
        case World.Entry.Said(line, _) => line
        case World.Entry.Joined(line)  => line
    }

    /// 項目の本文の行。
    def logRows(env: Env, entry: World.Entry): List[String] = wrapRowsOf(env, logSize(env), Layout.logText(env#fit)#width, entryLine(entry)#text)

    /// 1 項目の高さ（名前の行 + 本文の行の数 + 項目の間）。
    def logEntryHeight(env: Env, entry: World.Entry): Float64 =
        let name = if (String.isEmpty(logNameOf(env, entry))) 0.0 else logSize(env) + 6.0;
        name + Int32.toFloat64(List.length(logRows(env, entry))) * logRowOf(env) + 14.0

    /// 項目ごとの (番号, 項目, 上端, 高さ)。新しい項目を下に、遡るほど上（offset 0 = 一番新しい所が一番下に見える）。
    def logPlaced(env: Env, log: List[World.Entry], offset: Float64): List[(Int32, World.Entry, Float64, Float64)] =
        let view = Layout.logView(env#fit);
        let bottom = view#position#y + view#size#y + offset;
        let (rows, _) = log |> List.zipWithIndex |> List.foldLeft((acc, pair) -> {
            let (done, below) = acc;
            let (i, entry) = pair;
            let h = logEntryHeight(env, entry);
            ((i, entry, below - h, h) :: done, below - h)
        }, (Nil, bottom));
        rows

    /// バックログの長さと読む範囲の高さ（UiScroll の勘定へ）。
    pub def logScrollSize(fit: Layout.Fit, res: Res.Res, w: World.World): { contentPx = Float64, viewportPx = Float64 } = scrollSizeOf(envOf(fit, res, w), World.logOf(w))

    def scrollSizeOf(env: Env, log: List[World.Entry]): { contentPx = Float64, viewportPx = Float64 } =
        { contentPx = log |> List.foldLeft((sum, entry) -> sum + logEntryHeight(env, entry), 0.0),
          viewportPx = Layout.logView(env#fit)#size#y }

    /// p の下にある項目の番号（読む範囲の外・戻れない項目は None）。
    pub def logEntryAt(fit: Layout.Fit, res: Res.Res, p: { x = Float64, y = Float64 }, w: World.World): Option[Int32] =
        entryAtOf(p, envOf(fit, res, w), World.logOf(w), WorldLog.offsetOf(w))

    def entryAtOf(p: { x = Float64, y = Float64 }, env: Env, log: List[World.Entry], offset: Float64): Option[Int32] =
        if (not Layout.contains(Layout.logView(env#fit), p)) None
        else logPlaced(env, log, offset) |> List.find(match (_, entry, top, h) -> p#y >= top and p#y < top + h and WorldLog.isJumpable(entry))
                                         |> Option.map(match (i, _, _, _) -> i)

    /// バックログ: チャットの履歴を遡る形（3 人の発言は色の名前、地の文は明朝の薄い字、入退室は小さく）。戻れる行に触れると明るくなる。
    def logPanel(fonts: Fonts, env: Env, log: List[World.Entry], offset: Float64): List[Render.PlacedItem] =
        let t = theme(env);
        let view = Layout.logView(env#fit);
        let text = Layout.logText(env#fit);
        let size = logSize(env);
        let rowH = logRowOf(env);
        let hovered = entryAtOf(env#pointer, env, log, offset);
        // 上の端で切れる項目は出さない（字の頭だけが線のように残る）。下の端は一番新しい項目が必ず収まる。
        let items = logPlaced(env, log, offset) |> List.filter(match (_, _, top, _) -> top >= view#position#y - 1.0 and top < view#position#y + view#size#y)
            |> List.flatMap(match (i, entry, top, h) -> {
                let lit = hovered == Some(i) and i > 0;
                let glow = if (lit) at(view#position#x, top + 2.0,
                                       RawDraw.box({ x = view#size#x, y = h - 6.0 }, Color.lighten(t#sidebar, 0.1), zCard()) |> Render.fade(0.8) |> Render.rounded(4.0)) :: Nil
                           else Nil;
                let line = entryLine(entry);
                let name = logNameOf(env, entry);
                let nameRow = if (String.isEmpty(name)) 0.0 else size + 6.0;
                let nameColor = match line#kind {
                    case Page.Kind.Post(cast) => ThemeDoc.castColor(cast, env#res#theme)
                    case _                    => t#inkDim
                };
                let face = Layout.logAvatar(env#fit);
                let head = match line#kind {
                    case Page.Kind.Post(cast) =>
                        avatar(fonts, env, Some(cast), line#impostor, { x = view#position#x + face#dx, y = top + face#dy }, face#diameter, zPanelText())
                    case _ => Nil
                };
                let nameItem = if (String.isEmpty(name)) Nil else textAt(text#x, top + 6.0, name, fonts#ui, size * 0.9, nameColor, zPanelText()) :: Nil;
                let (atlas, ink) = match line#kind {
                    case Page.Kind.Thought      => (fonts#mincho, Color.mix(t#thought, t#sidebar, 0.25))
                    case Page.Kind.Notice(_, _) => (fonts#ui, t#inkDim)
                    case _                      => (fonts#ui, if (lit) Color.lighten(t#ink, 0.1) else t#ink)
                };
                let body = placeRows(logRows(env, entry), { x = text#x, y = top + 6.0 + nameRow }, rowH, { atlas = atlas, size = size, color = ink, z = zPanelText() }, String.length(line#text));
                List.flatten(glow :: head :: nameItem :: body :: Nil)
            });
        let hint = label(if (Layout.isPortrait(env#fit)) StoryDoc.Label.LogTapHint else StoryDoc.Label.LogHint, env);
        List.flatten(panelFrame(fonts, label(StoryDoc.Label.LogTitle, env), hint, env)
                     :: Render.clippedAll(view, items) :: scrollbar(env, log, offset) :: Nil)

    /// スクロールバー（中身が読む範囲より長い時だけ）。つまみの長さは見えている割合、位置は遡った量。
    def scrollbar(env: Env, log: List[World.Entry], offset: Float64): List[Render.PlacedItem] =
        let t = theme(env);
        let track = Layout.logTrack(env#fit);
        let size = scrollSizeOf(env, log);
        if (size#contentPx <= size#viewportPx) Nil
        else {
            let h = Float64.max(28.0, track#size#y * size#viewportPx / size#contentPx);
            let top = UiScroll.topPx(size, offset) / UiScroll.maxOffsetPx(size);
            let y = track#position#y + (track#size#y - h) * top;
            at(track#position#x, track#position#y, RawDraw.box(track#size, Color.lighten(t#sidebar, 0.12), zPanelText()) |> Render.rounded(2.0))
            :: at(track#position#x, y, RawDraw.box({ x = track#size#x, y = h }, t#accent, zPanelText() + 1) |> Render.fade(0.8) |> Render.rounded(2.0))
            :: Nil
        }

    // ── セーブ・ロード ──

    def tabLabel(tab: Saves.Tab, env: Env): String = match tab {
        case Saves.Tab.Auto        => label(StoryDoc.Label.TabAuto, env)
        case Saves.Tab.Quick       => label(StoryDoc.Label.TabQuick, env)
        case Saves.Tab.Numbered(n) => Int32.toString(n)
    }

    /// 枠の番号の字（ページ 1〜3 は通しの No.、オートとクイックはページの名前と順）。
    def slotNumber(tab: Saves.Tab, i: Int32, env: Env): String = match tab {
        case Saves.Tab.Numbered(n) =>
            let no = (n - 1) * Saves.perPage() + i + 1;
            if (no < 10) "No.0${no}" else "No.${no}"
        case _ => "${tabLabel(tab, env)} ${i + 1}"
    }

    /// セーブ・ロードの画面: 上にページのタブ、2 列 × 3 行の枠。枠はサムネ・番号・保存した日時・場所・発言の頭。
    def slotsPanel(fonts: Fonts, env: Env, heading: StoryDoc.Label, pages: { tabs = List[Saves.Tab], tab = Saves.Tab, cursor = Int32 },
                   screenOf: Saves.Mark -> Option[World.Read]): List[Render.PlacedItem] =
        let t = theme(env);
        let tabs = pages#tabs |> List.zipWithIndex |> List.flatMap(match (j, tab) -> {
            let r = Layout.tab(env#fit, List.length(pages#tabs), j);
            let on = tab == pages#tab;
            let lit = on or isOver(r, env);
            let bar = if (on) at(r#position#x, r#position#y + r#size#y - 2.0, RawDraw.box({ x = r#size#x, y = 2.0 }, t#accent, zPanelText() + 1)) :: Nil else Nil;
            plate(r, lit, env, zPanelText()) :: textIn(r, tabLabel(tab, env), fonts#ui, Layout.tabTextSize(env#fit), if (on) t#accent else if (lit) t#ink else t#inkDim, zPanelText() + 1) :: bar
        });
        let newest = Saves.latest(env#saves);
        let cards = List.range(0, Saves.perPage()) |> List.flatMap(i -> slotCard(fonts, env, pages#tab, i, i == pages#cursor, newest, screenOf));
        // WhyNot: 縦の画面にキーの案内を出さない — 指の端末にキーは無く、タブと × がそのまま押せる。
        let hint = if (Layout.isPortrait(env#fit)) "" else label(StoryDoc.Label.SlotsHint, env);
        List.flatten(panelFrame(fonts, label(heading, env), hint, env) :: tabs :: cards :: Nil)

    def slotCard(fonts: Fonts, env: Env, tab: Saves.Tab, i: Int32, picked: Bool, newest: Option[(Saves.Tab, Int32)],
                 screenOf: Saves.Mark -> Option[World.Read]): List[Render.PlacedItem] =
        let t = theme(env);
        let r = Layout.slot(env#fit, i);
        let lit = picked or isOver(r, env);
        let thumb = Layout.thumb(env#fit, i);
        let tx = thumb#position#x + thumb#size#x + 14.0;
        let textWidth = Layout.slotTextRight(env#fit, i) - tx;
        let y = r#position#y;
        let st = Layout.slotText(env#fit);
        let small = st#small;
        let number = textAt(tx, y + st#numberTop, slotNumber(tab, i, env), fonts#ui, small, if (lit) t#accent else t#inkDim, zPanelText());
        let card = plate(r, lit, env, zCard());
        match Saves.slotOf(tab, i, env#saves) {
            case Some(slot) =>
                let rm = Layout.remove(env#fit, i);
                let removeMark = textIn(rm, "×", fonts#ui, st#place, if (isOver(rm, env)) t#accent else t#inkDim, zPanelText());
                let date = textRight(rm#position#x - 6.0, y + st#numberTop, Saves.dateText(slot#savedAt), fonts#ui, small, t#inkDim, zPanelText());
                let place = textAt(tx, y + st#placeTop, clipTo(textWidth, st#place, fonts#ui, slot#place), fonts#ui, st#place, t#ink, zPanelText());
                let said = if (String.isEmpty(slot#speaker)) slot#excerpt else "${slot#speaker}「${slot#excerpt}」";
                let excerpt = linesWithin(textWidth, small, Layout.slotExcerptRows(env#fit, i), fonts#ui, said) |> List.zipWithIndex
                    |> List.map(match (n, row) -> textAt(tx, y + st#excerptTop + Int32.toFloat64(n) * st#excerptStep, row, fonts#ui, small, Color.mix(t#ink, t#sidebar, 0.2), zPanelText()));
                let badge = if (newest == Some((tab, i))) newBadge(fonts, thumb, env) else Nil;
                List.flatten((card :: number :: removeMark :: date :: place :: excerpt) :: thumbnail(fonts, env, screenOf(slot#mark), thumb) :: badge :: Nil)
            case None =>
                let empty = at(thumb#position#x, thumb#position#y, RawDraw.box(thumb#size, Color.darken(t#sidebar, 0.3), zThumb())
                                   |> Render.outlineA({ color = Color.mix(t#ink, t#sidebar, 0.75), alpha = 0.6, width = 1.0 }));
                // 縦の画面のサムネは細いので、空きの字はサムネの右（場所の行）に置く。
                let emptyText = if (Layout.isPortrait(env#fit)) textAt(tx, y + st#placeTop, label(StoryDoc.Label.EmptySlot, env), fonts#ui, st#place, t#inkDim, zPanelText())
                                else textIn(thumb, label(StoryDoc.Label.EmptySlot, env), fonts#ui, small, t#inkDim, zPanelText());
                card :: number :: empty :: emptyText :: Nil
        }

    /// サムネ: その枠の戻れる所へ戻した画面（WorldRead.screenOf）を、実際の画面と同じ関数で描いて枠の大きさへ縮める（字は読めなくてよい）。
    /// 縮めた画面の中の前後は元の z のまま、枠のカードより手前（zThumb から）へ持ち上げる。
    def thumbnail(fonts: Fonts, env: Env, screen: Option[World.Read], r: Rect2.Rect2): List[Render.PlacedItem] =
        let t = theme(env);
        let away = { pointer = { x = -1.0, y = -1.0 } | env };
        let shown = screen |> Option.map(read -> readingScene(fonts, away, read)) |> Option.getWithDefault(Nil);
        let k = Float64.min(r#size#x / Layout.width(env#fit), r#size#y / Layout.height(env#fit));
        let small = shown |> Render.scaledAllAround(k, { x = 0.0, y = 0.0 }) |> Render.movedAll(r#position)
            |> List.map(Render.overItem(liftedZ(zThumb()))) |> Render.clippedAll(r);
        List.flatten(small :: frameOf(r, Color.mix(t#ink, t#sidebar, 0.6), zThumbTop()) :: Nil)

    /// 絵 1 つの濃さを k 倍に（層ごと出し入れする時。Render.fade は濃さを置き換えるので、層の中の薄い物まで濃くなる）。
    def timesAlpha(k: Float64): Render.Item -> Render.Item = item -> match item {
        case Render.Item.Sprite(x)  => Render.Item.Sprite({ alpha = x#alpha * k | x })
        case Render.Item.Text(x)    => Render.Item.Text({ alpha = x#alpha * k | x })
        case Render.Item.Box(x)     => Render.Item.Box({ alpha = x#alpha * k | x })
        case Render.Item.Poly(x)    => Render.Item.Poly({ alpha = x#alpha * k | x })
        case Render.Item.Shader(x)  => Render.Item.Shader({ alpha = x#alpha * k | x })
        case Render.Item.Scene3d(x) => Render.Item.Scene3d(x)
        case Render.Item.Clipped(c) => Render.Item.Clipped({ inner = timesAlpha(k)(c#inner) | c })
    }

    /// 絵 1 つの重なり順を dz だけ手前へ（Clipped は中身）。
    def liftedZ(dz: Int32): Render.Item -> Render.Item = item -> match item {
        case Render.Item.Sprite(s)  => Render.Item.Sprite({ zIndex = s#zIndex + dz | s })
        case Render.Item.Text(x)    => Render.Item.Text({ zIndex = x#zIndex + dz | x })
        case Render.Item.Box(b)     => Render.Item.Box({ zIndex = b#zIndex + dz | b })
        case Render.Item.Poly(p)    => Render.Item.Poly({ zIndex = p#zIndex + dz | p })
        case Render.Item.Shader(x)  => Render.Item.Shader({ zIndex = x#zIndex + dz | x })
        case Render.Item.Scene3d(x) => Render.Item.Scene3d({ zIndex = x#zIndex + dz | x })
        case Render.Item.Clipped(c) => Render.Item.Clipped({ inner = liftedZ(dz)(c#inner) | c })
    }

    /// 矩形の 1px の縁。
    def frameOf(r: Rect2.Rect2, color: Color, z: Int32): List[Render.PlacedItem] =
        let x = r#position#x;
        let y = r#position#y;
        let w = r#size#x;
        let h = r#size#y;
           at(x, y, RawDraw.box({ x = w, y = 1.0 }, color, z))
        :: at(x, y + h - 1.0, RawDraw.box({ x = w, y = 1.0 }, color, z))
        :: at(x, y, RawDraw.box({ x = 1.0, y = h }, color, z))
        :: at(x + w - 1.0, y, RawDraw.box({ x = 1.0, y = h }, color, z))
        :: Nil

    def newBadge(fonts: Fonts, thumb: Rect2.Rect2, env: Env): List[Render.PlacedItem] =
        let t = theme(env);
        let r = { position = { x = thumb#position#x + 4.0, y = thumb#position#y + 4.0 }, size = { x = 38.0, y = 17.0 } };
        at(r#position#x, r#position#y, RawDraw.box(r#size, t#accent, zThumbTop() + 1) |> Render.rounded(2.0))
        :: textIn(r, label(StoryDoc.Label.NewBadge, env), fonts#ui, 11.0, t#rail, zThumbTop() + 2) :: Nil

    /// 幅 maxWidth に収まるよう末尾を「…」で切る。
    def clipTo(maxWidth: Float64, size: Float64, atlas: FontAtlas, text: String): String =
        if (TextDraw.width(text, atlas, size) <= maxWidth) text
        else {
            let room = maxWidth - TextDraw.width("…", atlas, size);
            def go(n: Int32): String = {
                let head = String.takeLeft(n, text);
                if (n <= 0 or TextDraw.width(head, atlas, size) <= room) "${head}…" else go(n - 1)
            };
            go(String.length(text) - 1)
        }

    /// 幅 maxWidth で折り、rows 行まで（あふれた最後の行は「…」で切る）。
    def linesWithin(maxWidth: Float64, size: Float64, rows: Int32, atlas: FontAtlas, text: String): List[String] =
        def take(n: Int32, rest: String): String = {
            if (n >= String.length(rest) or TextDraw.width(String.takeLeft(n + 1, rest), atlas, size) > maxWidth) String.takeLeft(n, rest)
            else take(n + 1, rest)
        };
        def go(left: Int32, rest: String): List[String] = {
            if (String.isEmpty(rest) or left <= 0) Nil
            else if (left == 1) clipTo(maxWidth, size, atlas, rest) :: Nil
            else {
                let head = take(0, rest);
                let n = Int32.max(1, String.length(head));
                String.takeLeft(n, rest) :: go(left - 1, String.dropLeft(n, rest))
            }
        };
        go(rows, text)

    // ── 設定 ──

    /// 設定: 左の列に文章、右の列に音と画面。スライダー・2 つから選ぶボタン・初期設定に戻す。左下に文字の速さの見本。
    def settingsPanel(fonts: Fonts, env: Env, cursor: World.Setting): List[Render.PlacedItem] =
        let t = theme(env);
        let groups = (0 :: 1 :: Nil) |> List.flatMap(col -> {
            let g = Layout.group(env#fit, col);
            let name = if (col == 0) StoryDoc.Label.GroupText else StoryDoc.Label.GroupSound;
            textAt(g#x, g#y, label(name, env), fonts#ui, Layout.settingText(env#fit)#group, t#accent, zPanelText())
            :: at(g#x, g#y + Layout.settingText(env#fit)#group + 8.0, RawDraw.box({ x = Layout.groupRuleWidth(env#fit), y = 1.0 }, Color.mix(t#ink, t#sidebar, 0.7), zPanelText()) |> Render.fade(0.6)) :: Nil
        });
        let rows = WorldSettings.settings() |> List.zipWithIndex
            |> List.flatMap(match (i, setting) -> settingRow(fonts, env, i, setting, setting == cursor));
        List.flatten(panelFrame(fonts, label(StoryDoc.Label.SettingsTitle, env), "", env) :: groups :: rows :: preview(fonts, env) :: Nil)

    def settingRow(fonts: Fonts, env: Env, i: Int32, setting: World.Setting, picked: Bool): List[Render.PlacedItem] =
        let t = theme(env);
        let config = Saves.configOf(env#saves);
        let fit = env#fit;
        let text = Layout.settingText(fit);
        let row = Layout.settingRow(fit, i);
        let focus = if (picked) at(row#position#x - 8.0, row#position#y, RawDraw.box({ x = 2.0, y = row#size#y }, t#accent, zPanelText())) :: Nil else Nil;
        let name = textAt(row#position#x + 4.0, row#position#y + text#nameTop, label(settingLabel(setting), env), fonts#ui, text#name,
                          if (picked) t#accent else t#ink, zPanelText());
        match setting {
            case World.Setting.Slider(slider) =>
                let range = WorldSettings.rangeOf(slider, env#res#kind);
                let bar = Layout.settingBar(fit, i);
                let v = WorldSettings.levelOf(slider, config);
                let filled = if (range#max > range#min) (v - range#min) / (range#max - range#min) else 0.0;
                let knobX = bar#position#x + bar#size#x * filled;
                List.flatten(focus :: (name ::
                    at(bar#position#x, bar#position#y, RawDraw.box(bar#size, Color.lighten(t#sidebar, 0.18), zPanelText()) |> Render.rounded(3.0))
                    :: at(bar#position#x, bar#position#y, RawDraw.box({ x = bar#size#x * filled, y = bar#size#y }, t#accent, zPanelText() + 1) |> Render.rounded(3.0))
                    :: RawDraw.circleAt({ x = knobX, y = bar#position#y + bar#size#y / 2.0 }, if (picked) 8.0 else 7.0, if (picked) t#accent else t#ink, zPanelText() + 2)
                    :: textRight(row#position#x + row#size#x, row#position#y + text#valueTop, valueText(slider, v, env), fonts#ui, text#value, t#inkDim, zPanelText())
                    :: Nil) :: Nil)
            case World.Setting.Pair(pair) =>
                let chosen = WorldSettings.sideOf(pair, config);
                let (left, right) = WorldSettings.pairLabels(pair);
                let buttons = Layout.sides() |> List.flatMap(side -> {
                    let r = Layout.settingSide(fit, i, side);
                    let on = side == chosen;
                    plate(r, on or isOver(r, env), env, zPanelText())
                    :: textIn(r, label(if (side == Layout.Side.Left) left else right, env), fonts#ui, text#pair, if (on) t#accent else t#inkDim, zPanelText() + 1) :: Nil
                });
                List.flatten(focus :: (name :: Nil) :: buttons :: Nil)
            case World.Setting.Reset =>
                let r = Layout.settingAction(fit, i);
                List.append(focus, plate(r, picked or isOver(r, env), env, zPanelText()) :: textIn(r, label(StoryDoc.Label.Reset, env), fonts#ui, text#action, t#ink, zPanelText() + 1) :: Nil)
        }

    /// 見本: 地の文の速さで見本の文を流し続ける（実時間。読み終えて少し置いてから頭へ戻る）。
    def preview(fonts: Fonts, env: Env): List[Render.PlacedItem] =
        let t = theme(env);
        let r = Layout.preview(env#fit);
        let sample = label(StoryDoc.Label.Preview, env);
        let cps = Saves.configOf(env#saves)#cps;
        let length = Int32.toFloat64(String.length(sample));
        let cycle = length / Float64.max(1.0, cps) + 1.6;
        let elapsed = realSeconds(env) - Float64.floor(realSeconds(env) / cycle) * cycle;
        let visible = if (KindDoc.isNoWait(cps, env#res#kind)) String.length(sample)
                      else Float64.tryToInt32(Float64.floor(elapsed * cps)) |> Option.getWithDefault(0) |> Int32.min(String.length(sample));
        let size = Layout.settingText(env#fit)#preview;
        let rows = wrapRowsOf(env, size, r#size#x - 32.0, sample);
        at(r#position#x, r#position#y,
           Render.vgrad(r#size, { top = Color.darken(t#rail, 0.3), bottom = Color.darken(t#rail, 0.6) }, zCard())
               |> Render.outlineA({ color = t#accent, alpha = 0.35, width = 1.0 }) |> Render.rounded(4.0))
        :: placeRows(rows, { x = r#position#x + 16.0, y = r#position#y + Layout.previewTextInset(env#fit) }, size * 1.6,
                     { atlas = fonts#mincho, size = size, color = t#thought, z = zPanelText() }, visible)

    pub def settingLabel(setting: World.Setting): StoryDoc.Label = match setting {
        case World.Setting.Slider(World.Slider.TextSpeed)      => StoryDoc.Label.TextSpeed
        case World.Setting.Slider(World.Slider.AutoWait)       => StoryDoc.Label.AutoWait
        case World.Setting.Slider(World.Slider.MasterVolume)   => StoryDoc.Label.MasterVolume
        case World.Setting.Slider(World.Slider.AmbienceVolume) => StoryDoc.Label.AmbienceVolume
        case World.Setting.Slider(World.Slider.SeVolume)       => StoryDoc.Label.SeVolume
        case World.Setting.Pair(World.Pair.SkipScope)          => StoryDoc.Label.SkipScope
        case World.Setting.Pair(World.Pair.Display)            => StoryDoc.Label.Display
        case World.Setting.Reset                               => StoryDoc.Label.Reset
    }

    def valueText(slider: World.Slider, v: Float64, env: Env): String =
        let whole = x -> Float64.tryToInt32(Float64.round(x)) |> Option.getWithDefault(0) |> Int32.toString;
        match slider {
            case World.Slider.TextSpeed => if (KindDoc.isNoWait(v, env#res#kind)) "ノーウェイト" else "${whole(v)} 字/秒"
            case World.Slider.AutoWait  => "${Float64.toString(Float64.round(v * 10.0) / 10.0)} 秒"
            case _                      => "${whole(v * 100.0)}%"
        }

    // ── 確認のウィンドウ ──

    def askLayer(fonts: Fonts, env: Env, ask: Option[(World.Ask, World.Answer)]): List[Render.PlacedItem] =
        match ask {
            case None => Nil
            case Some((asked, cursor)) =>
                let t = theme(env);
                let box = Layout.askBox(env#fit);
                let center = box#position#x + box#size#x / 2.0;
                let (question, note) = askText(asked);
                let shade = screenBox(env, Color.darken(t#rail, 0.5), zAsk()) |> fadeTo(0.6);
                let sizes = Layout.askText(env#fit);
                let ground = at(box#position#x, box#position#y,
                                Render.vgrad(box#size, { top = Color.lighten(t#sidebar, 0.05), bottom = t#sidebar }, zAsk() + 1)
                                    |> Render.outlineA({ color = t#accent, alpha = 0.6, width = 1.0 }) |> Render.rounded(6.0));
                let line = TextDraw.centered({ text = label(question, env), atlas = fonts#ui, size = sizes#question, color = t#ink, z = zAsk() + 2,
                                               centerX = center, y = box#position#y + sizes#questionTop });
                let sub = note |> Option.map(n -> TextDraw.centered({ text = label(n, env), atlas = fonts#ui, size = sizes#note, color = t#inkDim,
                                                                       z = zAsk() + 2, centerX = center, y = box#position#y + sizes#noteTop }) :: Nil)
                              |> Option.getWithDefault(Nil);
                let answers = (World.Answer.Yes :: World.Answer.No :: Nil) |> List.flatMap(answer -> {
                    let r = Layout.askButton(env#fit, WorldMenu.sideOf(answer));
                    let on = answer == cursor;
                    plate(r, on, env, zAsk() + 2)
                    :: textIn(r, label(if (answer == World.Answer.Yes) StoryDoc.Label.Yes else StoryDoc.Label.No, env), fonts#ui, Layout.askButtonTextSize(env#fit),
                              if (on) t#accent else t#ink, zAsk() + 3) :: Nil
                });
                List.flatten((shade :: ground :: line :: Nil) :: sub :: answers :: Nil)
        }

    /// 尋ねる言葉と、下に添える注意（進行が失われる時）。
    def askText(ask: World.Ask): (StoryDoc.Label, Option[StoryDoc.Label]) = match ask {
        case World.Ask.Overwrite(_, _) => (StoryDoc.Label.AskOverwrite, None)
        case World.Ask.Delete(_, _)    => (StoryDoc.Label.AskDelete, None)
        case World.Ask.Load(_, _)      => (StoryDoc.Label.AskLoad, Some(StoryDoc.Label.LostNote))
        case World.Ask.QuickLoad       => (StoryDoc.Label.AskLoad, Some(StoryDoc.Label.LostNote))
        case World.Ask.Jump(_)         => (StoryDoc.Label.AskJump, None)
        case World.Ask.ToTitle         => (StoryDoc.Label.AskToTitle, Some(StoryDoc.Label.LostNote))
        case World.Ask.Quit            => (StoryDoc.Label.AskQuit, None)
        case World.Ask.Reset           => (StoryDoc.Label.AskReset, None)
    }

    // ── 知らせ ──

    def toast(fonts: Fonts, env: Env, shown: Option[String]): List[Render.PlacedItem] =
        match shown {
            case Some(text) =>
                let t = theme(env);
                let place = Layout.toast(env#fit);
                let width = TextDraw.width(text, fonts#ui, place#size) + 32.0;
                let r = { position = { x = Layout.width(env#fit) - 32.0 - width, y = place#y }, size = { x = width, y = place#size + 18.0 } };
                at(r#position#x, r#position#y, RawDraw.box(r#size, t#sidebar, zToast()) |> Render.fade(0.92)
                                                   |> Render.outlineA({ color = t#accent, alpha = 0.5, width = 1.0 }) |> Render.rounded(6.0))
                :: textIn(r, text, fonts#ui, place#size, t#ink, zToast() + 1) :: Nil
            case None => Nil
        }
}
