sub init()
    m.icon = m.top.findNode("icon")
    m.title = m.top.findNode("title")
end sub

sub setContent()
    c = m.top.content
    if c = invalid then return
    m.title.text = c.title
    m.icon.uri = ""
    if c.hdSmallIconUrl <> invalid then m.icon.uri = c.hdSmallIconUrl
end sub

sub layout()
    w = m.top.width
    h = m.top.height
    if h <= 0 then h = 60
    m.icon.translation = [8, (h - 44) / 2]
    m.title.translation = [90, 0]
    if w > 100 then m.title.width = w - 96
    m.title.height = h
end sub
