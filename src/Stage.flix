// Stage — 舞台（どの画面か・テレビの映り・環境音の層・画面の冷え・水滴・血文字・揺れ・チャットに居る人）の状態と、
// シナリオのコマンドからの反映のし方（純粋）。シナリオに書けるコマンド（Talk の語彙。check は名前だけを見るので、引数はここが読む）:
//
//   <<chat>> / <<dark>>          画面をチャット・真っ暗（UI もカーソルも消す）に替える
//   <<tv caster|fallen|static>>  画面をテレビのニュースに替える（キャスター・倒れた後・砂嵐）
//   <<join 名>> / <<leave 名>>   名（amanatsu / kaabo / kansai）の入退室（行は World が流し、音は出来事にして鳴らす）
//   <<ambience 名 音量>>         環境音 amb_<名> の層を足す・音量（0〜1。省けば 1）を替える（off で止める）。層は重ねて鳴らす
//   <<silence>>                  環境音の層を全部すぐ止める
//   <<se 名>>                    効果音 se_<名> を 1 回
//   <<chill 目標 秒>>            画面の冷え（0〜1）を秒かけて目標へ
//   <<drops on|off>>             画面の内側に水滴を付ける・消す
//   <<scare 字>>                 真っ暗な画面の中央に字を血文字で一瞬だけ出す（出す秒は chat.pace.json の scareSeconds）
//   <<shake>>                    画面を短く揺らす
//
// 引数の読めないコマンドは Err で返し、World が 1 行知らせて舞台はそのまま続ける（シナリオの書き損じで止めない）。
// セーブから戻る時は YarnRunner.resume が通ったコマンドを全部返すので、同じ applyCue で反映してから settle で
// 演出の途中を終わりの形にする（冷えは目標の値・揺れと血文字は消え・水滴は付き切った形）。
mod Stage {
    use fge::{Clock, Curve, Num, Yarn}

    /// 物語の時計の名前（中身は要らない）。文字送り・<<wait>>・発言の間・冷え・揺れが使い、画面や確認のウィンドウを開くと止まる。
    pub enum Story

    /// 画面。Chat = チャットアプリ、Tv = テレビのニュース、Dark = 真っ暗（UI もボタンも出さない）。
    pub enum Screen with Eq, ToString {
        case Chat
        case Tv
        case Dark
    }

    /// テレビの映り。Caster = キャスターが読んでいる、Fallen = キャスターが倒れた後、Noise = 砂嵐だけ。
    pub enum TvShot with Eq, ToString {
        case Caster
        case Fallen
        case Noise
    }

    /// 入退室。
    pub enum Presence with Eq, ToString {
        case Join
        case Leave
    }

    /// 環境音の層 1 つ。name = <<ambience 名>> の名、volume = 0〜1。
    pub type alias Layer = { name = String, volume = Float64 }

    /// 画面の冷えの移り。base から target へ、at から seconds 秒かけて移る。
    pub type alias Chill = { base = Float64, target = Float64, at = Clock.Time[Story], seconds = Float64 }

    /// コマンド 1 つの意味。
    pub enum Cue {
        case ToScreen(Screen)
        case ToTv(TvShot)
        case Presence(Talk.Cast, Presence)
        case Ambience(String, Option[Float64])
        case Silence
        case Se(String)
        case Chill(Float64, Float64)
        case Drops(Bool)
        case Scare(String)
        case Shake
    }

    /// 舞台。screen = 今の画面、tv / tvFrom = テレビの映りとそれに替えた時刻、ambience = 鳴らしている環境音の層（足した順）、
    /// chill = 画面の冷え、dropsFrom = 水滴を付け始めた時刻（付いていなければ None）、scare = 血文字の字と出した時刻、
    /// shakeFrom = 揺れ始めた時刻、online = チャットに入っている人（入った順）、impostors = 偽物に入れ替わった人。
    pub type alias Stage = {
        screen = Screen,
        tv = TvShot,
        tvFrom = Clock.Time[Story],
        ambience = List[Layer],
        chill = Chill,
        dropsFrom = Option[Clock.Time[Story]],
        scare = Option[(String, Clock.Time[Story])],
        shakeFrom = Option[Clock.Time[Story]],
        online = List[Talk.Cast],
        impostors = List[Talk.Cast]
    }

