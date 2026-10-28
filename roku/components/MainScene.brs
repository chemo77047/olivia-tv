sub init()
    m.guide = m.top.findNode("guide")
    m.grid = m.top.findNode("grid")
    m.sectionLabel = m.top.findNode("sectionLabel")
    m.clock = m.top.findNode("clock")
    m.sTitle = m.top.findNode("sTitle")
    m.sTime = m.top.findNode("sTime")
    m.sDesc = m.top.findNode("sDesc")
    m.emptyLabel = m.top.findNode("emptyLabel")
    m.player = m.top.findNode("player")
    m.video = m.top.findNode("video")
    m.banner = m.top.findNode("banner")
    m.bLogo = m.top.findNode("bLogo")
    m.bName = m.top.findNode("bName")
    m.bNow = m.top.findNode("bNow")
    m.bNext = m.top.findNode("bNext")
    m.bClock = m.top.findNode("bClock")
    m.status = m.top.findNode("status")
    m.menu = m.top.findNode("menu")
    m.menuList = m.top.findNode("menuList")
    m.info = m.top.findNode("info")
    m.iTitle = m.top.findNode("iTitle")
    m.iChan = m.top.findNode("iChan")
    m.iTime = m.top.findNode("iTime")
    m.iDesc = m.top.findNode("iDesc")
    m.iButtons = m.top.findNode("iButtons")
    m.toast = m.top.findNode("toast")
    m.loading = m.top.findNode("loading")
    m.tuneTimer = m.top.findNode("tuneTimer")
    m.bannerTimer = m.top.findNode("bannerTimer")
    m.toastTimer = m.top.findNode("toastTimer")
    m.clockTimer = m.top.findNode("clockTimer")

    m.mode = "guide"
    m.content = invalid
    m.focusChannel = 0
    m.playIndex = -1
    m.streamIdx = 0
    m.skips = 0
    m.dir = 1
    m.firstLoad = true
    m.tuning = false
    m.section = "all"
    m.kb = invalid
    m.infoChannel = -1
    m.infoProgram = invalid
    m.favs = regJson("favs")
    m.failed = regJson("failed")

    m.sections = [["fav", "Favorites"], ["kids", "Kids"], ["mx", "México"], ["es", "Español (US)"], ["us", "US"], ["all", "All Channels"]]

    m.grid.observeField("programFocused", "onProgramFocused")
    m.grid.observeField("programSelected", "onProgramSelected")
    m.menuList.observeField("itemSelected", "onMenuSelected")
    m.iButtons.observeField("itemSelected", "onInfoButton")
    m.video.observeField("state", "onVideoState")
    m.tuneTimer.observeField("fire", "onTuneTimeout")
    m.bannerTimer.observeField("fire", "hideBanner")
    m.toastTimer.observeField("fire", "hideToast")
    m.clockTimer.observeField("fire", "updateClock")
    m.clockTimer.control = "start"
    updateClock()

    m.task = CreateObject("roSGNode", "DataTask")
    m.task.observeField("status", "onTaskStatus")
    m.task.observeField("result", "onResult")
    m.task.control = "RUN"
    m.top.setFocus(true)
end sub

' ---------- storage ----------

function regJson(key as string) as object
    sec = CreateObject("roRegistrySection", "oliviatv")
    if sec.Exists(key)
        v = ParseJson(sec.Read(key))
        if type(v) = "roAssociativeArray" then return v
    end if
    return {}
end function

sub regWrite(key as string, value as string)
    sec = CreateObject("roRegistrySection", "oliviatv")
    sec.Write(key, value)
    sec.Flush()
end sub

function regStr(key as string) as string
    sec = CreateObject("roRegistrySection", "oliviatv")
    if sec.Exists(key) then return sec.Read(key)
    return ""
end function

function nowSecs() as integer
    return CreateObject("roDateTime").AsSeconds()
end function

' ---------- time text ----------

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

function dayKey(t as integer) as integer
    d = CreateObject("roDateTime")
    d.FromSeconds(t)
    d.ToLocalTime()
    return d.GetDayOfMonth()
end function

function timeRange(p as object) as string
    s = Int(p.playStart)
    e = s + Int(p.playDuration)
    text = hm(s) + " - " + hm(e)
    if s > nowSecs() and dayKey(s) <> dayKey(nowSecs()) then text = "Tomorrow " + text
    return text
end function

function isNoInfo(p as object) as boolean
    return p <> invalid and p.shortDescriptionLine2 = "noinfo"
end function

