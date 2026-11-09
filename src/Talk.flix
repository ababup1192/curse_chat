// Talk — シナリオ（assets/talk/*.yarn）とコードの繋ぎ。
// 話し手・最初に開くノード・コマンドとタグの名前の正はここ（コマンドの意味は Stage）。bin/fge yarn build の check は
// この語彙を書き出した assets/talk/vocab.json を読む（書き直すのは make talk-vocab。TestDocs が一致を見る）。
//
//   assets/talk/curse_chat.yarn ──bin/fge yarn build assets/talk──▶ assets/talk/dialogue.json ──load──▶ Res#dialogue
mod Talk {
    use fge::{Yarn}

    /// 話し手（シナリオの「amanatsu: 本文」の左）。地の文は話し手を書かない。
    /// Amanatsu / Kaabo / Kansai = チャットの 3 人、Caster = テレビのニュースの字幕（チャットには出ない）。
    pub enum Speaker with Eq, ToString {
        case Amanatsu, Kaabo, Kansai, Caster
    }

    pub def speakers(): List[Speaker] = Speaker.Amanatsu :: Speaker.Kaabo :: Speaker.Kansai :: Speaker.Caster :: Nil

    pub def speakerId(speaker: Speaker): String = match speaker {
        case Speaker.Amanatsu => "amanatsu"
        case Speaker.Kaabo    => "kaabo"
        case Speaker.Kansai   => "kansai"
        case Speaker.Caster   => "caster"
    }

    /// 話し手の id から（地の文の空の id・知らない id は None）。
    pub def speakerOf(id: String): Option[Speaker] = speakers() |> List.find(s -> speakerId(s) == id)

    /// チャットに居る 3 人（入退室の行・メンバーの一覧・アバターの元）。
    pub enum Cast with Eq, Order, ToString {
        case Amanatsu, Kaabo, Kansai
    }

    /// メンバーの一覧に並べる順。
    pub def casts(): List[Cast] = Cast.Amanatsu :: Cast.Kansai :: Cast.Kaabo :: Nil

    pub def castId(cast: Cast): String = match cast {
        case Cast.Amanatsu => "amanatsu"
        case Cast.Kaabo    => "kaabo"
        case Cast.Kansai   => "kansai"
    }

    /// <<join 名>> の名から（知らない名は None）。
    pub def castOf(id: String): Option[Cast] = casts() |> List.find(c -> castId(c) == id)

    /// 話し手がチャットの 3 人なら、その人。
    pub def castOfSpeaker(speaker: Speaker): Option[Cast] = match speaker {
        case Speaker.Amanatsu => Some(Cast.Amanatsu)
        case Speaker.Kaabo    => Some(Cast.Kaabo)
        case Speaker.Kansai   => Some(Cast.Kansai)
        case Speaker.Caster   => None
    }

    /// 自分（入力欄に一字ずつ打つ人）。
    pub def me(): Cast = Cast.Kaabo

    /// コードが開くノード（それ以外はシナリオの <<jump>> で辿る）。
    pub enum Node with Eq, ToString {
        case Opening
    }

    pub def nodeName(node: Node): String = match node {
        case Node.Opening => "Chat"
    }

    /// 発言の後の間の段（#gap の値）。
    pub enum Gap with Eq, ToString {
        case Normal
        case Long
        case Longer
    }

    /// 行のタグから間の段（#gap:long / #gap:longer。無い・知らない値は Normal）。
    pub def gapOf(tags: List[Yarn.Tag]): Gap = match Yarn.tagOf("gap", tags) {
        case Some("long")   => Gap.Long
        case Some("longer") => Gap.Longer
        case _              => Gap.Normal
    }

    /// 字が震える発言か（#glitch）。
    pub def isGlitch(tags: List[Yarn.Tag]): Bool = Option.nonEmpty(Yarn.tagOf("glitch", tags))

    /// この発言から話し手が偽物か（#impostor）。
    pub def isImpostor(tags: List[Yarn.Tag]): Bool = Option.nonEmpty(Yarn.tagOf("impostor", tags))

    pub def dialoguePath(): String = "assets/talk/dialogue.json"

    pub def vocabPath(): String = "assets/talk/vocab.json"

    /// シナリオを読む。読めない・壊れている時はノードの無いシナリオ（World が直し方を語る 1 行を出す）。
    pub def load(): Yarn.Program \ Fs.FileRead = Yarn.loadOr(Yarn.empty(), dialoguePath())

    /// シナリオの話し手・コマンド・タグの語彙（yarn build の検査の元）。
    pub def vocabOf(): Yarn.Vocab =
        { speakers = Yarn.namesOf(speakerId, speakers()),
          nodes = Yarn.namesOf(nodeName, Node.Opening :: Nil),
          tags = ("gap", "long" :: "longer" :: Nil) :: ("glitch", Nil) :: ("impostor", Nil) :: Nil,
          commands = Stage.commandNames() }

    /// 語彙を assets/talk/vocab.json に書く（make talk-vocab）。
    pub def vocab(): Unit \ IO = run { println(if (Yarn.writeVocab(vocabPath(), vocabOf())) "[talk] 語彙を書いた: ${vocabPath()}" else "[talk] 語彙を書けない: ${vocabPath()}") } with Fs.FileWrite.runWithIO
}
