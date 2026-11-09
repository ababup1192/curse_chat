// Layout — 画面の置き場所（design の中の矩形）と、押せる物の字の大きさ。View が描く所と Controls がクリックを当てる所は、
// どちらもここの同じ関数から、同じ Fit を渡して引く（描いた所と押せる所がずれない）。
// 置き場所は「振り付け」なのでコードに置く。本文の字の大きさのような手触りは novel.kind.json、
// 小さい画面（スマホ）の時の大きさは novel.small.json、縦の画面の時の大きさは novel.portrait.json。
//
// チャットの画面（横 960×540）は左から: サーバーの列（rail）・チャンネルの列（sidebar）・会話（feed と下の入力欄）・メンバーの列。
// 上の帯（header）に「#ゲーム部屋」とクイックメニュー。小さい画面ではサーバー・チャンネル・メンバーの列を畳んで会話を広げる。
// 縦の画面（幅 540・高さは起動の時に決まる）はスマホのチャットアプリの形: 上の帯にチャンネル名と人数と ≡、
// 発言の列が画面いっぱい、下に入力欄（ホームバーの上に余白）。列は全部畳み、クイックメニューは ≡ から開く。
// 横の 960×540 で描いた絵（テレビ・タイトル・部屋・水滴・血文字）は、縦の画面では切り抜いて寄せる（*Crop が絵の中の範囲）。
mod Layout {
    use fge::{Display, Rect2, Vec2}

    /// 並べ方の組。Regular = PC・タブレット・デスクトップ版（マウスで押す大きさ）、
    /// Small = 横に持ったスマホ（指で押せる大きさ。大きさは novel.small.json）。どちらも design は 960×540。
    /// Portrait = 縦の design で起動した時（大きさは novel.portrait.json・画面の大きさは起動の時に決まった縦の design）。
    pub enum Fit {
        case Regular
        case Small(SmallScreenDoc.Rec)
        case Portrait(PortraitDoc.Rec, Vec2.Vec2)
    }

