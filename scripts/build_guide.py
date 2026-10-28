"""Builds data/guide.json.gz for the app.

Merges the grabbed XMLTV files (epg/guides/<site>.xml) with i.mjh.nz feeds (epg/mjh.json), keeping
for each channel the source with the most programs in the window.
Format: {"start": epoch, "ch": {channel_id: [[start, end, title, desc, category], ...]}}
"""
import gzip
import io
import json
import os
import time
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEFORE = 3 * 3600
AFTER = 36 * 3600


def ts(s):
    return int(datetime.strptime(s.strip(), "%Y%m%d%H%M%S %z").timestamp())


def programmes(src, lo, hi, wanted=None):
    """Yields (channel, [start, stop, title, desc, cat]) from an XMLTV stream."""
    for _, el in ET.iterparse(src):
        if el.tag != "programme":
            if el.tag == "channel":
                el.clear()
            continue
        cid = el.get("channel") or ""
        if wanted is not None and cid not in wanted:
            el.clear()
            continue
        try:
            start, stop = ts(el.get("start")), ts(el.get("stop"))
        except (TypeError, ValueError):
            el.clear()
            continue
        if stop > lo and start < hi and stop > start:
            title = (el.findtext("title") or "").strip()
            sub = (el.findtext("sub-title") or "").strip()
            desc = (el.findtext("desc") or "").strip()
            if sub and sub != title:
                desc = f"{sub}. {desc}" if desc else sub
            cat = (el.findtext("category") or "").strip()
            yield cid, [start, stop, title, desc[:400], cat]
        el.clear()


def clean(progs):
    progs.sort()
    out = []
    for p in progs:
        if out and p[0] < out[-1][1]:
            continue
        out.append(p)
    return out


def main():
    now = int(time.time())
    lo, hi = now - BEFORE, now + AFTER
    candidates = {}

    gdir = os.path.join(ROOT, "epg", "guides")
    for name in sorted(os.listdir(gdir)) if os.path.isdir(gdir) else []:
        if not name.endswith(".xml"):
            continue
        per = {}
        for cid, p in programmes(os.path.join(gdir, name), lo, hi):
            per.setdefault(cid.split("@")[0], []).append(p)
        for cid, progs in per.items():
            candidates.setdefault(cid, []).append(clean(progs))

    mjh_path = os.path.join(ROOT, "epg", "mjh.json")
    if os.path.exists(mjh_path):
        by_feed = {}
        for cid, site_id in json.load(open(mjh_path)):
            feed, key = site_id.split("#", 1)
            by_feed.setdefault(feed, {}).setdefault(key, []).append(cid)
        for feed, keys in by_feed.items():
            try:
                with urllib.request.urlopen(f"https://i.mjh.nz/{feed}.xml.gz", timeout=120) as r:
                    data = gzip.decompress(r.read())
            except Exception as e:
                print(f"skip {feed}: {e}")
                continue
            per = {}
            for key, p in programmes(io.BytesIO(data), lo, hi, wanted=keys):
                per.setdefault(key, []).append(p)
            for key, progs in per.items():
                for cid in keys[key]:
                    candidates.setdefault(cid, []).append(clean(list(progs)))

    ch = {}
    for cid, lists in candidates.items():
        best = max(lists, key=lambda l: (sum(1 for p in l if p[2]), sum(1 for p in l if p[3])))
        if best:
            ch[cid] = best
    out = os.path.join(ROOT, "data", "guide.json.gz")
    with gzip.open(out, "wt", encoding="utf-8") as f:
        json.dump({"start": now, "ch": ch}, f, ensure_ascii=False, separators=(",", ":"))
    roku = {}
    for cid, progs in ch.items():
        keep = [[p[0], p[1], p[2], p[3][:200], p[4]] for p in progs if p[1] > now - 3600 and p[0] < now + 12 * 3600]
        if keep:
            roku[cid] = keep
    with open(os.path.join(ROOT, "data", "roku_guide.json"), "w", encoding="utf-8") as f:
        json.dump({"start": now, "ch": roku}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"guide: {len(ch)} channels, {sum(len(v) for v in ch.values())} programs, {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    main()
