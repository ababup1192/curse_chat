// Page — チャットの履歴と、今出している行（打っている途中の発言・地の文・字幕）の状態（純粋）。
// 1 行はシナリオの台詞 1 つで、どの .yarn の行か（既読の鍵）を持つ。行の種類（Kind）で出す所が違う:
//   Post    … チャットの発言。打っている間（reveal が出し終えるまで）は履歴に入れず、出し終えたら履歴の最後に描く
//   Notice  … 入退室の行（コマンドから。打たずにすぐ履歴へ入る）
//   Thought … 地の文。チャットの上に沈めた層の中央に、続いている地の文をまとめて出す（履歴には入れない）
//   Caption … テレビの字幕（履歴には入れない）
// 次の行を出す時に、今の発言を履歴へ移す（feed）。履歴は feedMax 行まで（古い方から落とす）。
mod Page {
    use fge::{Clock, UiTypewriter}

    /// 行の種類。
    pub enum Kind with Eq, ToString {
        case Post(Talk.Cast)
        case Notice(Talk.Cast, Stage.Presence)
        case Thought
        case Caption
    }

    /// 1 行。text = 出す字、source = .yarn の「ファイル:行」（入退室は空）、glitch = 字が震える、
    /// impostor = 偽物が送った発言（アバターを替える）、gap = 発言の後の間の段、posted = 履歴に入った順の番号（発言の時刻の元）。
    pub type alias Line = { kind = Kind, text = String, source = String, glitch = Bool, impostor = Bool, gap = Talk.Gap, posted = Int32 }

    /// feed = チャットの履歴（古い順。今の発言は入っていない）、current = 打っている途中か出し終えた今の行、reveal = 今の行の文字送り、
    /// shownAt = 今の行を出した物語の時刻、thoughts = 今の地の文の前に続いている地の文（古い順。今の行が地の文の時だけ）、
    /// fading = 直前まで出していた地の文のまとまり（チャットへ戻った時に層を消していく間だけ描く）、count = 履歴に入れた行の数。
    pub type alias Page = {
        feed = List[Line],
        current = Option[Line],
        reveal = UiTypewriter.Reveal,
        shownAt = Clock.Time[Stage.Story],
        thoughts = List[Line],
        fading = List[Line],
        count = Int32
    }

    /// 次の行を出す時の決まり。feedMax = 履歴に残す行の数、now = 物語の時計の今。
    pub type alias Rule = { feedMax = Int32, now = Clock.Time[Stage.Story] }

    pub def empty(): Page =
        { feed = Nil, current = None, reveal = UiTypewriter.done(""), shownAt = Clock.never(), thoughts = Nil, fading = Nil, count = 0 }

    /// 行の種類が発言か。
    pub def isPost(line: Line): Bool = match line#kind {
        case Kind.Post(_) => true
        case _            => false
    }

    pub def isThought(line: Line): Bool = line#kind == Kind.Thought

    /// 発言の話し手（発言でなければ None）。
    pub def castOf(line: Line): Option[Talk.Cast] = match line#kind {
        case Kind.Post(cast)      => Some(cast)
        case Kind.Notice(cast, _) => Some(cast)
        case _                    => None
    }

    /// 履歴の最後に lines を足し、feedMax 行に切り詰める。
    def pushed(feedMax: Int32, lines: List[Line], feed: List[Line]): List[Line] =
        let all = List.append(feed, lines);
        List.drop(Int32.max(0, List.length(all) - feedMax), all)

    /// 今の行が発言なら履歴へ移す。
    def commit(feedMax: Int32, page: Page): List[Line] = match page#current {
        case Some(line) if isPost(line) => pushed(feedMax, line :: Nil, page#feed)
        case _                          => page#feed
    }

    /// 次の行を出す。今の発言は履歴へ移す。地の文が続く間は前の地の文を thoughts に残し、地の文が終わったら fading へ。
    pub def show(rule: Rule, line: Line, page: Page): Page =
        let feed = commit(rule#feedMax, page);
        let block = match page#current {
            case Some(prev) if isThought(prev) => List.append(page#thoughts, prev :: Nil)
            case _                             => Nil
        };
        let numbered = if (isPost(line)) { posted = page#count | line } else line;
        let count = if (isPost(line)) page#count + 1 else page#count;
        if (isThought(line))
            { feed = feed, current = Some(numbered), reveal = UiTypewriter.start(line#text), shownAt = rule#now,
              thoughts = block, fading = Nil, count = count | page }
        else
            { feed = feed, current = Some(numbered), reveal = UiTypewriter.start(line#text), shownAt = rule#now,
              thoughts = Nil, fading = block, count = count | page }

    /// 入退室の行を履歴へすぐ入れる。今の発言は先に履歴へ移し、今の行は無くす（入退室の後は次の行まで何も出していない）。
    pub def notice(rule: Rule, line: Line, page: Page): Page =
        let block = match page#current {
            case Some(prev) if isThought(prev) => List.append(page#thoughts, prev :: Nil)
            case _                             => Nil
        };
        let feed = pushed(rule#feedMax, { posted = page#count | line } :: Nil, commit(rule#feedMax, page));
        { feed = feed, current = None, reveal = UiTypewriter.done(""), shownAt = rule#now, thoughts = Nil,
          fading = block, count = page#count + 1 | page }

    /// 文字送りを dt 秒ぶん進める。
    pub def step(cps: Float64, dt: Float64, page: Page): Page =
        { reveal = UiTypewriter.step(cps = cps, dt, page#reveal) | page }

    /// 今の行を全部出す。
    pub def revealAll(page: Page): Page = { reveal = UiTypewriter.skip(page#reveal) | page }

    /// 今の行を出し終えたか（行が無ければ出し終えている）。
    pub def isDone(page: Page): Bool = UiTypewriter.isDone(page#reveal)

    /// 今の行の見えている字の数。
    pub def visibleCount(page: Page): Int32 = UiTypewriter.visibleCount(page#reveal)

    /// 今打っている発言の話し手（発言を出し終えていれば None）。
    pub def typingOf(page: Page): Option[Talk.Cast] =
        if (isDone(page)) None
        else page#current |> Option.filter(isPost) |> Option.flatMap(castOf)

    /// チャットの履歴に描く行（出し終えた今の発言を最後に足す）。
    pub def shownFeed(page: Page): List[Line] = match page#current {
        case Some(line) if isPost(line) and isDone(page) => List.append(page#feed, line :: Nil)
        case _                                           => page#feed
    }

    /// 地の文の層に出す行（今の地の文と、その前に続いている地の文。今の行が地の文でなければ空）。
    pub def thoughtBlock(page: Page): List[Line] = match page#current {
        case Some(line) if isThought(line) => List.append(page#thoughts, line :: Nil)
        case _                             => Nil
    }
}
