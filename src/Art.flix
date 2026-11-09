// Art — chat.art.json（地の文の層の奥を選ぶ 1 欄）の宣言ドキュメント層と、絵の部品をどの画像から持ってくるか。
// 絵の部品は assets/gpt/ の画像（ChatGPT で作った物）を貼る。字と枠（チャットの UI・字幕・画面の枠）は図形で描く。
// fail-open — 画像がまだ届いていない・読めない部品は、その部品だけ図形とシェーダーで描く（画像が 1 枚も無くても必ず描ける）。
// Doc が読めない・壊れている・知らない綴りのときは defaults。
mod Art {
    use fge::{DocJson, JsonCodec}
    use Util.Json.Json

    /// 画像を貼る絵の部品（画像 1 枚ずつに対応する）。
    pub enum Part with Eq, ToString {
        case Avatar(Talk.Cast)
        case AvatarUnknown
        case Room
        case RoomFlooded
        case Tv
        case TvFallen
        case Drops
        case Blood
        case Title
    }

    /// 地の文の層の奥に絵を置くか。Room = 部屋の画像（届いていなければモニターの光を図形で描く）、
    /// Bare = 絵を一切置かず、チャットの UI そのものを暗く沈めて中央に字を出す（テレビ・暗転・血文字はどちらも同じ）。
    pub enum Backdrop with Eq, ToString {
        case Room
        case Bare
    }

    pub type alias Rec = { version = Int32, backdrop = Backdrop }

    /// 型検査が record を展開しないため、World が持つ Doc は 1 case の enum で包む。
    pub enum Doc(Rec)

    pub def rec(d: Doc): Rec = match d { case Doc.Doc(r) => r }

    pub def path(): String = "assets/chat.art.json"

    pub def defaults(): Doc = Doc.Doc({ version = 2, backdrop = Backdrop.Room })

    pub def backdropOf(d: Doc): Backdrop = rec(d)#backdrop

    /// 地の文の層の奥を差し替えた Doc（描き出しが背景なしの対を撮る）。
    pub def withBackdrop(backdrop: Backdrop, d: Doc): Doc = Doc.Doc({ backdrop = backdrop | rec(d) })

    /// JSON の綴り（"room" / "none"）から。知らない綴りは None。
    pub def backdropFromText(text: String): Option[Backdrop] = match text {
        case "room" => Some(Backdrop.Room)
        case "none" => Some(Backdrop.Bare)
        case _      => None
    }

    pub def fromJson(text: String): Option[Doc] =
        DocJson.decodeObject(fromRoot, text)

    // WhyNot: 知らない欄（古い JSON の variant など）を壊れた Doc として断らない — 読み飛ばせば backdrop は生きたまま使える。
    def fromRoot(root: Map[String, Json]): Doc =
        let d = rec(defaults());
        Doc.Doc({ version = JsonCodec.intOr("version", d#version, root),
                  backdrop = JsonCodec.stringOr("backdrop", "", root) |> backdropFromText |> Option.getWithDefault(d#backdrop) })

    /// path の Doc を読む。読めない・壊れているときは defaults（fail-open）。
    pub def load(p: String): Doc \ Fs.FileRead =
        DocJson.loadOr(fromJson, defaults(), p)

    /// 部品の画像の名前（project.json の textures の name）。
    pub def textureOf(part: Part): String = match part {
        case Part.Avatar(cast)  => "gpt_avatar_${Talk.castId(cast)}"
        case Part.AvatarUnknown => "gpt_avatar_unknown"
        case Part.Room          => "gpt_bg_room"
        case Part.RoomFlooded   => "gpt_bg_room_flooded"
        case Part.Tv            => "gpt_tv_news"
        case Part.TvFallen      => "gpt_tv_news_fallen"
        case Part.Drops         => "gpt_water_drops"
        case Part.Blood         => "gpt_blood_text"
        case Part.Title         => "gpt_title"
    }

    /// 全部の部品（project.json の textures と揃っているかをテストが見る）。
    pub def parts(): List[Part] =
        List.append(Talk.casts() |> List.map(Part.Avatar),
                    Part.AvatarUnknown :: Part.Room :: Part.RoomFlooded :: Part.Tv :: Part.TvFallen :: Part.Drops :: Part.Blood :: Part.Title :: Nil)

    /// 部品を貼る画像の名前。画像がまだ届いていない（missing）なら None（その部品は図形で描く）。
    pub def imageOf(missing: Set[String], part: Part): Option[String] =
        let name = textureOf(part);
        if (Set.memberOf(name, missing)) None else Some(name)
}
