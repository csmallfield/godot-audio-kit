#!/usr/bin/env python3
"""Index a drum library folder for GAK's drum browser: every sound and kit of every collection
under it, in <root>/gak_drums.json. See README.md (Browser index)."""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import TOOL_VERSION  # noqa: E402

INDEX_VERSION = 1


def collections(root):
    for d in sorted(os.listdir(root)):
        full = os.path.join(root, d)
        if os.path.isfile(os.path.join(full, "catalog.json")):
            yield d, full


def index_collection(name, full):
    with open(os.path.join(full, "catalog.json"), encoding="utf-8") as fh:
        cat = json.load(fh)
    tags = {}
    tpath = os.path.join(full, "tags.json")
    if os.path.exists(tpath):
        with open(tpath, encoding="utf-8") as fh:
            tags = json.load(fh).get("files", {})
    sounds = []
    for e in cat["entries"]:
        t = tags.get(e["path"], {})
        fin = t.get("final") or {}
        an = t.get("analysis") or {}
        inner = e["path"].split("/", 1)[1]
        words = list(an.get("describe", []))
        if e.get("kind") in ("loop", "long") and e["kind"] not in words:
            words.append(e["kind"])
        s = {"id": "%s/%s" % (name, e["path"]), "path": "%s/%s" % (name, e["path"]),
             "name": inner.rsplit("/", 1)[-1].rsplit(".", 1)[0], "machine": e["machine"], "collection": name,
             "folder": inner.rsplit("/", 1)[0] if "/" in inner else "",
             "category": fin.get("category") or "", "kind": (fin.get("kind") or "").split(":")[0],
             "sure": bool(fin.get("sure")), "how": fin.get("from", ""), "tags": words,
             "seconds": e.get("seconds", 0.0), "channels": e.get("channels", 1), "rate": e.get("rate", 0),
             "note": an.get("note", "")}
        if e.get("layer_group"):
            s["layer"] = "%s [V%s]" % (e["layer_group"].rsplit("/", 1)[-1], e.get("layer_index", ""))
        sounds.append(s)
    kits = []
    kpath = os.path.join(full, "kits", "index.json")
    if os.path.exists(kpath):
        with open(kpath, encoding="utf-8") as fh:
            for k in json.load(fh)["kits"]:
                kits.append({"id": "kit:%s/%s" % (name, k["path"]), "path": "%s/kits/%s" % (name, k["path"]),
                             "name": k["name"], "machine": k["machine"], "collection": name, "from": k["from"],
                             "folder": k.get("folder", ""), "pieces": k["pieces"], "sure_share": k["sure_share"],
                             "layered": k.get("layered", 0)})
    return sounds, kits


def build(root):
    sounds, kits, cols = [], [], []
    for name, full in collections(root):
        s, k = index_collection(name, full)
        sounds += s
        kits += k
        cols.append({"name": name, "sounds": len(s), "kits": len(k)})
    data = {"version": INDEX_VERSION, "tool_version": TOOL_VERSION, "collections": cols, "sounds": sounds, "kits": kits}
    with open(os.path.join(root, "gak_drums.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, separators=(",", ":"), ensure_ascii=False)
    return data


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", required=True, help="the drum library folder (holding one folder per collection)")
    a = ap.parse_args(argv)
    d = build(a.root)
    print("%d collections, %d sounds, %d kits -> %s" % (len(d["collections"]), len(d["sounds"]), len(d["kits"]),
                                                     os.path.join(a.root, "gak_drums.json")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
