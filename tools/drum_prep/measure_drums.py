#!/usr/bin/env python3
"""Measure every file of a converted collection: writes <collection>/analysis/features.json,
keyed by path, each entry with the file's content hash (unchanged files aren't measured again).
See README.md (Analysis)."""

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import features  # noqa: E402

FEATURES_VERSION = 2


def measure_machine(out, items):
    res, errors = {}, []
    for path, sha in items:
        try:
            m = features.measure(os.path.join(out, *path.split("/")))
            m["content_sha256"] = sha
            res[path] = m
        except Exception as e:  # noqa: BLE001
            errors.append((path, repr(e)))
    return res, errors


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", required=True, help="the converted collection (holds catalog.json)")
    ap.add_argument("--workers", type=int, default=max(1, min(6, (os.cpu_count() or 2) - 2)))
    ap.add_argument("--force", action="store_true", help="measure everything again")
    a = ap.parse_args(argv)
    with open(os.path.join(a.out, "catalog.json"), encoding="utf-8") as fh:
        entries = json.load(fh)["entries"]
    fpath = os.path.join(a.out, "analysis", "features.json")
    old = {}
    if os.path.exists(fpath) and not a.force:
        with open(fpath, encoding="utf-8") as fh:
            d = json.load(fh)
        if d.get("version") == FEATURES_VERSION:
            old = d["files"]
    by_machine, keep = {}, {}
    for e in entries:
        o = old.get(e["path"])
        if o and o.get("content_sha256") == e["content_sha256"]:
            keep[e["path"]] = o
        else:
            by_machine.setdefault(e["machine"], []).append((e["path"], e["content_sha256"]))
    todo = sum(len(v) for v in by_machine.values())
    print("%d files, %d to measure" % (len(entries), todo), flush=True)
    t0, done, errors = time.time(), 0, []
    with ProcessPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(measure_machine, a.out, items) for items in by_machine.values()]
        for f in as_completed(futs):
            res, err = f.result()
            keep.update(res)
            errors += err
            done += len(res) + len(err)
            if done and (done % 5000 < len(res) + len(err)):
                print("  %d / %d (%.0f s)" % (done, todo, time.time() - t0), flush=True)
    os.makedirs(os.path.dirname(fpath), exist_ok=True)
    with open(fpath, "w", encoding="utf-8", newline="\n") as fh:
        json.dump({"version": FEATURES_VERSION, "files": keep, "errors": errors}, fh, separators=(",", ":"))
    print("measured %d, errors %d, %.0f s" % (len(keep), len(errors), time.time() - t0))
    for e in errors[:10]:
        print("  ", e)
    return 0


if __name__ == "__main__":
    sys.exit(main())
