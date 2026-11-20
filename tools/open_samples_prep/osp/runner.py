"""The batch run: plan, convert in parallel, write sidecars and the catalog."""

import csv
import datetime as dt
import fnmatch
import hashlib
import json
import logging
import os
import re
import shutil
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

from . import SCHEMA, TOOL_NAME, TOOL_VERSION, cwm
from .discover import discover, instrument_root, notes_for
from .sfz import zones_from_sfz_text
from .sidecar import (build_tags, identity_for, notes_in_name, readme_text, summarize_samples,
                      summarize_zones)
from .slug import assign_out_paths, short_hash
from .wavinfo import read_wav_info

log = logging.getLogger("osp")

STATUSES = ["converted", "skipped-wav", "failed", "encrypted", "unsupported", "excluded",
            "pending"]
ADDITIONS_FILE = ".open_samples_additions.json"
CONVERTIBLE_KINDS = {"kontakt", "exs24", "sf2"}
SIDE = "instrument.json"
NOTE_TEXT_LIMIT = 64 * 1024


# --- hashing -------------------------------------------------------------------------

def sha256_file(path, bufsize=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(bufsize), b""):
            h.update(chunk)
    return h.hexdigest()


class HashCache:
    """sha256 per source file, reused while size and mtime are unchanged."""

    def __init__(self, path):
        self.path = path
        self.data = {}
        self.lock = threading.Lock()
        if path and os.path.isfile(path):
            try:
                with open(path, encoding="utf-8") as f:
                    self.data = json.load(f)
            except (OSError, ValueError):
                self.data = {}

    def get(self, abs_path, key):
        st = os.stat(abs_path)
        stamp = [st.st_size, st.st_mtime_ns]
        with self.lock:
            hit = self.data.get(key)
        if hit and hit[:2] == stamp:
            return hit[2]
        digest = sha256_file(abs_path)
        with self.lock:
            self.data[key] = stamp + [digest]
        return digest

    def save(self):
        if not self.path:
            return
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.data, f, sort_keys=True)
        os.replace(tmp, self.path)


# --- small helpers ---------------------------------------------------------------------

def now_iso():
    return dt.datetime.now().astimezone().replace(microsecond=0).isoformat()


def write_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def read_text(path, limit=None):
    with open(path, "rb") as f:
        raw = f.read(limit + 1 if limit else -1)
    text = raw.decode("utf-8", "replace")
    if limit and len(raw) > limit:
        text = text[:limit] + "\n[... truncated]"
    return text


def collection_info(root, args):
    info = {"name": "Open Samples", "url": "https://github.com/pumodi/open-samples",
            "root": root.replace("\\", "/"), "version": args.collection_version,
            "commit": args.collection_commit, "download_date": args.download_date}
    readme = os.path.join(root, "README.MD")
    if not os.path.isfile(readme):
        readme = os.path.join(root, "README.md")
    if os.path.isfile(readme):
        text = read_text(readme, 200000)
        m = re.search(r"Patch%20Number-(v[\d.]+)", text)
        if m and not info["version"]:
            info["version"] = m.group(1)
            info["version_source"] = "README badge 'Patch Number'"
        info["readme"] = os.path.relpath(readme, root).replace("\\", "/")
    if not info["download_date"]:
        try:
            info["download_date"] = dt.datetime.fromtimestamp(
                os.stat(root).st_ctime).date().isoformat()
            info["download_date_source"] = "creation time of the collection folder (estimate)"
        except OSError:
            pass
    return info


def license_info(root):
    path = os.path.join(root, "docs", "LICENSE.md")
    if not os.path.isfile(path):
        return {"name": "unknown", "path": None}
    text = read_text(path)
    first = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
    ver = re.search(r"Version\s+([\w.]+)", text)
    name = first.title() if first.isupper() else first
    return {"name": f"{name} v{ver.group(1)}" if ver else name, "path": "docs/LICENSE.md",
            "sha256": sha256_file(path), "copy_in_output": "LICENSE-open-samples.md",
            "summary": "Free and royalty free for music and sound use; don't resell the "
                       "samples as they are or repackaged; demos are all rights reserved."}


# --- the run ---------------------------------------------------------------------------

