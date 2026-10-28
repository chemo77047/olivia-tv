sub init()
    m.CW = 360
    m.W = 1800
    m.HDR = 44
    m.RH = 92
    m.ROWS = 7
    m.WIN = 7200
    m.PX = (m.W - m.CW) / m.WIN
    m.rows = m.top.findNode("rows")
    m.nowLine = m.top.findNode("nowLine")
    m.nowLine.height = m.HDR + m.ROWS * m.RH
    hdr = m.top.findNode("hdr")
    hb = hdr.createChild("Rectangle")
    hb.width = m.W
    hb.height = m.HDR - 6
    hb.color = "0x0D2A30FF"
    m.tl = []
    for k = 0 to 3
        lb = hdr.createChild("Label")
        lb.translation = [m.CW + k * 360 + 10, 0]
        lb.width = 340
        lb.height = m.HDR - 6
        lb.vertAlign = "center"
        lb.font = "font:SmallestBoldSystemFont"
        lb.color = "0x99F6E4FF"
        m.tl.Push(lb)
    end for
    m.slots = []
    for i = 0 to m.ROWS - 1
        g = m.rows.createChild("Group")
        g.translation = [0, m.HDR + i * m.RH]
        bg = g.createChild("Rectangle")
        bg.width = m.CW - 6
        bg.height = m.RH - 6
        po = g.createChild("Poster")
        po.translation = [10, (m.RH - 6 - 44) / 2]
        po.width = 72
        po.height = 44
        po.loadWidth = 144
        po.loadHeight = 88
        po.loadDisplayMode = "scaleToFit"
        lb = g.createChild("Label")
        lb.translation = [92, 0]
        lb.width = m.CW - 110
        lb.height = m.RH - 6
        lb.vertAlign = "center"
        lb.wrap = true
        lb.maxLines = 2
        lb.font = "font:SmallestBoldSystemFont"
        lb.color = "0xFFFFFFFF"
        cells = g.createChild("Group")
        cells.translation = [m.CW, 0]
        m.slots.Push({g: g, bg: bg, po: po, lb: lb, cells: cells})
    end for
    m.cache = {}
    m.row = 0
    m.first = 0
    m.prog = -1
    t = nowS()
    m.minWs = t - (t mod 1800)
    m.ws = m.minWs
    m.ft = t
end sub

function nowS() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

function hm(t as integer) as string
    d = CreateObject("roDateTime")
    d.FromSeconds(t)
    d.ToLocalTime()
    h = d.GetHours()
    mi = d.GetMinutes()
    ap = "AM"
    if h >= 12 then ap = "PM"
    h = h mod 12
    if h = 0 then h = 12
    ms = mi.ToStr()
    if mi < 10 then ms = "0" + ms
    return h.ToStr() + ":" + ms + " " + ap
end function

function pStart(p as object) as integer
    return Int(p.playStart)
end function

function pEnd(p as object) as integer
    return Int(p.playStart) + Int(p.playDuration)
end function

function getProgs(ci as integer) as object
    key = ci.ToStr()
    if m.cache.DoesExist(key) then return m.cache[key]
    arr = []
    ch = m.top.content.getChild(ci)
    if ch <> invalid
        for i = 0 to ch.getChildCount() - 1
            p = ch.getChild(i)
            if p.shortDescriptionLine2 <> "noinfo" then arr.Push(p)
        end for
    end if
    m.cache[key] = arr
    return arr
end function

function pickAt(ci as integer, t as integer) as integer
    arr = getProgs(ci)
    for i = 0 to arr.Count() - 1
        if pStart(arr[i]) <= t and pEnd(arr[i]) > t then return i
    end for
    for i = 0 to arr.Count() - 1
        s = pStart(arr[i])
        if s >= t and s < m.ws + m.WIN then return i
    end for
    return -1
end function

function count() as integer
    if m.top.content = invalid then return 0
    return m.top.content.getChildCount()
end function

sub onContent()
    m.cache = {}
    t = nowS()
    m.minWs = t - (t mod 1800)
    m.ws = m.minWs
    m.ft = t
    m.row = 0
    m.first = 0
    m.prog = -1
    if count() > 0 then m.prog = pickAt(0, m.ft)
    render()
end sub

sub onJump()
    n = count()
    if n = 0 then return
    r = m.top.jumpTo
    if r < 0 then r = 0
    if r >= n then r = n - 1
    m.row = r
    m.ft = nowS()
    if m.ft < m.ws then m.ft = m.ws
    m.prog = pickAt(m.row, m.ft)
    render()
end sub

sub moveLeft()
    arr = getProgs(m.row)
    if m.prog > 0 and pEnd(arr[m.prog - 1]) > m.minWs
        m.prog = m.prog - 1
        s = pStart(arr[m.prog])
        if s < m.ws
            m.ws = s - (s mod 1800)
            if m.ws < m.minWs then m.ws = m.minWs
        end if
        m.ft = s
        if m.ft < m.ws then m.ft = m.ws
    else if m.ws > m.minWs
        m.ws = m.ws - 1800
        m.ft = m.ws
        m.prog = pickAt(m.row, m.ft)
    end if
