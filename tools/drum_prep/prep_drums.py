#!/usr/bin/env python3
"""Convert a collection of per-machine drum sample ZIPs into lossless WAV folders with
manifests and a catalog, for Godot Audio Kit's drum library. See README.md."""

import argparse
import csv
import fnmatch
import json
import os
import shutil
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dp import TOOL_VERSION  # noqa: E402
from dp import machine as dm  # noqa: E402


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, help="folder of <Machine>.zip files (read only)")
    ap.add_argument("--out", required=True, help="output folder for this collection")
    ap.add_argument("--collection-name", default="", help="recorded in the catalog")
    ap.add_argument("--collection-url", default="", help="recorded in the catalog")
    ap.add_argument("--license-note", default="", help="recorded in the catalog")
    ap.add_argument("--only", action="append", metavar="GLOB", help="machines (ZIP names without .zip) to do; repeatable")
    ap.add_argument("--workers", type=int, default=max(1, min(4, (os.cpu_count() or 2) // 2)))
    ap.add_argument("--force", action="store_true", help="redo machines even when unchanged")
    ap.add_argument("--dry-run", action="store_true", help="convert in memory and print the summary; write nothing")
    return ap.parse_args(argv)


def machine_dir(out, machine):
    return os.path.join(out, dm.safe_component(machine))


def stamp(zip_path):
    st = os.stat(zip_path)
    return {"tool_version": TOOL_VERSION, "zip_bytes": st.st_size, "zip_mtime": int(st.st_mtime)}


def up_to_date(out, zip_path):
    m = os.path.join(machine_dir(out, os.path.splitext(os.path.basename(zip_path))[0]), "manifest.json")
    if not os.path.exists(m):
        return False
    try:
        with open(m, encoding="utf-8") as fh:
            return json.load(fh).get("stamp") == stamp(zip_path)
    except (OSError, ValueError):
        return False


def run_one(zip_path, out, write):
    name = os.path.splitext(os.path.basename(zip_path))[0]
    d = machine_dir(out, name)
    if write:
        if os.path.isdir(d):
            shutil.rmtree(d)   # our own earlier output for this machine
        os.makedirs(d)
    t0 = time.time()
    man = dm.process(zip_path, d, write)
    man["stamp"] = stamp(zip_path)
    man["seconds_taken"] = round(time.time() - t0, 1)
    if write:
        with open(os.path.join(d, "manifest.json"), "w", encoding="utf-8", newline="\n") as fh:
            json.dump(man, fh, indent=1, ensure_ascii=False)
    return man


def summary(man):
    notes = {}
    for f in man["files"]:
        for n in f.get("notes", []):
            k = n.split(" named ")[0] if " named " in n else n
            notes[k] = notes.get(k, 0) + 1
    return "%-40s %5d files  %3d dropped  %2d failed  %s" % (
        man["machine"][:40], len(man["files"]), len(man["dropped"]), len(man["failed"]),
        ", ".join("%s %d" % kv for kv in sorted(notes.items())))


def build_catalog(out, args):
    rows, by_hash = [], {}
    for name in sorted(os.listdir(out)):
        m = os.path.join(out, name, "manifest.json")
        if not os.path.isfile(m):
            continue
        with open(m, encoding="utf-8") as fh:
            man = json.load(fh)
        for f in man["files"]:
            row = {"machine": man["machine"], "path": name + "/" + f["path"], "kind": f["kind"],
                   "seconds": f["seconds"], "rate": f["rate"], "bits": f["bits"], "float": f["float"],
                   "channels": f["channels"], "peak_dbfs": f["peak_dbfs"],
                   "layer_group": f.get("layer", {}).get("group", ""),
                   "layer_index": f.get("layer", {}).get("index", ""),
                   "root_note": f.get("root_note", ""), "content_sha256": f["content_sha256"],
                   "notes": "; ".join(f.get("notes", []))}
            rows.append(row)
            by_hash.setdefault(f["content_sha256"], []).append(row["path"])
    for r in rows:
        others = [p for p in by_hash[r["content_sha256"]] if p != r["path"]]
        r["same_as"] = "; ".join(others)
    cat = {"collection": {"name": args.collection_name, "url": args.collection_url,
                          "license_note": args.license_note},
           "tool_version": TOOL_VERSION, "machines": len({r["machine"] for r in rows}),
           "files": len(rows), "entries": rows}
    with open(os.path.join(out, "catalog.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(cat, fh, indent=1, ensure_ascii=False)
    with open(os.path.join(out, "catalog.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ["path"])
        w.writeheader()
        w.writerows(rows)
    return cat


def main(argv=None):
    args = parse_args(argv)
    src, out = os.path.abspath(args.source), os.path.abspath(args.out)
    if out.startswith(src + os.sep) or src.startswith(out + os.sep) or src == out:
        sys.exit("--out must be outside --source")
    zips = sorted(os.path.join(src, f) for f in os.listdir(src) if f.lower().endswith(".zip"))
    if args.only:
        zips = [z for z in zips if any(fnmatch.fnmatch(os.path.basename(z)[:-4], g) for g in args.only)]
    if not args.dry_run:
        os.makedirs(out, exist_ok=True)
    todo = [z for z in zips if args.force or args.dry_run or not up_to_date(out, z)]
    print("%d machines, %d to do" % (len(zips), len(todo)), flush=True)
    failures = 0
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(run_one, z, out, not args.dry_run): z for z in todo}
        for fut in as_completed(futs):
            try:
                print(summary(fut.result()), flush=True)
            except Exception as e:  # noqa: BLE001
                failures += 1
                print("FAILED %s: %r" % (os.path.basename(futs[fut]), e), flush=True)
    if not args.dry_run:
        cat = build_catalog(out, args)
        print("catalog: %d files from %d machines" % (cat["files"], cat["machines"]))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
