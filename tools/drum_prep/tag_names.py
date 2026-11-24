#!/usr/bin/env python3
"""Tag every file of a converted collection by its name: writes <collection>/tags.json.
See README.md (Name tags)."""

import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import TOOL_VERSION  # noqa: E402
from dp import names  # noqa: E402

MAPS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "name_maps")


def tag_collection(out, maps_dir=MAPS_DIR):
    with open(os.path.join(out, "catalog.json"), encoding="utf-8") as fh:
        cat = json.load(fh)
    maps = names.load_name_maps(maps_dir)
    files, by, cats = {}, collections.Counter(), collections.Counter()
    for e in cat["entries"]:
        machine = e["machine"]
        inner = e["path"].split("/", 1)[1]
        r = names.classify(inner, maps.get(machine))
        files[e["path"]] = {"name": r}
        by[r["by"] or "none"] += 1
        cats[r["category"] or "unknown"] += 1
    tags = {"tool_version": TOOL_VERSION, "name_maps": sorted(maps), "summary": {"by": dict(by), "category": dict(cats)},
            "files": files}
    path = os.path.join(out, "tags.json")
    old = {}
    if os.path.exists(path):   # keep what later steps (analysis) wrote
        with open(path, encoding="utf-8") as fh:
            old = json.load(fh).get("files", {})
    for k, v in files.items():
        for section, val in old.get(k, {}).items():
            if section != "name":
                v[section] = val
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(tags, fh, indent=1, ensure_ascii=False)
    return tags


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="the converted collection (holds catalog.json)")
    ap.add_argument("--maps", default=MAPS_DIR, help="folder of name maps (default: name_maps/ beside this script)")
    a = ap.parse_args(argv)
    t = tag_collection(a.out, a.maps)
    n = len(t["files"])
    known = n - t["summary"]["category"].get("unknown", 0)
    print("%d files, %d tagged by name (%.1f%%)" % (n, known, 100.0 * known / max(1, n)))
    print("by:", t["summary"]["by"])
    print("category:", dict(sorted(t["summary"]["category"].items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