    /// 並べ方の組を選ぶ。orientation = design の向き（View は ViewCtx#display#orientation、Controls は Frame#viewport の縦横の形から）、
    /// screen = design の大きさ（View は ViewCtx#visible#size、Controls は Frame#viewport）、sizeClass = 端末の区分。
    /// WhyNot: Medium（タブレット）に Small の組を使わない — 倍率が 1 を超える横持ちなら 960×540 のままでも押せる大きさに近い。
    // WhyNot: 向きだけで Portrait にしない — 画面の大きさが縦長でなければ（読めない・0）、縦の置き場所の計算が崩れる。横の組へ落とす。
    pub def fitOf(sizeClass: Display.SizeClass, orientation: Display.Orientation, screen: Vec2.Vec2,
                  small: SmallScreenDoc.Doc, portrait: PortraitDoc.Doc): Fit =
        if (orientation == Display.Orientation.Portrait and screen#y > screen#x and screen#x > 0.0)
            Fit.Portrait(PortraitDoc.rec(portrait), screen)
        else match sizeClass {
            case Display.SizeClass.Small  => Fit.Small(SmallScreenDoc.rec(small))
            case Display.SizeClass.Medium => Fit.Regular
            case Display.SizeClass.Large  => Fit.Regular
        }

    /// 横の画面の大きさ（project.json の designWidth / designHeight と同じ値）。横で描いた絵の大きさでもある。
    pub def landscapeSize(): Vec2.Vec2 = { x = 960.0, y = 540.0 }

    /// 画面の大きさ（横は 960×540、縦は起動の時に決まった縦の design）。
    pub def size(fit: Fit): Vec2.Vec2 = match fit {
        case Fit.Portrait(_, s) => s
        case _                  => landscapeSize()
    }

    pub def width(fit: Fit): Float64 = size(fit)#x
    pub def height(fit: Fit): Float64 = size(fit)#y

    /// 小さい画面か。
    pub def isSmall(fit: Fit): Bool = match fit {
        case Fit.Small(_) => true
        case _            => false
    }

    /// 縦の画面か。
    pub def isPortrait(fit: Fit): Bool = match fit {
        case Fit.Portrait(_, _) => true
        case _                  => false
    }

    /// サーバー・チャンネル・メンバーの列を畳むか（小さい画面と縦の画面）。
    def isCollapsed(fit: Fit): Bool = match fit {
        case Fit.Regular => false
        case _           => true
    }

    /// 2 つ並べたボタンのどちら側か（確認のウィンドウのはい・いいえ、設定の 2 択）。
    pub enum Side with Eq, ToString {
        case Left
        case Right
    }

    pub def sides(): List[Side] = Side.Left :: Side.Right :: Nil

    /// 左から数えた番号（左 = 0）。
    def columnOf(side: Side): Int32 = match side {
        case Side.Left  => 0
        case Side.Right => 1
    }

    /// side(s) が p を含む側。
    pub def sideAt(r: Side -> Rect2.Rect2, p: { x = Float64, y = Float64 }): Option[Side] =
        sides() |> List.find(side -> contains(r(side), p))

    def rect(x: Float64, y: Float64, w: Float64, h: Float64): Rect2.Rect2 =
        { position = { x = x, y = y }, size = { x = w, y = h } }

    pub def screen(fit: Fit): Rect2.Rect2 = rect(0.0, 0.0, width(fit), height(fit))

    pub def contains(r: Rect2.Rect2, p: { x = Float64, y = Float64 }): Bool =
        p#x >= r#position#x and p#x < r#position#x + r#size#x and p#y >= r#position#y and p#y < r#position#y + r#size#y

    /// 0 から count − 1 のうち、r(i) が p を含む最初の番号。
    pub def hitOf(count: Int32, r: Int32 -> Rect2.Rect2, p: { x = Float64, y = Float64 }): Option[Int32] =
        List.range(0, count) |> List.find(i -> contains(r(i), p))

    /// 横で描いた絵（960×540）の中の範囲 crop を、画面の dst いっぱいに寄せて見せる倍率と範囲。
    /// zoom = 寄せる強さ（1 = dst の幅か高さが絵の幅か高さと同じ）。dst を埋め切れない倍率は埋まるまで上げる。focus = 寄せる中心（絵の中）。
    pub def coverCrop(dst: Vec2.Vec2, focus: Vec2.Vec2, zoom: Float64): Rect2.Rect2 =
        let src = landscapeSize();
        let k = Float64.max(zoom, Float64.max(dst#x / src#x, dst#y / src#y));
        let w = dst#x / k;
        let h = dst#y / k;
        rect(Float64.max(0.0, Float64.min(src#x - w, focus#x - w / 2.0)), Float64.max(0.0, Float64.min(src#y - h, focus#y - h / 2.0)), w, h)

    // ── チャットアプリの枠 ──

    /// サーバーの列（小さい画面・縦の画面は畳む = 幅 0）。
    pub def rail(fit: Fit): Rect2.Rect2 =
        rect(0.0, 0.0, if (isCollapsed(fit)) 0.0 else 58.0, height(fit))

    /// チャンネルの列（小さい画面・縦の画面は畳む）。
    pub def sidebar(fit: Fit): Rect2.Rect2 =
        let r = rail(fit);
        let w = if (isCollapsed(fit)) 0.0 else 170.0;
        rect(r#position#x + r#size#x, 0.0, w, height(fit))

    /// 会話の左端。
    def mainLeft(fit: Fit): Float64 = let s = sidebar(fit); s#position#x + s#size#x

    /// メンバーの列（小さい画面・縦の画面は畳む）。
    pub def members(fit: Fit): Rect2.Rect2 =
        let w = if (isCollapsed(fit)) 0.0 else 164.0;
        rect(width(fit) - w, header(fit)#size#y, w, height(fit) - header(fit)#size#y)

    /// 上の帯（会話とメンバーの上）。高さは小さい画面・縦の画面で押せる高さ。
    pub def header(fit: Fit): Rect2.Rect2 =
        let h = match fit {
            case Fit.Regular        => 46.0
            case Fit.Small(s)       => s#buttonHeight
            case Fit.Portrait(p, _) => p#headerHeight
        };
        rect(mainLeft(fit), 0.0, width(fit) - mainLeft(fit), h)

    /// 縦の画面の上の帯の字: チャンネル名と人数の大きさと、それぞれの上端。
    pub def headerText(fit: Fit): { title = Float64, sub = Float64, titleTop = Float64, subTop = Float64 } = match fit {
        case Fit.Portrait(p, _) =>
            let gap = 8.0;
            let top = (p#headerHeight - p#headerTitleSize - gap - p#headerSubSize) / 2.0;
            { title = p#headerTitleSize, sub = p#headerSubSize, titleTop = top, subTop = top + p#headerTitleSize + gap }
        case Fit.Small(_) => { title = 20.0, sub = 0.0, titleTop = (header(fit)#size#y - 20.0) / 2.0 - 1.0, subTop = 0.0 }
        case Fit.Regular  => { title = 16.0, sub = 0.0, titleTop = (header(fit)#size#y - 16.0) / 2.0 - 1.0, subTop = 0.0 }
    }

    /// 会話の列（履歴・入力中の行・入力欄を含む）。
    pub def chatColumn(fit: Fit): Rect2.Rect2 =
        let top = header(fit)#size#y;
        rect(mainLeft(fit), top, members(fit)#position#x - mainLeft(fit), height(fit) - top)

    /// 下の入力欄（縦の画面はホームバーの上に余白を空ける）。
    pub def input(fit: Fit): Rect2.Rect2 =
        let m = chatColumn(fit);
        match fit {
            case Fit.Portrait(p, _) => rect(16.0, height(fit) - p#homeBarGap - p#inputHeight, width(fit) - 32.0, p#inputHeight)
            case _ =>
                let h = if (isSmall(fit)) 52.0 else 42.0;
                rect(m#position#x + 16.0, height(fit) - 14.0 - h, m#size#x - 32.0, h)
        }

    /// 「○○が入力中…」の行の左上（入力欄のすぐ上）。
    pub def typingRow(fit: Fit): Vec2.Vec2 =
        let i = input(fit);
        let gap = if (isPortrait(fit)) 12.0 else 7.0;
        { x = i#position#x + 4.0, y = i#position#y - typingSize(fit) - gap }

    pub def typingSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 12.0
        case Fit.Small(_)       => 17.0
        case Fit.Portrait(p, _) => p#typingSize
    }

    /// 履歴を描く範囲（上の帯の下から、入力中の行の上まで）。新しい発言は下端にそろえる。
    pub def feed(fit: Fit): Rect2.Rect2 =
        let m = chatColumn(fit);
        let bottom = typingRow(fit)#y - 6.0;
        rect(m#position#x, m#position#y, m#size#x, bottom - m#position#y)

    /// 履歴の 1 行の、アバターの列の幅と大きさ（左端からの字の始まり）。
    pub def avatarSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 36.0
        case Fit.Small(_)       => 44.0
        case Fit.Portrait(p, _) => p#avatarSize
    }

    pub def feedTextLeft(fit: Fit): Float64 = feed(fit)#position#x + 16.0 + avatarSize(fit) + 14.0

    /// 履歴の本文を折り返す幅。
    pub def feedTextWidth(fit: Fit): Float64 = feed(fit)#position#x + feed(fit)#size#x - 20.0 - feedTextLeft(fit)

    /// チャットの本文と名前の字の大きさ（Regular は novel.kind.json のまま）。
    pub def chatSizes(fit: Fit, kind: KindDoc.Rec): { body = Float64, name = Float64 } = match fit {
        case Fit.Regular        => { body = kind#bodySize, name = kind#nameSize }
        case Fit.Small(s)       => { body = s#chatBodySize, name = s#chatNameSize }
        case Fit.Portrait(p, _) => { body = p#chatBodySize, name = p#chatNameSize }
    }

    /// 地の文の字の大きさ。
    pub def thoughtSize(fit: Fit, kind: KindDoc.Rec): Float64 = match fit {
        case Fit.Regular        => kind#thoughtSize
        case Fit.Small(s)       => s#thoughtSize
        case Fit.Portrait(p, _) => p#thoughtSize
    }

    /// 地の文の層でチャットを沈める濃さ（横は chat.pace.json のまま）。
    pub def thoughtDim(fit: Fit, pace: PaceDoc.Rec): Float64 = match fit {
        case Fit.Portrait(p, _) => p#thoughtDim
        case _                  => pace#thoughtDim
    }

    /// 地の文を折り返す幅（画面の真ん中の帯）。
    pub def thoughtWidth(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 640.0
        case Fit.Small(_)       => 820.0
        case Fit.Portrait(_, _) => width(fit) - 88.0
    }

    // ── クイックメニュー（横は上の帯の右・縦は帯の右の ≡ から開くメニュー） ──

    /// i 番目のボタン（count 個を上の帯の右端へ寄せて並べる。縦の画面は ≡ の 1 つ）。
    pub def button(fit: Fit, i: Int32, count: Int32): Rect2.Rect2 =
        let h = header(fit);
        match fit {
            case Fit.Portrait(p, _) =>
                let m = p#menuButtonSize;
                rect(width(fit) - 10.0 - Int32.toFloat64(count - i) * m, (h#size#y - m) / 2.0, m, m)
            case _ =>
                let (w, bh) = match fit {
                    case Fit.Small(s) => (Float64.min(80.0, (h#size#x - 170.0) / Int32.toFloat64(Int32.max(1, count))), s#buttonHeight)
                    case _            => (55.0, 26.0)
                };
                let x0 = width(fit) - 8.0 - Int32.toFloat64(count) * w;
                rect(x0 + Int32.toFloat64(i) * w, (h#size#y - bh) / 2.0, w, bh)
        }

    pub def buttonTextSize(fit: Fit): Float64 = match fit {
        case Fit.Small(s)       => s#buttonTextSize
        case Fit.Portrait(p, _) => p#menuItemTextSize
        case _                  => 12.0
    }

    /// ≡ から開くメニューの 1 項目の高さと字。
    def menuItemHeight(fit: Fit): Float64 = match fit {
        case Fit.Portrait(p, _) => p#menuItemHeight
        case _                  => 40.0
    }

    pub def menuItemTextSize(fit: Fit): Float64 = match fit {
        case Fit.Portrait(p, _) => p#menuItemTextSize
        case _                  => 16.0
    }

    /// ≡ から開くメニューの枠（上の帯のすぐ下・右寄せ）。count = 項目の数。
    pub def menuBox(fit: Fit, count: Int32): Rect2.Rect2 =
        let w = Float64.min(340.0, width(fit) - 32.0);
        rect(width(fit) - 16.0 - w, header(fit)#size#y + 6.0, w, Int32.toFloat64(count) * menuItemHeight(fit) + 16.0)

    /// メニューの i 番目の項目。
    pub def menuItem(fit: Fit, i: Int32, count: Int32): Rect2.Rect2 =
        let box = menuBox(fit, count);
        rect(box#position#x + 8.0, box#position#y + 8.0 + Int32.toFloat64(i) * menuItemHeight(fit), box#size#x - 16.0, menuItemHeight(fit))

    // ── テレビ ──

    /// テレビの映り（画面の中の範囲）。横は画面いっぱい、縦は画面の真ん中より上に 16:9 を寄せて大きく置く。
    pub def tvPicture(fit: Fit): Rect2.Rect2 = match fit {
        case Fit.Portrait(p, _) =>
            let h = tvPictureHeight();
            let below = tvCaptionHeight();
            rect(0.0, Float64.max(p#headerHeight, (height(fit) - h - below) / 2.0), width(fit), h)
        case _ => screen(fit)
    }

    /// 縦の画面のテレビの映りの高さと、その下の字幕の帯の高さ。
    def tvPictureHeight(): Float64 = 440.0

    def tvCaptionHeight(): Float64 = 220.0

    /// テレビの映りに見せる絵の中の範囲（縦はキャスターを真ん中に左右を切る）。
    pub def tvCrop(fit: Fit): Rect2.Rect2 =
        let dst = tvPicture(fit);
        coverCrop(dst#size, { x = 480.0, y = 270.0 }, dst#size#y / landscapeSize()#y)

    /// 字幕の帯（横は画面の下・縦は映りのすぐ下）。
    pub def captionBand(fit: Fit): Rect2.Rect2 = match fit {
        case Fit.Portrait(_, _) =>
            let pic = tvPicture(fit);
            rect(0.0, pic#position#y + pic#size#y, width(fit), tvCaptionHeight())
        case _ => rect(0.0, height(fit) - 120.0, width(fit), 92.0)
    }

    /// 字幕の字の左端と折り返す幅。
    pub def captionText(fit: Fit): { x = Float64, width = Float64 } = match fit {
        case Fit.Portrait(_, _) => { x = 32.0, width = width(fit) - 64.0 }
        case _                  => { x = 60.0, width = captionBand(fit)#size#x - 120.0 }
    }

    /// 字幕の字の大きさ（横は novel.kind.json のまま）。
    pub def captionSize(fit: Fit, kind: KindDoc.Rec): Float64 = match fit {
        case Fit.Portrait(p, _) => p#captionSize
        case _                  => kind#captionSize
    }

    /// 字幕の帯の左上の「ニュース」のラベルと、その字の大きさ。
    pub def captionTag(fit: Fit): Rect2.Rect2 =
        let band = captionBand(fit);
        if (isPortrait(fit)) rect(24.0, band#position#y - 34.0, 132.0, 36.0)
        else rect(40.0, band#position#y - 26.0, 104.0, 28.0)

    pub def captionTagTextSize(fit: Fit): Float64 = if (isPortrait(fit)) 20.0 else 15.0

    /// 「LIVE」の字の左上と大きさ（点はその左）。
    pub def live(fit: Fit): { x = Float64, y = Float64, size = Float64 } =
        if (isPortrait(fit)) { let pic = tvPicture(fit); { x = width(fit) - 92.0, y = pic#position#y + 18.0, size = 20.0 } }
        else { x = 860.0, y = 26.0, size = 15.0 }

    // ── タイトル ──

    /// 題の上端。
    pub def titleHeadingY(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 70.0
        case Fit.Small(_)       => 18.0
        case Fit.Portrait(_, _) => 84.0
    }

    /// 題の字の大きさ。
    pub def titleHeadingSize(fit: Fit): Float64 = match fit {
        case Fit.Regular => 42.0
        case _           => 58.0
    }

    /// 音の注意の上端。
    pub def titleWarningY(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 140.0
        case Fit.Small(_)       => 100.0
        case Fit.Portrait(_, _) => titleHeadingY(fit) + titleHeadingSize(fit) + 26.0
    }

    /// タイトルの音の注意と下の案内、画面の下の案内の字の大きさ。
    pub def noteSize(fit: Fit): Float64 = match fit {
        case Fit.Portrait(p, _) => p#noteSize
        case _                  => 12.0
    }

    /// タイトル画面の下の案内の高さ。
    pub def titleHintY(fit: Fit): Float64 = match fit {
        case Fit.Portrait(p, _) => height(fit) - p#homeBarGap - noteSize(fit) - 8.0
        case _                  => 512.0
    }

    /// i 番目（count 個のうち）のメニューの項目。Regular は左の列（右のモニターの絵に掛けない）、Small は画面の真ん中へ並べる。
    /// Portrait は下の案内の上に積む（上は絵と題）。
    pub def titleItem(fit: Fit, i: Int32, count: Int32): Rect2.Rect2 =
        match fit {
            case Fit.Regular  => rect(85.0, 236.0 + Int32.toFloat64(i) * 38.0, 210.0, 32.0)
            case Fit.Small(s) =>
                let step = s#titleItemHeight + 2.0;
                let total = Int32.toFloat64(count) * step - 2.0;
                let top = (titleWarningY(fit) + 52.0 + titleHintY(fit) - 4.0) / 2.0 - total / 2.0;
                rect(340.0, top + Int32.toFloat64(i) * step, 280.0, s#titleItemHeight)
            case Fit.Portrait(p, _) =>
                let step = p#titleItemHeight + 4.0;
                let top = titleHintY(fit) - 20.0 - Int32.toFloat64(count) * step + 4.0;
                rect((width(fit) - 320.0) / 2.0, top + Int32.toFloat64(i) * step, 320.0, p#titleItemHeight)
        }

    pub def titleItemTextSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 19.0
        case Fit.Small(s)       => s#titleItemTextSize
        case Fit.Portrait(p, _) => p#titleItemTextSize
    }

    /// タイトルの絵を見せる範囲（横は画面いっぱい・縦はメニューの頭まで。下の端は暗がりへ溶かす）。
    /// 縦で題の下にモニターが入り切らない低い画面は、絵を題の下から始める（題をモニターの光に重ねない）。
    pub def titlePicture(fit: Fit): Rect2.Rect2 = match fit {
        case Fit.Portrait(_, _) =>
            let bottom = titleItem(fit, 0, List.length(WorldMenu.titleItems()))#position#y + 60.0;
            let below = titleWarningY(fit) + 30.0;
            let top = if (bottom - below >= 480.0) 0.0 else below;
            rect(0.0, top, width(fit), bottom - top)
        case _ => screen(fit)
    }

    /// タイトルの絵の中で見せる範囲（縦は机のモニターに寄せる。低い画面はモニターが丸ごと入るまで引く）。
    pub def titleCrop(fit: Fit): Rect2.Rect2 =
        if (isPortrait(fit)) {
            let pic = titlePicture(fit);
            coverCrop(pic#size, { x = 485.0, y = 300.0 }, if (pic#position#y > 0.0) 1.0 else 1.25)
        } else rect(0.0, 0.0, 960.0, 540.0)

    /// 地の文の層の奥の部屋の絵の中で見せる範囲（縦は高さに合わせて、机のモニターと椅子へ寄せる）。
    pub def roomCrop(fit: Fit): Rect2.Rect2 = coverCrop(size(fit), { x = 230.0, y = 300.0 }, 1.0)

    /// 画面いっぱいに見せる絵（水滴）の中の範囲（縦は高さに合わせて左右を切る）。
    pub def screenCrop(fit: Fit): Rect2.Rect2 = coverCrop(size(fit), { x = 480.0, y = 300.0 }, 1.0)

    // ── 画面の枠（セーブ・ロード・設定・バックログで同じ） ──

    /// 見出しの左上。
    pub def heading(fit: Fit): { x = Float64, y = Float64 } =
        if (isPortrait(fit)) { x = 32.0, y = back(fit)#position#y + (back(fit)#size#y - panelText(fit)#heading) / 2.0 }
        else { x = 64.0, y = 30.0 }

    /// 見出しの字と下の案内の字の大きさ。
    pub def panelText(fit: Fit): { heading = Float64, hint = Float64 } =
        if (isPortrait(fit)) { heading = 30.0, hint = noteSize(fit) } else { heading = 26.0, hint = 12.0 }

    /// 見出しの下の線の高さ。
    pub def rule(fit: Fit): Float64 = if (isPortrait(fit)) 100.0 else 78.0

    /// 右上の「戻る」。Small・Portrait は見出しの下の線より上に収める。
    pub def back(fit: Fit): Rect2.Rect2 = match fit {
        case Fit.Regular        => rect(800.0, 32.0, 96.0, 32.0)
        case Fit.Small(s)       => rect(780.0, rule(fit) - 4.0 - s#backHeight, 140.0, s#backHeight)
        case Fit.Portrait(p, _) => rect(width(fit) - 32.0 - 132.0, rule(fit) - 16.0 - p#backHeight, 132.0, p#backHeight)
    }

    pub def backTextSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 15.0
        case Fit.Small(s)       => s#backTextSize
        case Fit.Portrait(p, _) => p#backTextSize
    }

    /// 画面の下の案内の高さ（縦はホームバーの上）。
    pub def hintY(fit: Fit): Float64 = match fit {
        case Fit.Portrait(p, _) => height(fit) - p#homeBarGap - noteSize(fit) - 14.0
        case _                  => 508.0
    }

    // ── セーブ・ロード ──

    /// ページのタブ j（左から・count 個のうち）。縦は幅を等分する。
    pub def tab(fit: Fit, count: Int32, j: Int32): Rect2.Rect2 = match fit {
        case Fit.Regular        => rect(64.0 + Int32.toFloat64(j) * 92.0, 90.0, 86.0, 30.0)
        case Fit.Small(s)       => rect(64.0 + Int32.toFloat64(j) * 116.0, rule(fit) + 6.0, 110.0, s#tabHeight)
        case Fit.Portrait(p, _) =>
            let n = Int32.toFloat64(Int32.max(1, count));
            let w = (width(fit) - 64.0 - (n - 1.0) * 6.0) / n;
            rect(32.0 + Int32.toFloat64(j) * (w + 6.0), rule(fit) + 12.0, w, p#tabHeight)
    }

    pub def tabTextSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 15.0
        case Fit.Small(s)       => s#tabTextSize
        case Fit.Portrait(p, _) => p#tabTextSize
    }

    /// 枠の列の数（横は 2 列 × 3 行・縦は 1 列 × 6 行）。上下のキーはこの数だけ枠を動かす。
    pub def slotColumns(fit: Fit): Int32 = if (isPortrait(fit)) 1 else 2

    /// 枠 i。Small・Portrait はタブの下から案内の上までを行の数で分ける。
    pub def slot(fit: Fit, i: Int32): Rect2.Rect2 =
        let columns = slotColumns(fit);
        let rows = Saves.perPage() / columns;
        let col = Int32.remainder(i, columns);
        let row = i / columns;
        let split = () -> {
            let t = tab(fit, 1, 0);
            let first = t#position#y + t#size#y + if (isPortrait(fit)) 12.0 else 6.0;
            let each = (hintY(fit) - 4.0 - first) / Int32.toFloat64(rows);
            (first, each, each - 8.0)
        };
        let (top, step, h) = match fit {
            case Fit.Regular => (132.0, 124.0, 114.0)
            case _           => split()
        };
        if (isPortrait(fit)) rect(32.0, top + Int32.toFloat64(row) * step, width(fit) - 64.0, h)
        else rect(64.0 + Int32.toFloat64(col) * 424.0, top + Int32.toFloat64(row) * step, 408.0, h)

    /// 枠の中のサムネ（画面と同じ縦横の比。枠の高さに合わせる）。
    pub def thumb(fit: Fit, i: Int32): Rect2.Rect2 =
        let s = slot(fit, i);
        let h = if (isPortrait(fit)) s#size#y - 18.0 else Float64.min(96.0, s#size#y - 18.0);
        rect(s#position#x + 9.0, s#position#y + 9.0, h * width(fit) / height(fit), h)

    /// 枠の右上の削除（縦は指で押せる大きさ）。
    pub def remove(fit: Fit, i: Int32): Rect2.Rect2 =
        let s = slot(fit, i);
        if (isPortrait(fit)) { let side = Float64.min(66.0, s#size#y - 8.0); rect(s#position#x + s#size#x - 4.0 - side, s#position#y + 4.0, side, side) }
        else rect(s#position#x + s#size#x - 30.0, s#position#y + 6.0, 24.0, 24.0)

    /// 枠の中の字: 番号・日時・発言の頭の字（small）と場所の字（place）、それぞれの枠の上端からの下がり、発言の頭の行の間隔。
    pub type alias SlotText = { small = Float64, place = Float64, numberTop = Float64, placeTop = Float64, excerptTop = Float64, excerptStep = Float64 }

    pub def slotText(fit: Fit): SlotText = match fit {
        case Fit.Portrait(p, _) => { small = p#slotTextSize, place = p#slotPlaceSize, numberTop = 10.0, placeTop = 38.0, excerptTop = 72.0, excerptStep = p#slotTextSize + 6.0 }
        case _                  => { small = 13.0, place = 16.0, numberTop = 10.0, placeTop = 32.0, excerptTop = 62.0, excerptStep = 19.0 }
    }

    /// 枠 i の発言の頭の行の数（縦は枠の高さに入るだけ・2 行まで）。
    pub def slotExcerptRows(fit: Fit, i: Int32): Int32 =
        if (isPortrait(fit)) {
            let t = slotText(fit);
            let fits = Float64.floor((slot(fit, i)#size#y - t#excerptTop - 4.0) / t#excerptStep) |> Float64.tryToInt32 |> Option.getWithDefault(1);
            Int32.max(1, Int32.min(2, fits))
        } else 2

    /// 枠 i の字の右端（縦は削除のボタンに掛けない）。
    pub def slotTextRight(fit: Fit, i: Int32): Float64 =
        let s = slot(fit, i);
        if (isPortrait(fit)) remove(fit, i)#position#x - 8.0 else s#position#x + s#size#x - 12.0

    // ── バックログ ──

    /// 読む範囲（チャットを遡る画面: アバターの列 + 名前と本文）。
    pub def logView(fit: Fit): Rect2.Rect2 =
        if (isPortrait(fit)) { let top = rule(fit) + 14.0; rect(24.0, top, width(fit) - 60.0, hintY(fit) - 10.0 - top) }
        else rect(64.0, 92.0, 800.0, 404.0)

    /// 本文の列の左端と幅。
    pub def logText(fit: Fit): { x = Float64, width = Float64 } =
        if (isPortrait(fit)) { let v = logView(fit); { x = v#position#x + 62.0, width = v#size#x - 68.0 } }
        else { x = 124.0, width = 720.0 }

    /// アバターの直径と、項目の左上からの中心の位置。
    pub def logAvatar(fit: Fit): { diameter = Float64, dx = Float64, dy = Float64 } =
        if (isPortrait(fit)) { diameter = 44.0, dx = 26.0, dy = 28.0 } else { diameter = 28.0, dx = 22.0, dy = 18.0 }

    /// バックログの本文の字の大きさ（横はチャットの本文と同じ）。
    pub def logTextSize(fit: Fit, kind: KindDoc.Rec): Float64 = match fit {
        case Fit.Portrait(p, _) => p#logTextSize
        case _                  => chatSizes(fit, kind)#body
    }

    /// スクロールバーの溝。
    pub def logTrack(fit: Fit): Rect2.Rect2 =
        if (isPortrait(fit)) { let v = logView(fit); rect(width(fit) - 22.0, v#position#y, 4.0, v#size#y) }
        else rect(884.0, 92.0, 4.0, 404.0)

    // ── 設定（横は 2 列・縦は 1 列） ──

    /// 列 col（0 = 左・1 = 右）の左端。
    def columnX(col: Int32): Float64 = 64.0 + Int32.toFloat64(col) * 432.0

    /// 設定の左の列（文章）に並べる行の数。残りは右の列（音と画面）。縦は同じ数で上の群と下の群に分ける。
    pub def leftColumnRows(): Int32 = 4

    /// 群の見出しの左上（横は列の頭・縦は群の頭）。
    pub def group(fit: Fit, col: Int32): { x = Float64, y = Float64 } =
        if (isPortrait(fit)) {
            if (col == 0) { x = 32.0, y = rule(fit) + 16.0 }
            else { let last = settingRow(fit, leftColumnRows() - 1); { x = 32.0, y = last#position#y + last#size#y + 22.0 } }
        } else { x = columnX(col), y = 92.0 }

    /// 群の見出しの下の線の長さ。
    pub def groupRuleWidth(fit: Fit): Float64 = if (isPortrait(fit)) width(fit) - 64.0 else 400.0

    /// 設定の i 行目（WorldSettings.settings の並び。左の列に leftColumnRows 行、残りは右の列。縦は群の見出しの下に積む）。
    pub def settingRow(fit: Fit, i: Int32): Rect2.Rect2 =
        let left = leftColumnRows();
        let (col, row) = if (i < left) (0, i) else (1, i - left);
        match fit {
            case Fit.Regular  => rect(columnX(col), 126.0 + Int32.toFloat64(row) * 56.0, 400.0, 44.0)
            case Fit.Small(s) => rect(columnX(col), 120.0 + Int32.toFloat64(row) * (s#settingRowHeight + 4.0), 420.0, s#settingRowHeight)
            case Fit.Portrait(p, _) =>
                let g = group(fit, col);
                rect(32.0, g#y + 34.0 + Int32.toFloat64(row) * (p#settingRowHeight + 6.0), width(fit) - 64.0, p#settingRowHeight)
        }

    /// 行の中で、つまみの帯と 2 つから選ぶボタンが始まる所（行の左端から）。
    def settingControlX(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 160.0
        case Fit.Small(_)       => 156.0
        case Fit.Portrait(_, _) => 172.0
    }

    /// 行 i のつまみの帯（左端 = 最小・右端 = 最大）。
    pub def settingBar(fit: Fit, i: Int32): Rect2.Rect2 =
        let r = settingRow(fit, i);
        let w = match fit {
            case Fit.Regular        => 172.0
            case Fit.Small(_)       => 150.0
            case Fit.Portrait(_, _) => 160.0
        };
        rect(r#position#x + settingControlX(fit), r#position#y + (r#size#y - 6.0) / 2.0, w, 6.0)

    /// 行 i のつまみの帯をクリックで受ける範囲（帯より一回り大きい。Small・Portrait は行の高さいっぱい）。
    pub def settingBarReach(fit: Fit, i: Int32): Rect2.Rect2 =
        let bar = settingBar(fit, i);
        let row = settingRow(fit, i);
        match fit {
            case Fit.Regular => rect(bar#position#x - 10.0, bar#position#y - 16.0, bar#size#x + 20.0, bar#size#y + 32.0)
            case _           => rect(bar#position#x - 10.0, row#position#y, bar#size#x + 20.0, row#size#y)
        }

    /// 行 i の 2 つから選ぶボタンの side 側。
    pub def settingSide(fit: Fit, i: Int32, side: Side): Rect2.Rect2 =
        let r = settingRow(fit, i);
        let x = r#position#x + settingControlX(fit);
        let col = Int32.toFloat64(columnOf(side));
        match fit {
            case Fit.Regular        => rect(x + col * 122.0, r#position#y + 6.0, 116.0, 32.0)
            case Fit.Small(_)       => rect(x + col * 134.0, r#position#y, 130.0, r#size#y)
            case Fit.Portrait(_, _) =>
                let w = (r#size#x - settingControlX(fit) - 6.0) / 2.0;
                rect(x + col * (w + 6.0), r#position#y, w, r#size#y)
        }

    /// 押す行（初期設定に戻す）のボタン。
    pub def settingAction(fit: Fit, i: Int32): Rect2.Rect2 =
        let r = settingRow(fit, i);
        match fit {
            case Fit.Regular        => rect(r#position#x, r#position#y + 6.0, 238.0, 32.0)
            case Fit.Small(_)       => rect(r#position#x, r#position#y, 238.0, r#size#y)
            case Fit.Portrait(_, _) => rect(r#position#x, r#position#y, 260.0, r#size#y)
        }

    /// 設定の字: 行の名前・スライダーの値・2 つから選ぶボタン・押す行のボタンの大きさと、名前と値の字の行の上端からの下がり、
    /// 群の見出しと見本の文の字の大きさ。
    pub type alias SettingText = { name = Float64, value = Float64, pair = Float64, action = Float64, nameTop = Float64, valueTop = Float64,
                                   group = Float64, preview = Float64 }

    pub def settingText(fit: Fit): SettingText = match fit {
        case Fit.Regular  => { name = 16.0, value = 14.0, pair = 14.0, action = 15.0, nameTop = 12.0, valueTop = 13.0, group = 14.0, preview = 16.0 }
        case Fit.Small(s) =>
            let top = (s#settingRowHeight - s#settingTextSize) / 2.0;
            { name = s#settingTextSize, value = s#settingTextSize, pair = s#settingTextSize, action = s#settingTextSize, nameTop = top, valueTop = top,
              group = 14.0, preview = 16.0 }
        case Fit.Portrait(p, _) =>
            let top = (p#settingRowHeight - p#settingTextSize) / 2.0;
            { name = p#settingTextSize, value = p#settingTextSize, pair = p#settingTextSize, action = p#settingTextSize, nameTop = top, valueTop = top,
              group = p#settingTextSize, preview = p#settingTextSize }
    }

    /// 文字の速さの見本（横は左の列の下・縦は全部の行の下）。
    pub def preview(fit: Fit): Rect2.Rect2 =
        if (isPortrait(fit)) {
            let last = settingRow(fit, List.length(WorldSettings.settings()) - 1);
            let top = last#position#y + last#size#y + 20.0;
            rect(32.0, top, width(fit) - 64.0, Float64.min(110.0, hintY(fit) - 10.0 - top))
        } else {
            let last = settingRow(fit, leftColumnRows() - 1);
            let top = last#position#y + last#size#y + 20.0;
            rect(64.0, top, 400.0, Float64.min(84.0, hintY(fit) - 10.0 - top))
        }

    /// 見本の文の、見本の枠の上端からの下がり。
    pub def previewTextInset(fit: Fit): Float64 = match fit {
        case Fit.Regular => 18.0
        case _           => 8.0
    }

    // ── 確認のウィンドウ ──

    pub def askBox(fit: Fit): Rect2.Rect2 =
        if (isPortrait(fit)) rect(28.0, height(fit) / 2.0 - 140.0, width(fit) - 56.0, 280.0)
        else rect(270.0, 186.0, 420.0, 168.0)

    /// 左がはい・右がいいえ。Small・Portrait はボタンの下端をウィンドウの下端から上にそろえる。
    pub def askButton(fit: Fit, side: Side): Rect2.Rect2 =
        let box = askBox(fit);
        let col = Int32.toFloat64(columnOf(side));
        match fit {
            case Fit.Regular  => rect(316.0 + col * 172.0, 290.0, 156.0, 40.0)
            case Fit.Small(s) => rect(316.0 + col * 172.0, box#position#y + box#size#y - 10.0 - s#askButtonHeight, 156.0, s#askButtonHeight)
            case Fit.Portrait(p, _) =>
                let w = (box#size#x - 60.0) / 2.0;
                rect(box#position#x + 20.0 + col * (w + 20.0), box#position#y + box#size#y - 20.0 - p#askButtonHeight, w, p#askButtonHeight)
        }

    pub def askButtonTextSize(fit: Fit): Float64 = match fit {
        case Fit.Regular        => 17.0
        case Fit.Small(s)       => s#askButtonTextSize
        case Fit.Portrait(p, _) => p#askButtonTextSize
    }

    /// 問いと注意の字の大きさと、ウィンドウの上端からの下がり。
    pub def askText(fit: Fit): { question = Float64, note = Float64, questionTop = Float64, noteTop = Float64 } = match fit {
        case Fit.Portrait(p, _) => { question = p#askTextSize, note = p#noteSize, questionTop = 48.0, noteTop = 100.0 }
        case _                  => { question = 18.0, note = 13.0, questionTop = 40.0, noteTop = 74.0 }
    }

    // ── 知らせ・クレジット ──

    /// 知らせの上端と字の大きさ（縦は上の帯の下）。
    pub def toast(fit: Fit): { y = Float64, size = Float64 } =
        if (isPortrait(fit)) { y = header(fit)#size#y + 14.0, size = 20.0 } else { y = 58.0, size = 14.0 }

    /// クレジットの見出し・本文・出典の字の大きさ。
    pub def creditsSizes(fit: Fit): { heading = Float64, body = Float64, small = Float64 } = match fit {
        case Fit.Portrait(p, _) => { heading = p#creditsHeadingSize, body = p#creditsBodySize, small = p#creditsSmallSize }
        case _                  => { heading = 26.0, body = 18.0, small = 13.0 }
    }
}