function isOnNow(p as object) as boolean
    if p = invalid then return false
    t = nowSecs()
    s = Int(p.playStart)
    return s <= t and t < s + Int(p.playDuration)
end function

sub updateClock()
    t = hm(nowSecs())
    m.clock.text = t
    m.bClock.text = t
end sub

' ---------- data ----------

sub onTaskStatus()
    if m.task.status = "ready" then requestSection("start", "")
end sub

sub requestSection(key as string, query as string)
    m.loading.text = "Loading channels..."
    m.loading.visible = true
    m.task.request = {section: key, query: query, n: nowSecs() + Rnd(100000)}
end sub

function sectionName(key as string) as string
    if key = "search" then return "Search"
    for each s in m.sections
        if s[0] = key then return s[1]
    end for
    return "All Channels"
end function

sub onResult()
    root = m.task.result
    if root = invalid then return
    m.loading.visible = false
    m.content = root
    m.section = root.section
    count = root.getChildCount()
    lbl = sectionName(m.section)
    if m.section = "search" then lbl = "Search: " + root.query
    m.sectionLabel.text = lbl + "  ·  " + count.ToStr() + " channels"
    t = nowSecs()
    m.grid.contentStartTime = t - (t mod 1800)
    m.grid.content = root
    m.focusChannel = 0
    m.emptyLabel.visible = (count = 0)
    if count = 0
        if m.section = "fav"
            m.emptyLabel.text = "No favorites yet. Press * on a channel to add it."
        else
            m.emptyLabel.text = "No channels found."
        end if
        m.sTitle.text = ""
        m.sTime.text = ""
        m.sDesc.text = ""
    end if
    if m.firstLoad
        m.firstLoad = false
        idx = findChannel(regStr("last"))
        if idx >= 0
            m.grid.jumpToChannel = idx
            m.focusChannel = idx
            startChannel(idx, 1, true)
            return
        end if
    end if
    showGuide()
end sub

function findChannel(cid as string) as integer
    if cid = "" or m.content = invalid then return -1
    n = m.content.getChildCount()
    for i = 0 to n - 1
        if m.content.getChild(i).cid = cid then return i
    end for
    return -1
end function

' ---------- guide ----------

sub showGuide()
    m.mode = "guide"
    m.player.visible = false
    m.menu.visible = false
    m.info.visible = false
    m.guide.visible = true
    if m.content <> invalid and m.content.getChildCount() > 0
        m.grid.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

sub onProgramFocused()
    d = m.grid.programFocusedDetails
    if d = invalid or m.content = invalid then return
    ci = d.focusChannelIndex
    if ci = invalid then return
    ch = m.content.getChild(ci)
    if ch = invalid then return
    m.focusChannel = ci
    p = invalid
    if d.focusIndex <> invalid then p = ch.getChild(d.focusIndex)
    if p = invalid or isNoInfo(p)
        m.sTitle.text = ch.title
        m.sTime.text = "No guide info for this channel"
        m.sDesc.text = ""
        return
    end if
    m.sTitle.text = p.title
    t = timeRange(p)
    if p.shortDescriptionLine1 <> invalid and p.shortDescriptionLine1 <> "" then t = t + "  ·  " + p.shortDescriptionLine1
    if isOnNow(p) then t = "On now  ·  " + t
    m.sTime.text = t + "  ·  " + ch.title
    m.sDesc.text = p.description
end sub

sub onProgramSelected()
    d = m.grid.programFocusedDetails
    if d = invalid or m.content = invalid then return
    ci = d.focusChannelIndex
    if ci = invalid then return
    ch = m.content.getChild(ci)
    if ch = invalid then return
    p = invalid
    if d.focusIndex <> invalid then p = ch.getChild(d.focusIndex)
    if p = invalid or isNoInfo(p) or isOnNow(p)
        startChannel(ci, 1, true)
    else
        openInfo(ci, p)
    end if
end sub

' ---------- show info ----------

sub openInfo(ci as integer, p as object)
    ch = m.content.getChild(ci)
    m.infoChannel = ci
    m.infoProgram = p
    m.iTitle.text = p.title
    m.iChan.text = ch.title
    t = timeRange(p)
    if p.shortDescriptionLine1 <> invalid and p.shortDescriptionLine1 <> "" then t = t + "  ·  " + p.shortDescriptionLine1
    m.iTime.text = t
    desc = p.description
    if desc = invalid or desc = "" then desc = "No description available."
    m.iDesc.text = desc
    m.iButtons.content = listContent(["Watch channel", favLabel(ch.cid), "Close"])
    m.iButtons.jumpToItem = 0
    m.mode = "info"
    m.info.visible = true
    m.iButtons.setFocus(true)
