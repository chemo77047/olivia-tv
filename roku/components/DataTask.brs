sub init()
    m.top.functionName = "serve"
end sub

sub serve()
    m.top.status = "loading"
    m.channels = loadJson("channels.json", "pkg:/data/channels.json")
    if type(m.channels) <> "roArray" then m.channels = []
    m.guide = {}
    g = loadJson("roku_guide.json", "")
    if type(g) = "roAssociativeArray" and g.ch <> invalid then m.guide = g.ch
    port = CreateObject("roMessagePort")
    m.top.observeField("request", port)
    m.top.status = "ready"
    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent" then build(msg.getData())
    end while
end sub

function fetch(name as string) as string
    ut = CreateObject("roUrlTransfer")
    ut.SetCertificatesFile("common:/certs/ca-bundle.crt")
    ut.InitClientCertificates()
    ut.EnableEncodings(true)
    ut.SetUrl("https://raw.githubusercontent.com/chemo77047/olivia-tv/main/data/" + name)
    port = CreateObject("roMessagePort")
    ut.SetMessagePort(port)
    if ut.AsyncGetToString()
        msg = wait(30000, port)
        if type(msg) = "roUrlEvent"
            if msg.GetResponseCode() = 200 then return msg.GetString()
        else
            ut.AsyncCancel()
        end if
    end if
    return ""
end function

function loadJson(name as string, fallback as string) as dynamic
    cache = "cachefs:/" + name
    s = fetch(name)
    if s <> ""
        WriteAsciiFile(cache, s)
    else
        s = ReadAsciiFile(cache)
    end if
    data = invalid
    if s <> "" then data = ParseJson(s)
    if data = invalid and fallback <> "" then data = ParseJson(ReadAsciiFile(fallback))
    return data
end function

function regJson(key as string) as object
    sec = CreateObject("roRegistrySection", "oliviatv")
    if sec.Exists(key)
        v = ParseJson(sec.Read(key))
        if type(v) = "roAssociativeArray" then return v
    end if
    return {}
end function

function regStr(key as string) as string
    sec = CreateObject("roRegistrySection", "oliviatv")
    if sec.Exists(key) then return sec.Read(key)
    return ""
end function

function fold(s as string) as string
    s = LCase(s)
    pairs = [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ü", "u"], ["ñ", "n"], ["Á", "a"], ["É", "e"], ["Í", "i"], ["Ó", "o"], ["Ú", "u"], ["Ñ", "n"]]
    for each p in pairs
        s = s.Replace(p[0], p[1])
    end for
    return s
end function

function include(c as object, section as string, query as string, favs as object, failed as object, nowS as integer) as boolean
    t = failed[c.id]
    if t <> invalid and nowS - t < 259200 then return false
    if section = "fav" then return favs.DoesExist(c.id)
    if section = "kids" then return c.kids <> invalid and c.kids = true
    if section = "mx" or section = "es" or section = "us" then return c.section = section
    if section = "search" then return query <> "" and Instr(1, fold(c.name), query) > 0
    return true
end function

sub build(req as object)
    section = "all"
    if req.section <> invalid then section = req.section
    query = ""
    if req.query <> invalid then query = fold(req.query)
    favs = regJson("favs")
    failed = regJson("failed")
    nowS = CreateObject("roDateTime").AsSeconds()
    if section = "start"
        last = regStr("last")
        if favs.Count() > 0 and (last = "" or favs.DoesExist(last))
            section = "fav"
        else
            section = "all"
        end if
    end if
    winStart = nowS - 3600
    winEnd = nowS + 12 * 3600
    root = CreateObject("roSGNode", "ContentNode")
    root.addFields({section: section, query: query})
    for each c in m.channels
        if include(c, section, query, favs, failed, nowS)
            ch = root.createChild("ContentNode")
            ch.title = c.name
            if c.logo <> invalid then ch.hdSmallIconUrl = c.logo
            ch.addFields({cid: c.id, srcList: c.streams})
            added = 0
            progs = m.guide[c.id]
            if progs <> invalid
                for each p in progs
                    if p[1] > winStart and p[0] < winEnd
                        pn = ch.createChild("ContentNode")
                        pn.title = p[2]
                        pn.playStart = p[0]
                        pn.playDuration = p[1] - p[0]
                        pn.description = p[3]
                        pn.shortDescriptionLine1 = p[4]
                        added = added + 1
                    end if
                end for
            end if
            if added = 0
                pn = ch.createChild("ContentNode")
                pn.title = c.name
                pn.playStart = winStart
                pn.playDuration = winEnd - winStart
                pn.shortDescriptionLine2 = "noinfo"
            end if
        end if
    end for
    m.top.result = root
end sub