end sub

sub moveRight()
    arr = getProgs(m.row)
    if m.prog >= 0 and m.prog + 1 < arr.Count()
        m.prog = m.prog + 1
        s = pStart(arr[m.prog])
        if s >= m.ws + m.WIN then m.ws = s - (s mod 1800)
        m.ft = s
        if m.ft < m.ws then m.ft = m.ws
    else if m.ws + m.WIN < m.minWs + 86400
        m.ws = m.ws + 1800
        if m.ft < m.ws then m.ft = m.ws
        m.prog = pickAt(m.row, m.ft)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    n = count()
    if n = 0 then return false
    if key = "up"
        m.row = m.row - 1
        if m.row < 0 then m.row = n - 1
        m.prog = pickAt(m.row, m.ft)
    else if key = "down"
        m.row = m.row + 1
        if m.row >= n then m.row = 0
        m.prog = pickAt(m.row, m.ft)
    else if key = "rewind"
        m.row = m.row - m.ROWS
        if m.row < 0 then m.row = 0
        m.prog = pickAt(m.row, m.ft)
    else if key = "fastforward"
        m.row = m.row + m.ROWS
        if m.row >= n then m.row = n - 1
        m.prog = pickAt(m.row, m.ft)
    else if key = "left"
        moveLeft()
    else if key = "right"
        moveRight()
    else if key = "OK"
        m.top.selected = focusInfo()
        return true
    else
        return false
    end if
    render()
    return true
end function

function focusInfo() as object
    p = invalid
    if m.prog >= 0
        arr = getProgs(m.row)
        if m.prog < arr.Count() then p = arr[m.prog]
    end if
    return {ch: m.row, prog: p}
end function

sub addCell(parent as object, s as integer, e as integer, text as string, focused as boolean, onNow as boolean)
    x = Int((s - m.ws) * m.PX)
    w = Int((e - s) * m.PX) - 4
    if w < 4 then w = 4
    r = parent.createChild("Rectangle")
    r.translation = [x, 0]
    r.width = w
    r.height = m.RH - 6
    if focused
        r.color = "0x14B8A6FF"
    else if onNow
        r.color = "0x12403FFF"
    else
        r.color = "0x0D2A30FF"
    end if
    if w > 30
        lb = r.createChild("Label")
        lb.translation = [12, 0]
        lb.width = w - 20
        lb.height = m.RH - 6
        lb.vertAlign = "center"
        lb.wrap = true
        lb.maxLines = 2
        lb.text = text
        if focused
            lb.font = "font:SmallestBoldSystemFont"
            lb.color = "0x071A1EFF"
        else
            lb.font = "font:SmallestSystemFont"
            lb.color = "0xFFFFFFFF"
        end if
    end if
end sub

sub render()
    n = count()
    if m.row < m.first then m.first = m.row
    if m.row >= m.first + m.ROWS then m.first = m.row - m.ROWS + 1
    if m.first < 0 then m.first = 0
    for k = 0 to 3
        m.tl[k].text = hm(m.ws + k * 1800)
    end for
    t = nowS()
    we = m.ws + m.WIN
    if t >= m.ws and t < we
        m.nowLine.translation = [m.CW + Int((t - m.ws) * m.PX), 0]
        m.nowLine.visible = true
    else
        m.nowLine.visible = false
    end if
    for i = 0 to m.ROWS - 1
        sl = m.slots[i]
        ci = m.first + i
        sl.cells.removeChildrenIndex(sl.cells.getChildCount(), 0)
        if ci >= n
            sl.g.visible = false
        else
            ch = m.top.content.getChild(ci)
            sl.g.visible = true
            sl.lb.text = ch.title
            uri = ""
            if ch.hdSmallIconUrl <> invalid then uri = ch.hdSmallIconUrl
            if sl.po.uri <> uri then sl.po.uri = uri
            isRow = (ci = m.row)
            if isRow
                sl.bg.color = "0x134E4AFF"
            else
                sl.bg.color = "0x0D2A30FF"
            end if
            arr = getProgs(ci)
            drawn = 0
            for j = 0 to arr.Count() - 1
                p = arr[j]
                s = pStart(p)
                e = pEnd(p)
                if e > m.ws and s < we
                    x0 = s
                    if x0 < m.ws then x0 = m.ws
                    x1 = e
                    if x1 > we then x1 = we
                    addCell(sl.cells, x0, x1, p.title, isRow and j = m.prog, s <= t and t < e)
                    drawn = drawn + 1
                end if
            end for
            if drawn = 0 then addCell(sl.cells, m.ws, we, "No info", isRow, false)
        end if
    end for
    if n > 0 then m.top.focused = focusInfo()
end sub