    /// 物語を始める前の舞台（チャット・音なし・冷えなし・誰も居ない）。
    pub def empty(): Stage =
        { screen = Screen.Chat, tv = TvShot.Caster, tvFrom = Clock.never(), ambience = Nil,
          chill = { base = 0.0, target = 0.0, at = Clock.never(), seconds = 0.0 },
          dropsFrom = None, scare = None, shakeFrom = None, online = Nil, impostors = Nil }

    /// Talk の語彙に載せるコマンドの名前（wait はエンジンが読むので入れない）。
    pub def commandNames(): List[String] =
        "chat" :: "tv" :: "dark" :: "join" :: "leave" :: "ambience" :: "silence" :: "se" :: "chill" :: "drops" :: "scare" :: "shake" :: Nil

    /// 環境音の名前（<<ambience 名>> の名）→ project.json の sounds の名前。
    pub def ambienceSound(name: String): String = "amb_${name}"

    /// コマンドの意味を読む。
    pub def cueOf(command: Yarn.Command): Result[String, Cue] =
        let at = " (${Yarn.sourceText(command#source)})";
        let number = (text: String, what: String) -> Float64.fromString(text) |> Option.toOk("${what}が数でない '${text}'${at}");
        match (command#name, command#args) {
            case ("chat", _)              => Ok(Cue.ToScreen(Screen.Chat))
            case ("dark", _)              => Ok(Cue.ToScreen(Screen.Dark))
            case ("tv", "caster" :: _)    => Ok(Cue.ToTv(TvShot.Caster))
            case ("tv", "fallen" :: _)    => Ok(Cue.ToTv(TvShot.Fallen))
            case ("tv", "static" :: _)    => Ok(Cue.ToTv(TvShot.Noise))
            case ("tv", other :: _)       => Err("知らないテレビの映り '${other}'${at}")
            case ("join", name :: _)      => presenceOf(name, Presence.Join, at)
            case ("leave", name :: _)     => presenceOf(name, Presence.Leave, at)
            case ("ambience", name :: "off" :: _) => Ok(Cue.Ambience(name, None))
            case ("ambience", name :: volume :: _) => number(volume, "<<ambience>> の音量") |> Result.map(v -> Cue.Ambience(name, Some(Num.clamp01(v))))
            case ("ambience", name :: Nil) => Ok(Cue.Ambience(name, Some(1.0)))
            case ("silence", _)           => Ok(Cue.Silence)
            case ("se", name :: _)        => Ok(Cue.Se(name))
            case ("chill", target :: seconds :: _) =>
                forM (t <- number(target, "<<chill>> の目標"); s <- number(seconds, "<<chill>> の秒"))
                yield Cue.Chill(Num.clamp01(t), Float64.max(0.0, s))
            case ("drops", "on" :: _)     => Ok(Cue.Drops(true))
            case ("drops", "off" :: _)    => Ok(Cue.Drops(false))
            case ("scare", text :: _)     => Ok(Cue.Scare(text))
            case ("shake", _)             => Ok(Cue.Shake)
            case (name, _)                => Err("<<${name}>> の引数が足りないか読めない${at}")
        }

    def presenceOf(name: String, presence: Presence, at: String): Result[String, Cue] =
        Talk.castOf(name) |> Option.map(cast -> Cue.Presence(cast, presence)) |> Option.toOk("知らない人 '${name}'${at}")

