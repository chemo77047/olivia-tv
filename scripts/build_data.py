"""Builds data/channels.json and epg/custom.channels.xml from the iptv-org API.

Keeps US and Mexican channels whose streams actually answer right now.
"""
import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

API = "https://iptv-org.github.io/api/"
COUNTRIES = {"US", "MX"}
KIDS = {"kids", "animation", "family"}
BLOCKED_CATS = {"xxx", "shop"}
SITE_ORDER = [
    "i.mjh.nz", "pluto.tv", "plex.tv", "tvtv.us", "tvpassport.com", "gatotv.com",
    "mi.tv", "tvguide.com", "xumo.tv", "distro.tv", "ontvtonight.com", "watchyour.tv",
]
MAX_SOURCES = 3
UA = "Mozilla/5.0 (Linux; Android 12; TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def get_json(name):
    with urllib.request.urlopen(API + name, timeout=120) as r:
        return json.load(r)


def quality(st):
    q = (st.get("quality") or "").rstrip("pi")
    return int(q) if q.isdigit() else 0


def stream_ok(st):
    headers = {"User-Agent": st.get("user_agent") or UA}
    if st.get("referrer"):
        headers["Referer"] = st["referrer"]
    try:
        req = urllib.request.Request(st["url"], headers=headers)
        with urllib.request.urlopen(req, timeout=10) as r:
            if r.status != 200:
                return False
            body = r.read(65536)
            ctype = r.headers.get("Content-Type", "")
            return b"#EXTM3U" in body or "video" in ctype or "mpegurl" in ctype.lower()
    except Exception:
        return False


def main():
    channels = {c["id"]: c for c in get_json("channels.json")}
    feeds = get_json("feeds.json")
    streams = get_json("streams.json")
    guides = get_json("guides.json")
    logos = get_json("logos.json")

    main_lang = {f["channel"]: f.get("languages") or [] for f in feeds if f.get("is_main")}
    logo = {}
    for l in logos:
        if l.get("feed") is None and l["channel"] not in logo:
            logo[l["channel"]] = l["url"]

    picked = {}
    for st in streams:
        ch = channels.get(st.get("channel"))
        if not ch or ch["country"] not in COUNTRIES or ch.get("closed") or ch.get("is_nsfw"):
            continue
        if BLOCKED_CATS & set(ch["categories"]):
            continue
        picked.setdefault(ch["id"], []).append(st)

    flat = [st for sts in picked.values() for st in sts]
    with ThreadPoolExecutor(64) as pool:
        results = list(pool.map(stream_ok, flat))
    ok_urls = {st["url"] for st, ok in zip(flat, results) if ok}

    guide_sites = {}
    for g in guides:
        cid = g.get("channel")
        if cid not in picked or g["site"] not in SITE_ORDER:
            continue
        guide_sites.setdefault(cid, {}).setdefault(g["site"], []).append(g)

    out = []
    for cid, sts in picked.items():
        good = [s for s in sts if s["url"] in ok_urls]
        if not good:
            continue
        good.sort(key=lambda s: ("Geo-blocked" in s["labels"], -quality(s)))
        ch = channels[cid]
        if ch["country"] == "MX":
            section = "mx"
        elif "spa" in main_lang.get(cid, []):
            section = "es"
        else:
            section = "us"
        out.append({
            "id": cid,
            "name": ch["name"],
            "logo": logo.get(cid),
            "section": section,
            "kids": bool(KIDS & set(ch["categories"])),
            "cats": ch["categories"],
            "streams": [
                {k: v for k, v in (("u", s["url"]), ("ua", s.get("user_agent")), ("ref", s.get("referrer"))) if v}
                for s in good[:3]
            ],
        })
    out.sort(key=lambda c: c["name"].lower())

    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "channels.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))

    os.makedirs(os.path.join(ROOT, "epg"), exist_ok=True)
    from xml.sax.saxutils import escape, quoteattr
    lines = ['<?xml version="1.0" encoding="UTF-8"?>', "<channels>"]
    kept = {c["id"]: c for c in out}
    mjh = []
    n_guide = 0
    for cid, sites in sorted(guide_sites.items()):
        if cid not in kept:
            continue
        n_guide += 1
        region = "/mx" if kept[cid]["section"] == "mx" else "/us"
        for site in sorted(sites, key=SITE_ORDER.index)[:MAX_SOURCES]:
            g = sorted(sites[site], key=lambda g: (region not in g["site_id"], "/us" not in g["site_id"]))[0]
            if site == "i.mjh.nz":
                mjh.append([cid, g["site_id"]])
                continue
            lines.append(
                f'  <channel site={quoteattr(site)} lang={quoteattr(g["lang"])} '
                f'xmltv_id={quoteattr(cid)} site_id={quoteattr(g["site_id"])}>{escape(g["site_name"])}</channel>'
            )
    lines.append("</channels>")
    with open(os.path.join(ROOT, "epg", "mjh.json"), "w", encoding="utf-8") as f:
        json.dump(mjh, f)
    with open(os.path.join(ROOT, "epg", "custom.channels.xml"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    by = {}
    for c in out:
        by[c["section"]] = by.get(c["section"], 0) + 1
    print(f"channels kept: {len(out)} {by}; with guide: {n_guide}; streams ok {len(ok_urls)}/{len(flat)}")


if __name__ == "__main__":
    main()