end sub

function favLabel(cid as string) as string
    if m.favs.DoesExist(cid) then return "Remove from Favorites"
    return "Add to Favorites"
end function

function listContent(items as object) as object
    root = CreateObject("roSGNode", "ContentNode")
    for each it in items
        c = root.createChild("ContentNode")
        c.title = it
    end for
    return root
end function

sub onInfoButton()
    i = m.iButtons.itemSelected
    ci = m.infoChannel
    if i = 0
        m.info.visible = false
        startChannel(ci, 1, true)
    else if i = 1
        toggleFav(ci)
        m.iButtons.content = listContent(["Watch channel", favLabel(m.content.getChild(ci).cid), "Close"])
        m.iButtons.jumpToItem = 1
    else
        showGuide()
    end if
end sub

' ---------- favorites ----------

sub toggleFav(ci as integer)
    if m.content = invalid then return
    ch = m.content.getChild(ci)
    if ch = invalid then return
    cid = ch.cid
    if m.favs.DoesExist(cid)
        m.favs.Delete(cid)
        showToast(ch.title + " removed from Favorites")
    else
        m.favs[cid] = true
        showToast(ch.title + " added to Favorites")
    end if
    regWrite("favs", FormatJson(m.favs))
end sub

sub showToast(text as string)
    m.toast.text = text
    m.toast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub hideToast()
    m.toast.visible = false
end sub

' ---------- menu ----------

sub openMenu()
    items = []
    for each s in m.sections
        items.Push(s[1])
    end for
    items.Push("Search channels")
    if m.content <> invalid and m.content.getChild(m.focusChannel) <> invalid
        ch = m.content.getChild(m.focusChannel)
        if m.favs.DoesExist(ch.cid)
            items.Push("Remove " + ch.title + " from Favorites")
        else
            items.Push("Add " + ch.title + " to Favorites")
        end if
    end if
    m.menuList.content = listContent(items)
    sel = 0
    for i = 0 to m.sections.Count() - 1
        if m.sections[i][0] = m.section then sel = i
    end for
    m.menuList.jumpToItem = sel
    m.mode = "menu"
    m.menu.visible = true
    m.menuList.setFocus(true)
end sub

sub onMenuSelected()
    i = m.menuList.itemSelected
    n = m.sections.Count()
    if i < n
        m.menu.visible = false
        m.mode = "guide"
        requestSection(m.sections[i][0], "")
    else if i = n
        m.menu.visible = false
        openSearch()
    else
        toggleFav(m.focusChannel)
        m.menu.visible = false
        if m.section = "fav"
            requestSection("fav", "")
        else
            showGuide()
        end if
    end if
end sub

' ---------- search ----------

sub openSearch()
    m.mode = "search"
    kb = CreateObject("roSGNode", "StandardKeyboardDialog")
    kb.title = "Search channels"
    kb.message = ["Type part of a channel name"]
    kb.buttons = ["Search", "Cancel"]
    kb.observeField("buttonSelected", "onSearchButton")
    kb.observeField("wasClosed", "onSearchClosed")
    m.kb = kb
    m.top.dialog = kb
end sub

sub onSearchButton()
    kb = m.kb
    if kb = invalid then return
    q = kb.text.Trim()
    pressed = kb.buttonSelected
    m.kb = invalid
    kb.close = true
    if pressed = 0 and q <> ""
        m.mode = "guide"
        requestSection("search", q)
    else
        showGuide()
    end if
end sub

sub onSearchClosed()
    if m.kb <> invalid
        m.kb = invalid
        showGuide()
    end if
end sub

' ---------- player ----------

sub startChannel(index as integer, dir as integer, fresh as boolean)
    if m.content = invalid then return
    n = m.content.getChildCount()
    if n = 0 then return
    if index < 0 then index = n - 1
    if index >= n then index = 0
    if fresh then m.skips = 0
    m.playIndex = index
    m.dir = dir
    m.streamIdx = 0
    m.mode = "player"
    m.guide.visible = false
    m.menu.visible = false
    m.info.visible = false
    m.player.visible = true
    m.top.setFocus(true)
    showBanner()
    playStream()
end sub