class Run:
    def __init__(self, args):
        self.args = args
        self.source = os.path.abspath(args.source)
        self.out = os.path.abspath(args.out)
        self.dry = args.dry_run
        self.cwm_exe = None
        self.cwm_version = None
        self.write_ds = not args.no_decentsampler

    # options that change output; part of every fingerprint
    def options_for(self, cand):
        if cand.kind in CONVERTIBLE_KINDS:
            dests = ["sfz"] + (["decentsampler"] if self.write_ds else [])
            return {"destinations": dests,
                    "params": {d: cwm.DEST_PARAMS.get(d, {}) for d in dests},
                    "flat": True, "processing": "off", "analysis": "-ad"}
        if cand.kind in ("wav-folder", "wav-file"):
            return {"copy_wav": bool(self.args.copy_wav)}
        return {}

    def fingerprint(self, cand, source_sha):
        payload = {"source_sha256": source_sha, "tool_version": TOOL_VERSION,
                   "schema": SCHEMA, "options": self.options_for(cand)}
        if cand.kind in CONVERTIBLE_KINDS:
            payload["convertwithmoss_version"] = self.cwm_version
        return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()

    def check_paths(self):
        s, o = os.path.normcase(self.source), os.path.normcase(self.out)
        if not os.path.isdir(self.source):
            raise SystemExit(f"source folder not found: {self.source}")
        if o == s or o.startswith(s + os.sep) or s.startswith(o + os.sep):
            raise SystemExit("output folder must be outside the source collection (and not "
                             "contain it)")

    def setup_logging(self):
        fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s", "%H:%M:%S")
        log.setLevel(logging.INFO)
        log.handlers.clear()
        h = logging.StreamHandler()
        h.setFormatter(fmt)
        log.addHandler(h)
        if not self.dry:
            os.makedirs(os.path.join(self.out, "logs"), exist_ok=True)
            stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
            self.log_path = os.path.join(self.out, "logs", f"run-{stamp}.log")
            fh = logging.FileHandler(self.log_path, encoding="utf-8")
            fh.setFormatter(fmt)
            log.addHandler(fh)

    @staticmethod
    def _matches(rel, pats):
        rel = rel.lower()
        for p in pats:
            p = p.replace("\\", "/").lower().rstrip("/")
            if fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(rel, p + "/*"):
                return True
        return False

    def excluded(self, cand):
        return self._matches(cand.rel, self.args.exclude or [])

    def selected(self, cand):
        if self.excluded(cand):
            return False
        pats = self.args.only or []
        return not pats or self._matches(cand.rel, pats)

    def existing_sidecar(self, cand):
        p = os.path.join(self.out, cand.out_rel, SIDE)
        if not os.path.isfile(p):
            return None
        try:
            with open(p, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def outputs_present(self, cand, sc):
        base = os.path.join(self.out, cand.out_rel)
        for v in (sc.get("outputs") or {}).values():
            if isinstance(v, str) and v and not v.startswith("(") and not os.path.exists(
                    os.path.join(base, v)):
                return False
            if isinstance(v, list):
                for x in v:
                    if isinstance(x, str) and not os.path.exists(os.path.join(base, x)):
                        return False
        return True

    # -- main ---------------------------------------------------------------------------

    def main(self):
        self.check_paths()
        self.setup_logging()
        try:
            return self._main()
        finally:
            for h in list(log.handlers):
                h.close()
                log.removeHandler(h)

    def _main(self):
        a = self.args
        log.info("%s %s  source=%s  out=%s%s", TOOL_NAME, TOOL_VERSION, self.source, self.out,
                 "  (dry run)" if self.dry else "")
        coll = discover(self.source)
        mapping = assign_out_paths(
            (c.rel, c.is_file, c.kind, c.kind_suffix) for c in coll.candidates)
        for c in coll.candidates:
            c.out_rel = mapping[c.rel]
        self.coll = coll
        self.collection = collection_info(self.source, a)
        self.license = license_info(self.source)
        self.additions = load_additions(self.source)
        chosen = [c for c in coll.candidates if self.selected(c)]
        log.info("found %d instruments (%s); %d selected", len(coll.candidates),
                 ", ".join(f"{k} {n}" for k, n in sorted(_count(coll.candidates, "kind").items())),
                 len(chosen))

        needs_cwm = any(c.kind in CONVERTIBLE_KINDS for c in chosen)
        self.cwm_exe = cwm.find_cwm(a.cwm)
        if self.cwm_exe:
            self.cwm_version = cwm.version(self.cwm_exe)
            log.info("ConvertWithMoss %s at %s", self.cwm_version, self.cwm_exe)
        elif needs_cwm:
            raise SystemExit("ConvertWithMoss not found; pass --cwm <path to "
                             "ConvertWithMossCLI.exe> or set OSP_CWM")

        cache_path = None if self.dry else os.path.join(self.out, ".hash_cache.json")
        if self.dry and os.path.isfile(os.path.join(self.out, ".hash_cache.json")):
            cache_path = os.path.join(self.out, ".hash_cache.json")  # read only below
        self.hashes = HashCache(cache_path)

        # plan
        plan = []
        for c in chosen:
            try:
                src_sha, member_shas = self.source_hash(c)
            except OSError as e:
                log.error("cannot read %s: %s", c.rel, e)
                src_sha, member_shas = None, {}
            fp = self.fingerprint(c, src_sha)
            old = self.existing_sidecar(c)
            action = "do"
            if old and not a.force and old.get("processing", {}).get("fingerprint") == fp \
                    and self.outputs_present(c, old):
                retry = a.retry_failed and old.get("status") in ("failed", "encrypted")
                action = "redo-failed" if retry else "skip"
            elif old:
                action = "redo"
            plan.append((c, src_sha, member_shas, fp, action))

        if self.dry:
            for c, _, _, _, action in plan:
                verb = {"do": "convert" if c.kind in CONVERTIBLE_KINDS else "catalog",
                        "redo": "redo (changed)", "redo-failed": "retry",
                        "skip": "skip (unchanged)"}[action]
                print(f"{verb:18} {c.kind:12} {c.rel}\n{'':18} {'':12} -> {c.out_rel}")
            counts = _count([p[4] for p in plan])
            print(f"\n{len(plan)} selected: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
            return 0

        os.makedirs(self.out, exist_ok=True)
        work_root = os.path.join(self.out, ".work")
        if os.path.isdir(work_root):
            shutil.rmtree(work_root, ignore_errors=True)  # leftovers of an interrupted run
        os.makedirs(work_root, exist_ok=True)
        self.hashes.save()

        todo = [p for p in plan if p[4] != "skip"]
        log.info("%d to do, %d unchanged", len(todo), len(plan) - len(todo))
        done = 0
        interrupted = False
        pool = ThreadPoolExecutor(max_workers=max(1, a.workers))
        try:
            futs = {pool.submit(self.process, c, sha, members, fp): c
                    for c, sha, members, fp, _ in todo}
            for fut in as_completed(futs):
                c = futs[fut]
                done += 1
                try:
                    sc = fut.result()
                    log.info("[%d/%d] %-11s %s", done, len(todo), sc["status"], c.rel)
                except Exception as e:  # keep going; record as failed
                    log.exception("[%d/%d] crashed on %s", done, len(todo), c.rel)
                    self.write_failure(c, f"internal error: {e!r}")
        except KeyboardInterrupt:
            interrupted = True
            log.warning("interrupted; finished instruments are kept, rerun to resume")
            pool.shutdown(wait=False, cancel_futures=True)
        finally:
            pool.shutdown(wait=not interrupted)
            self.hashes.save()
            shutil.rmtree(work_root, ignore_errors=True)
        self.write_catalog()
        return 130 if interrupted else 0

    # -- per instrument -----------------------------------------------------------------

    def source_hash(self, c):
        if c.kind in ("wav-folder", "wav-file"):
            members = {}
            for rel in c.files:
                members[rel] = self.hashes.get(os.path.join(self.source, rel), rel)
            if c.kind == "wav-file":
                return members[c.files[0]], members
            manifest = "".join(f"{r}\t{members[r]}\n" for r in sorted(members))
            return hashlib.sha256(manifest.encode()).hexdigest(), members
        return self.hashes.get(os.path.join(self.source, c.rel), c.rel), {}

    def base_sidecar(self, c, src_sha, fp):
        identity = identity_for(c)
        root = instrument_root(c.rel) if c.is_file else c.rel
        notes = notes_for(c.rel, c.is_file, self.coll.note_files)
        note_entries = []
        for n in notes:
            entry = {"path": n}
            if n == "docs/LICENSE.md":
                entry["text"] = "(collection licence; copied to LICENSE-open-samples.md)"
            elif n.lower() == self.collection.get("readme", "").lower():
                entry["text"] = "(collection README; not copied)"
            else:
                entry["text"] = read_text(os.path.join(self.source, n), NOTE_TEXT_LIMIT)
            note_entries.append(entry)
        under = (lambda rel: root == "" or rel.startswith(root + "/"))
        size = None
        if c.is_file:
            try:
                size = os.path.getsize(os.path.join(self.source, c.rel))
            except OSError:
                pass
        return {
            "schema": SCHEMA,
            "id": c.out_rel,
            "status": None,
            "reason": None,
            "origin": {
                "collection": self.collection,
                "source_path": c.rel,
                "source_kind": c.kind,
                "format": c.fmt,
                "source_sha256": src_sha,
                "source_sha256_of": "file" if c.is_file and c.kind != "wav-folder"
                else "manifest of '<path>\\t<sha256>' lines of the folder's WAV files",
                "source_size": size,
                "instrument_root": root,
                "related_files": {
                    "resources": [r for r in self.coll.resource_files if under(r)],
                    "scripts": [r for r in self.coll.script_files if under(r)],
                },
                "related_instruments": [],
                "notes": note_entries,
                "license": self.license,
                "added_from": self.additions.get(c.rel) or (
                    {"files": {f: self.additions[f] for f in c.files if f in self.additions}}
                    if any(f in self.additions for f in c.files) else None),
            },
            "identity": identity,
            "content": {},
            "processing": {
                "tool": TOOL_NAME, "tool_version": TOOL_VERSION,
                "convertwithmoss_version": None, "date": now_iso(),
                "options": self.options_for(c), "fingerprint": fp,
                "commands": [], "warnings": [], "lost": [],
            },
            "outputs": {},
            "tags": [],
        }

    def finish(self, c, sc, work):
        sc["tags"] = sc["tags"] or build_tags(sc["identity"])
        write_json(os.path.join(work, SIDE), sc)
        with open(os.path.join(work, "README.txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write(readme_text(sc))
        target = os.path.join(self.out, c.out_rel)
        assert os.path.normcase(os.path.abspath(target)).startswith(
            os.path.normcase(self.out) + os.sep)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.isdir(target):
            shutil.rmtree(target)
        os.replace(work, target)
        return sc

    def new_work(self, c):
        work = os.path.join(self.out, ".work", short_hash(c.rel, 12))
        if os.path.isdir(work):
            shutil.rmtree(work)
        os.makedirs(work)
        return work

    def write_failure(self, c, reason):
        work = self.new_work(c)
        sc = self.base_sidecar(c, None, None)
        sc["status"], sc["reason"] = "failed", reason
        self.finish(c, sc, work)

    def process(self, c, src_sha, members, fp):
        work = self.new_work(c)
        sc = self.base_sidecar(c, src_sha, fp)
        if c.kind in CONVERTIBLE_KINDS:
            self.convert(c, sc, work)
        elif c.kind in ("wav-folder", "wav-file"):
            self.wav_entry(c, sc, work, members)
        else:
            sc["status"] = "unsupported"
            sc["reason"] = f"{c.fmt}: no converter reads this format"
            sc["tags"] = build_tags(sc["identity"], [c.rel], ["unsupported"])
        return self.finish(c, sc, work)

    # -- WAV ----------------------------------------------------------------------------

    def wav_entry(self, c, sc, work, members):
        samples, notes = [], set()
        for rel in c.files:
            try:
                info = read_wav_info(os.path.join(self.source, rel))
            except (OSError, ValueError) as e:
                info = {"error": str(e)}
                sc["processing"]["warnings"].append(f"{rel}: {e}")
            name = rel.rsplit("/", 1)[-1]
            hint = notes_in_name(name.rsplit(".", 1)[0])
            notes.update(hint)
            samples.append({"file": rel, "sha256": members.get(rel), **info,
                            "notes_from_name": hint})
        copied = None
        if self.args.copy_wav:
            os.makedirs(os.path.join(work, "samples"))
            for rel in c.files:
                shutil.copy2(os.path.join(self.source, rel),
                             os.path.join(work, "samples", rel.rsplit("/", 1)[-1]))
            copied = "samples"
        related = []
        for o in self.coll.candidates:
            if o.kind in CONVERTIBLE_KINDS:
                root = instrument_root(o.rel)
                if root and (c.rel == root or c.rel.startswith(root + "/")):
                    related.append(o.out_rel)
        sc["origin"]["related_instruments"] = related
        summ = summarize_samples([s for s in samples if "error" not in s])
        smpl_roots = sorted({s["smpl"]["midi_unity_note"] for s in samples if s.get("smpl")})
        sc["content"] = {
            "samples_summary": summ,
            "notes_from_names": sorted(notes),
            "notes_from_names_convention": "C4 = 60 (hint only; sample makers differ)",
            "root_notes_from_smpl_chunks": smpl_roots,
            "looped_in_wav": any(s.get("smpl", {}).get("loops") for s in samples),
            "samples": samples,
        }
        sc["status"] = "skipped-wav"
        sc["reason"] = "plain WAV: usable as is; not converted"
        sc["outputs"] = {"samples_dir": copied,
                         "source_samples": "(referenced in place, see content.samples[].file)"}
        if related:
            sc["processing"]["warnings"].append(
                "these WAVs sit beside a sampler instrument that maps them: "
                + ", ".join(related))
        flags = ["wav"]
        flags.append("multisampled" if len(notes) > 1 else "single-sample" if len(c.files) == 1
                     else "multi-file")
        if summ["stereo"]:
            flags.append("stereo")
        if summ["mono"]:
            flags.append("mono")
        if sc["content"]["looped_in_wav"]:
            flags.append("looped")
        sc["tags"] = build_tags(sc["identity"], [c.rel] + c.files, flags)

    # -- conversion ---------------------------------------------------------------------

    def convert(self, c, sc, work):
        p = sc["processing"]
        p["convertwithmoss_version"] = self.cwm_version
        src = os.path.join(self.source, c.rel)
        logs = os.path.join(work, "cwm")
        os.makedirs(logs)
        scratch = os.path.join(work, "_scratch")
        os.makedirs(scratch)
        timeout = self.args.timeout

        # 1. analysis: ConvertWithMoss's own description of every zone, kept verbatim.
        args = cwm.analyze_args(c.cwm_source, src, scratch)
        rc, atext, cmd = cwm.run(self.cwm_exe, args, timeout)
        p["commands"].append(cwm.display_command(cmd))
        _write(os.path.join(logs, "analysis.txt"), atext)
        analysis = cwm.parse_analysis(atext)

        # 2. SFZ, the primary mapping, written next to its samples.
        rc, stext, cmd = cwm.run(self.cwm_exe, cwm.convert_args(c.cwm_source, "sfz", src, work),
                                 timeout)
        p["commands"].append(cwm.display_command(cmd))
        _write(os.path.join(logs, "convert_sfz.log"), stext)
        sfz_files = sorted(f for f in os.listdir(work) if f.lower().endswith(".sfz"))

        # 3. DecentSampler, sharing the SFZ's samples when they are byte-identical.
        ds_text = ""
        ds_files = []
        if self.write_ds and sfz_files:
            ds_dir = os.path.join(scratch, "ds")
            os.makedirs(ds_dir)
            rc, ds_text, cmd = cwm.run(
                self.cwm_exe, cwm.convert_args(c.cwm_source, "decentsampler", src, ds_dir), timeout)
            p["commands"].append(cwm.display_command(cmd))
            _write(os.path.join(logs, "convert_decentsampler.log"), ds_text)
            ds_files = self.merge_decentsampler(ds_dir, work, p)
        shutil.rmtree(scratch, ignore_errors=True)

        alltext = "\n".join([atext, stext, ds_text])
        for w in cwm.warning_lines(alltext):
            if w not in p["warnings"]:
                p["warnings"].append(w)
        if not sfz_files:
            low = alltext.lower()
            if "encrypt" in low:
                sc["status"], sc["reason"] = "encrypted", "encrypted: ConvertWithMoss can't read it"
            else:
                tail = [ln for ln in cwm.warning_lines(alltext)] or alltext.strip().splitlines()[-3:]
                sc["status"] = "failed"
                sc["reason"] = "no SFZ written: " + " | ".join(tail[-3:])
            sc["outputs"] = {"cwm_logs": "cwm"}
            sc["tags"] = build_tags(sc["identity"], [c.rel], [c.kind, sc["status"]])
            return

        presets, all_zones, group_names = [], [], []
        for f in sfz_files:
            with open(os.path.join(work, f), encoding="utf-8", errors="replace") as fh:
                parsed, zones = zones_from_sfz_text(fh.read())
            stem = f[:-4]
            ds = stem + ".dspreset"
            for z in zones:
                if z["sample"] and not os.path.isfile(os.path.join(work, z["sample"])):
                    p["warnings"].append(f"{f}: zone {z['index']} sample missing: {z['sample']}")
            presets.append({
                "name": parsed["global"].get("global_label") or stem,
                "sfz": f,
                "dspreset": ds if ds in ds_files else None,
                "sfz_header": parsed["comments"],
                "zones": zones,
            })
            all_zones += zones
            group_names += [z["group_label"] for z in zones if z["group_label"]]

        samples = []
        for dirpath, _, files in os.walk(work):
            if os.path.relpath(dirpath, work).split(os.sep)[0] in ("cwm",):
                continue
            for fn in sorted(files):
                if fn.lower().endswith(".wav"):
                    full = os.path.join(dirpath, fn)
                    rel = os.path.relpath(full, work).replace("\\", "/")
                    try:
                        info = read_wav_info(full)
                    except (OSError, ValueError) as e:
                        info = {"error": str(e)}
                    samples.append({"file": rel, "sha256": sha256_file(full), **info})
        samples.sort(key=lambda s: s["file"])

        meta = {}
        for a in analysis:
            for k, v in a["metadata"].items():
                meta.setdefault(k, v)
            group_names += [g["name"] for g in a["groups"]]
        ident = sc["identity"]
        ident["category"] = meta.get("category")
        ident["creator"] = meta.get("creator")
        ident["keywords"] = [k.strip() for k in meta.get("keywords", "").split(",") if k.strip()]
        ident["names_in_file"] = {
            "instruments": [a["name"] for a in analysis] or [pr["name"] for pr in presets],
            "groups": sorted(set(group_names)),
            "detected_as": sorted({a["detected"] for a in analysis if a.get("detected")}),
        }
        zsum = summarize_zones(all_zones, group_names)
        ssum = summarize_samples([s for s in samples if "error" not in s])
        sc["content"] = {
            "zones_summary": zsum,
            "samples_summary": ssum,
            "features_used": cwm.feature_lines(atext),
            "presets": presets,
            "samples": samples,
        }
        p["lost"] = self.lost_list(c, sc, zsum)
        sc["status"] = "converted"
        sc["outputs"] = {
            "sfz": sfz_files,
            "dspreset": ds_files,
            "samples_dirs": sorted({s["file"].split("/")[0] for s in samples if "/" in s["file"]}),
            "cwm_analysis": "cwm/analysis.txt",
            "cwm_logs": "cwm",
        }
        flags = [c.kind + "-converted", "sampler-instrument"]
        if zsum["looped"]:
            flags.append("looped")
        if zsum["velocity_layer_count"] > 1:
            flags.append("velocity-layered")
        if zsum["round_robin"]["likely"]:
            flags.append("round-robin")
        if len(zsum["root_notes"]) > 1:
            flags.append("multisampled")
        if zsum["release_trigger_zones"]:
            flags.append("release-triggers")
        if ssum["stereo"]:
            flags.append("stereo")
        if ssum["mono"]:
            flags.append("mono")
        if any(z["loop"]["mode"] == "one_shot" for z in all_zones):
            flags.append("one-shot")
        name_words = [c.rel] + group_names + [z["sample"] for z in all_zones[:2000]]
        sc["tags"] = build_tags(ident, name_words, flags, ident.get("category"),
                                ident.get("keywords") or [])

    def merge_decentsampler(self, ds_dir, work, p):
        """Move DecentSampler presets next to the SFZ, sharing identical sample files."""
        presets = sorted(f for f in os.listdir(ds_dir) if f.lower().endswith(".dspreset"))
        same = True
        for dirpath, _, files in os.walk(ds_dir):
            for fn in files:
                if fn.lower().endswith(".dspreset"):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ds_dir)
                twin = os.path.join(work, rel)
                if not (os.path.isfile(twin) and sha256_file(twin) == sha256_file(full)):
                    same = False
        if same:
            for f in presets:
                os.replace(os.path.join(ds_dir, f), os.path.join(work, f))
            return presets
        dest = os.path.join(work, "decentsampler")
        shutil.move(ds_dir, dest)
        p["warnings"].append("DecentSampler samples differ from the SFZ samples; kept "
                             "separately in decentsampler/")
        return [f"decentsampler/{f}" for f in presets]

    def lost_list(self, c, sc, zsum):
        lost = []
        rel = sc["origin"]["related_files"]
        if c.kind == "kontakt":
            lost += [
                "Kontakt scripts (KSP) are not converted: any scripted behaviour "
                "(round-robin logic, key switches, legato, UI controls) is gone.",
                "Kontakt effects (insert, send, bus) are not converted.",
                "Modulation beyond amp/pitch/filter envelopes, pitch/volume LFOs, pitch bend "
                "and velocity-to-volume is not converted.",
                "Kontakt group start options (round-robin cycling, key-switch conditions) are "
                "not written; groups keep their names.",
            ]
            if rel["resources"] or rel["scripts"]:
                lost.append("This instrument ships Kontakt resources/scripts ("
                            + ", ".join(rel["resources"] + rel["scripts"])
                            + "), so it relied on a script or custom UI that was not converted.")
        elif c.kind == "exs24":
            lost.append("EXS24 parameters beyond zones, loops, envelopes and filter may be lost.")
        elif c.kind == "sf2":
            lost.append("SoundFont modulators and generators that SFZ/DecentSampler can't "
                        "express are dropped.")
        if zsum["round_robin"]["groups_named_rr"] and not zsum["round_robin"]["seq_length"]:
            lost.append("Groups named like round robins (" + ", ".join(
                zsum["round_robin"]["groups_named_rr"]) + ") are stacked on the same keys; the "
                "cycling order is not in the SFZ.")
        if self.write_ds:
            lost.append("The .dspreset also contains ConvertWithMoss's default DecentSampler UI, "
                        "delay and reverb template; those are not from the source instrument.")
        return lost

    # -- catalog ------------------------------------------------------------------------

    def write_catalog(self):
        entries = []
        for c in self.coll.candidates:
            if self.excluded(c):
                entries.append({"id": c.out_rel, "status": "excluded", "kind": c.kind,
                                "source_path": c.rel, "out_path": c.out_rel,
                                "reason": "excluded with --exclude"})
                continue
            sc = self.existing_sidecar(c)
            if sc is None:
                entries.append({"id": c.out_rel, "status": "pending", "kind": c.kind,
                                "source_path": c.rel, "out_path": c.out_rel})
                continue
            entries.append(catalog_entry(c, sc))
        counts = _count(entries, "status")
        by_kind = _count(entries, "kind")
        orphans = self.unreferenced_ncw()
        cat = {
            "schema": SCHEMA, "tool": TOOL_NAME, "tool_version": TOOL_VERSION,
            "convertwithmoss_version": self.cwm_version, "generated": now_iso(),
            "source": self.source.replace("\\", "/"), "collection": self.collection,
            "license": self.license, "counts_by_status": counts, "counts_by_kind": by_kind,
            "unreferenced_ncw_count": len(orphans), "entries": entries,
        }
        write_json(os.path.join(self.out, "catalog.json"), cat)
        cols = ["id", "status", "kind", "source_path", "out_path", "family", "manufacturer",
                "model", "instrument", "patch", "category", "zone_count", "sample_count",
                "root_notes", "velocity_layers", "round_robin", "looped", "channels",
                "sample_rates", "bit_depths", "total_duration_s", "tags", "warnings", "reason"]
        with open(os.path.join(self.out, "catalog.csv"), "w", encoding="utf-8", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
            w.writeheader()
            for e in entries:
                row = {k: e.get(k) for k in cols}
                for k in ("root_notes", "channels", "sample_rates", "bit_depths", "tags"):
                    if isinstance(row.get(k), list):
                        row[k] = " ".join(str(x) for x in row[k])
                w.writerow(row)
        with open(os.path.join(self.out, "failures.txt"), "w", encoding="utf-8",
                  newline="\n") as f:
            bad = [e for e in entries if e["status"] in ("failed", "encrypted", "unsupported")]
            f.write(f"# {len(bad)} instruments not converted ({now_iso()})\n")
            for e in bad:
                f.write(f"{e['status']}\t{e['source_path']}\t{e.get('reason') or ''}\n")
        with open(os.path.join(self.out, "unreferenced_ncw.txt"), "w", encoding="utf-8",
                  newline="\n") as f:
            f.write("# .ncw samples no converted instrument maps (by file name); "
                    "these are not in the output\n")
            for o in orphans:
                f.write(o + "\n")
        lic = self.license.get("path")
        if lic:
            shutil.copyfile(os.path.join(self.source, lic),
                            os.path.join(self.out, "LICENSE-open-samples.md"))
        log.info("catalog: %d entries  %s", len(entries),
                 "  ".join(f"{k}={counts.get(k, 0)}" for k in STATUSES if counts.get(k)))
        if orphans:
            log.info("%d .ncw samples are not mapped by any converted instrument "
                     "(see unreferenced_ncw.txt)", len(orphans))

    def unreferenced_ncw(self):
        used = set()
        for c in self.coll.candidates:
            if c.kind not in CONVERTIBLE_KINDS:
                continue
            sc = self.existing_sidecar(c)
            if not sc or sc.get("status") != "converted":
                continue
            for s in sc["content"].get("samples", []):
                stem = s["file"].rsplit("/", 1)[-1].rsplit(".", 1)[0]
                used.add(re.sub(r"-\[\d+\]$", "", stem).lower())
        out = []
        for n in self.coll.ncw_files:
            if self._matches(n, self.args.exclude or []):
                continue
            stem = n.rsplit("/", 1)[-1].rsplit(".", 1)[0].lower()
            if stem not in used:
                out.append(n)
        return out


def load_additions(root):
    """Files added to the collection later (see README), keyed by path: {commit, source, date}."""
    path = os.path.join(root, ADDITIONS_FILE)
    out = {}
    if not os.path.isfile(path):
        return out
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return out
    for batch in data.get("additions", []):
        for f in batch.get("files", []):
            out[f["path"]] = {"source": batch.get("source"), "commit": batch.get("commit"),
                              "date": batch.get("date"), "sha256": f.get("sha256")}
    return out


def catalog_entry(c, sc):
    content = sc.get("content") or {}
    z = content.get("zones_summary") or {}
    s = content.get("samples_summary") or {}
    i = sc.get("identity") or {}
    return {
        "id": sc.get("id", c.out_rel), "status": sc.get("status"), "kind": c.kind,
        "source_path": c.rel, "out_path": c.out_rel,
        "source_sha256": sc.get("origin", {}).get("source_sha256"),
        "family": i.get("family"), "manufacturer": i.get("manufacturer"),
        "model": i.get("model"), "instrument": i.get("instrument"), "patch": i.get("patch"),
        "category": i.get("category"),
        "zone_count": z.get("zone_count"), "sample_count": s.get("sample_count"),
        "root_notes": z.get("root_notes") or content.get("notes_from_names"),
        "velocity_layers": z.get("velocity_layer_count"),
        "round_robin": (z.get("round_robin") or {}).get("likely"),
        "looped": z.get("looped") if z else content.get("looped_in_wav"),
        "channels": s.get("channels"), "sample_rates": s.get("sample_rates"),
        "bit_depths": s.get("bit_depths"), "total_duration_s": s.get("total_duration_s"),
        "tags": sc.get("tags"), "warnings": len(sc.get("processing", {}).get("warnings", [])),
        "reason": sc.get("reason"),
    }


def _write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def _count(items, key=None):
    out = {}
    for it in items:
        k = it.get(key) if key and isinstance(it, dict) else getattr(it, key) if key else it
        out[k] = out.get(k, 0) + 1
    return out