    /// コマンド 1 つを舞台に反映する（now = 物語の時計の今）。Se は舞台を変えない（音は World が出来事にする）。
    pub def applyCue(now: Clock.Time[Story], cue: Cue, stage: Stage): Stage = match cue {
        case Cue.ToScreen(screen)     => { screen = screen | stage }
        case Cue.ToTv(shot)           => { screen = Screen.Tv, tv = shot, tvFrom = now | stage }
        case Cue.Presence(cast, Presence.Join)  =>
            { online = List.append(List.filter(c -> c != cast, stage#online), cast :: Nil) | stage }
        case Cue.Presence(cast, Presence.Leave) => { online = List.filter(c -> c != cast, stage#online) | stage }
        case Cue.Ambience(name, volume) => { ambience = withLayer(name, volume, stage#ambience) | stage }
        case Cue.Silence              => { ambience = Nil | stage }
        case Cue.Se(_)                => stage
        case Cue.Chill(target, seconds) =>
            { chill = { base = chillAt(now, stage), target = target, at = now, seconds = seconds } | stage }
        case Cue.Drops(true)          => if (Option.nonEmpty(stage#dropsFrom)) stage else { dropsFrom = Some(now) | stage }
        case Cue.Drops(false)         => { dropsFrom = None | stage }
        case Cue.Scare(text)          => { scare = Some((text, now)) | stage }
        case Cue.Shake                => { shakeFrom = Some(now) | stage }
    }

    /// 層の並びに name を volume で足す（同じ名があれば音量だけ替える）。volume が None なら外す。
    def withLayer(name: String, volume: Option[Float64], layers: List[Layer]): List[Layer] = match volume {
        case None    => List.filter(l -> l#name != name, layers)
        case Some(v) =>
            if (List.exists(l -> l#name == name, layers)) List.map(l -> if (l#name == name) { volume = v | l } else l, layers)
            else List.append(layers, { name = name, volume = v } :: Nil)
    }

    /// 話し手が偽物に入れ替わった（#impostor の発言を出した）。
    pub def withImpostor(cast: Talk.Cast, stage: Stage): Stage =
        if (List.memberOf(cast, stage#impostors)) stage else { impostors = cast :: stage#impostors | stage }

    /// 演出の途中を終わりの形にする（セーブから戻った時・描き出しで場面を作る時）。
    pub def settle(stage: Stage): Stage =
        { tvFrom = Clock.never(), chill = { base = stage#chill#target, at = Clock.never() | stage#chill },
          dropsFrom = stage#dropsFrom |> Option.map(_ -> Clock.never()), scare = None, shakeFrom = None | stage }

    /// 今の冷え（0〜1）。目標へなめらかに移る。
    pub def chillAt(now: Clock.Time[Story], stage: Stage): Float64 =
        let c = stage#chill;
        let t = if (c#seconds <= 0.0) 1.0 else Num.clamp01(Clock.since(c#at, now) / c#seconds);
        Num.lerp(c#base, c#target, Curve.pieces((0.0, 0.0) :: (0.5, 0.62) :: (1.0, 1.0) :: Nil, t))

    /// 今出している血文字（出してから seconds 秒の間だけ。それ以外は None）。
    pub def scareShown(now: Clock.Time[Story], seconds: Float64, stage: Stage): Option[String] =
        stage#scare |> Option.flatMap(match (text, at) -> {
            let t = Clock.since(at, now);
            if (t >= 0.0 and t < seconds) Some(text) else None
        })

    /// 揺れのずれ（px）。揺れの長さと幅は novel.kind.json。だんだん収まる。
    pub def shakeOffset(now: Clock.Time[Story], seconds: Float64, px: Float64, stage: Stage): (Float64, Float64) =
        match stage#shakeFrom {
            case None       => (0.0, 0.0)
            case Some(start) =>
                let t = Clock.since(start, now);
                if (t < 0.0 or t >= seconds or seconds <= 0.0) (0.0, 0.0)
                else {
                    let left = 1.0 - t / seconds;
                    (Num.sin(t * 71.0) * px * left, Num.cos(t * 53.0) * px * 0.5 * left)
                }
        }

    /// 水の地の文の後か（水の環境音の層が鳴っている）。部屋の背景を水浸しの方にする。
    pub def isFlooded(stage: Stage): Bool = List.exists(l -> l#name == "water", stage#ambience)
}