sub playStream()
    ch = m.content.getChild(m.playIndex)
    streams = ch.streams
    if streams = invalid or m.streamIdx >= streams.Count()
        channelFailed()
        return
    end if
    s = streams[m.streamIdx]
    c = CreateObject("roSGNode", "ContentNode")
    c.url = s.u
    c.title = ch.title
    c.live = true
    if Instr(1, LCase(s.u), ".mp4") > 0
        c.streamFormat = "mp4"
    else
        c.streamFormat = "hls"
    end if
    headers = []
    if s.ua <> invalid then headers.Push("User-Agent:" + s.ua)
    if s.ref <> invalid then headers.Push("Referer:" + s.ref)
    if headers.Count() > 0 then c.HttpHeaders = headers
    m.status.text = "Tuning..."
    m.status.visible = true
    m.tuning = true
    m.video.control = "stop"
    m.video.content = c
    m.video.control = "play"
    m.tuneTimer.control = "stop"
    m.tuneTimer.control = "start"
end sub

sub onVideoState()
    if m.mode <> "player" then return
    st = m.video.state
    if st = "playing"
        m.tuneTimer.control = "stop"
        m.status.visible = false
        m.tuning = false
        m.skips = 0
        ch = m.content.getChild(m.playIndex)
        if m.failed.DoesExist(ch.cid)
            m.failed.Delete(ch.cid)
            regWrite("failed", FormatJson(m.failed))
        end if
        regWrite("last", ch.cid)
    else if st = "error" or (st = "finished" and m.tuning = true)
        nextStream()
    end if
end sub

sub onTuneTimeout()
    if m.mode = "player" and m.tuning = true then nextStream()
end sub

sub nextStream()
    m.tuneTimer.control = "stop"
    m.streamIdx = m.streamIdx + 1
    ch = m.content.getChild(m.playIndex)
    limit = ch.streams.Count()
    if limit > 3 then limit = 3
    if m.streamIdx < limit
        playStream()
    else
        channelFailed()
    end if
end sub

sub channelFailed()
    ch = m.content.getChild(m.playIndex)
    m.failed[ch.cid] = nowSecs()
    regWrite("failed", FormatJson(m.failed))
    m.skips = m.skips + 1
    if m.skips >= 8 or m.content.getChildCount() < 2
        m.video.control = "stop"
        m.tuning = false
        m.status.text = "This channel isn't working right now. Press OK for the guide."
        m.status.visible = true
        return
    end if
    showToast(ch.title + " isn't working, skipping")
    startChannel(m.playIndex + m.dir, m.dir, false)
end sub

sub showBanner()
    ch = m.content.getChild(m.playIndex)
    m.bName.text = ch.title
    m.bLogo.uri = ""
    if ch.hdSmallIconUrl <> invalid then m.bLogo.uri = ch.hdSmallIconUrl
    nowP = invalid
    nextP = invalid
    t = nowSecs()
    n = ch.getChildCount()
    for i = 0 to n - 1
        p = ch.getChild(i)
        if not isNoInfo(p)
            s = Int(p.playStart)
            if s <= t and t < s + Int(p.playDuration)
                nowP = p
            else if s > t and nextP = invalid
                nextP = p
            end if
        end if
    end for
    if nowP <> invalid
        m.bNow.text = "Now:  " + nowP.title + "   (" + timeRange(nowP) + ")"
    else
        m.bNow.text = "Now:  No guide info"
    end if
    if nextP <> invalid
        m.bNext.text = "Next:  " + nextP.title + "   (" + hm(Int(nextP.playStart)) + ")"
    else
        m.bNext.text = ""
    end if
    if m.favs.DoesExist(ch.cid) then m.bName.text = ch.title + "   (Favorite)"
    m.banner.visible = true
    m.bannerTimer.control = "stop"
    m.bannerTimer.control = "start"
end sub

sub hideBanner()
    m.banner.visible = false
end sub

sub leavePlayer()
    m.tuneTimer.control = "stop"
    m.tuning = false
    m.video.control = "stop"
    m.status.visible = false
    m.banner.visible = false
    if m.playIndex >= 0 then m.grid.jumpToChannel = m.playIndex
    showGuide()
end sub

' ---------- keys ----------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.mode = "player"
        if key = "up"
            startChannel(m.playIndex - 1, -1, true)
        else if key = "down"
            startChannel(m.playIndex + 1, 1, true)
        else if key = "OK" or key = "back"
            leavePlayer()
        else if key = "options"
            toggleFav(m.playIndex)
            showBanner()
        else
            showBanner()
        end if
        return true
    else if m.mode = "menu" or m.mode = "info"
        if key = "back" or key = "options"
            showGuide()
            return true
        end if
    else if m.mode = "guide"
        if key = "options"
            openMenu()
            return true
        end if
    end if
    return false
end function
