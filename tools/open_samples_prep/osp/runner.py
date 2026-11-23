"""The batch run: plan, convert in parallel, write sidecars and the catalog."""

import base64
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

from . import SCHEMA, TOOL_NAME, TOOL_VERSION, cwm, cz, dx7, helm, korg, obxd, surge, synth1, tal
from .discover import discover, instrument_root, notes_for
from .sfz import zones_from_sfz_text
from .sidecar import (build_tags, guess_category, identity_for, notes_in_name, readme_text,
                      summarize_samples, summarize_zones)
from .slug import assign_out_paths, short_hash
from .wavinfo import read_wav_info

log = logging.getLogger("osp")

STATUSES = ["converted", "rendered", "decoded", "skipped-wav", "failed", "encrypted", "unsupported", "excluded",
            "pending"]
ADDITIONS_FILE = ".open_samples_additions.json"
CONVERTIBLE_KINDS = {"kontakt", "exs24", "sf2"}  # plus disk images (see Candidate.cwm_source)
DX7RENDER_DEFAULT = os.path.join("D:" + os.sep, "tools", "dx7render", "dx7render.exe")
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
    info = {"name": args.collection_name, "url": args.collection_url,
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


def license_info(root, note=None):
    path = os.path.join(root, "docs", "LICENSE.md")
    if not os.path.isfile(path):
        return {"name": note or "unknown (no licence file in the collection)", "path": None}
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
        self.dx7_exe = None
        self.dx7_sha = None

    # options that change output; part of every fingerprint
    def dx7_settings(self):
        a = self.args
        return {"notes": [int(x) for x in a.dx7_notes.split(",")],
                "velocities": [int(x) for x in a.dx7_velocities.split(",")],
                "hold_s": a.dx7_hold, "release_s": a.dx7_release, "gap_s": a.dx7_gap,
                "sample_rate": a.dx7_rate, "engine": a.dx7_engine}

    def options_for(self, cand):
        if cand.kind == "dx7-voice":
            return {"render": self.dx7_settings(), "renderer_sha256": self.dx7_sha}
        if cand.cwm_source:
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
        if cand.cwm_source:
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
        coll = discover(self.source, a.disk_images)
        mapping = assign_out_paths(
            (c.rel, c.is_file, c.kind, c.kind_suffix) for c in coll.candidates)
        for c in coll.candidates:
            c.out_rel = mapping[c.rel]
        self.coll = coll
        self.collection = collection_info(self.source, a)
        self.license = license_info(self.source, a.license_note)
        self.additions = load_additions(self.source)
        chosen = [c for c in coll.candidates if self.selected(c)]
        log.info("found %d instruments (%s); %d selected", len(coll.candidates),
                 ", ".join(f"{k} {n}" for k, n in sorted(_count(coll.candidates, "kind").items())),
                 len(chosen))

        if any(c.kind == "dx7-voice" for c in chosen):
            exe = a.dx7render or os.environ.get("OSP_DX7RENDER") or DX7RENDER_DEFAULT
            if not os.path.isfile(exe):
                raise SystemExit(f"dx7render not found at {exe}; build it with "
                                 "dx7render/build.ps1 or pass --dx7render")
            self.dx7_exe = os.path.abspath(exe)
            self.dx7_sha = sha256_file(self.dx7_exe)
            log.info("dx7render at %s (sha256 %s)", self.dx7_exe, self.dx7_sha[:12])
        needs_cwm = any(c.cwm_source for c in chosen)
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
                verb = {"do": "convert" if c.cwm_source else "render" if c.kind == "dx7-voice"
                        else "catalog",
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
        if c.voice is not None:
            return hashlib.sha256(bytes(c.voice["packed"])).hexdigest(), {}
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
        stem = c.source_file.rsplit("/", 1)[-1].rsplit(".", 1)[0].lower()
        description = None
        for n in notes:
            if n.rsplit("/", 1)[-1].lower().startswith("sound_list"):
                for line in read_text(os.path.join(self.source, n)).splitlines():
                    k, sep, v = line.partition("|")
                    if sep and k.strip().lstrip("\ufeff").lower() == stem:
                        description = v.strip()
        under = (lambda rel: root == "" or rel.startswith(root + "/"))
        size = None
        if c.is_file:
            try:
                size = os.path.getsize(os.path.join(self.source, c.source_file))
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
                "source_sha256_of": (
                    "file" if c.kind in ("synth1-patch", "helm-patch", "tal-patch", "surge-patch")
                    or (c.kind == "obxf-patch" and "#" not in c.rel)
                    else "the entry's own bytes (unpacked)" if c.voice is not None
                    else "file" if c.is_file and c.kind != "wav-folder"
                    else "manifest of '<path>\\t<sha256>' lines of the folder's WAV files"),
                "source_file": c.source_file,
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
            "identity": {**identity, **({"description": description} if description else {})},
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
        if c.kind == "dx7-voice":
            self.render_dx7(c, sc, work)
        elif c.kind in ("m3r-program", "m3r-combination", "cz-tone"):
            self.decode_patch(c, sc, work)
        elif c.kind == "synth1-patch":
            self.decode_synth1(c, sc)
        elif c.kind in ("helm-patch", "tal-patch", "obxf-patch", "surge-patch"):
            self.decode_vsynth(c, sc)
        elif c.cwm_source:
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
            if o.cwm_source:
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

    # -- patch data with no renderer yet (M3R, CZ) --------------------------------------

    def decode_patch(self, c, sc, work):
        e = c.voice
        raw = bytes(e["packed"])
        ident = sc["identity"]
        p = sc["processing"]
        flags = ["patch-data", "decoded"]
        if c.kind == "m3r-program":
            params = korg.program_params(raw)
            osc = params["oscillator"]
            ms = osc.get("multisound")
            basic = osc["mode"] == "multisound" and ms in korg.BASIC_WAVES
            sc["content"] = {"m3r_program": {
                "number": e["number"], "raw_hex": raw.hex(), "params": params,
                "direct_candidate": basic,
                "direct_wave": ({"shape": korg.BASIC_WAVES[ms],
                                 "width": korg.BASIC_WIDTH.get(ms)} if basic else None),
            }}
            wave = osc.get("multisound_name") or f"{osc['mode']} {osc['source']}"
            ident["category"] = guess_category(params["name"], wave)
            flags += ["korg", "m3r", "ai-synthesis",
                      "basic-wave" if basic else "pcm-wave", wave]
            p["lost"] = ["No M3R renderer: nothing was rendered. The oscillator is a PCM "
                         "multisound in the M3R's ROM" + (" (here a plain waveform, so it "
                                                          "converts directly)" if basic else
                                                          "; its sound has to come from analysis "
                                                          "or recordings") + ".",
                         "Envelope times and levels stay in the M3R's 0-99 units; their curves "
                         "in seconds aren't published in the manual."]
            if osc["source"] == "card":
                p["warnings"].append("uses a PCM card multisound, not in the M3R's own ROM")
        elif c.kind == "m3r-combination":
            params = korg.combi_params(raw)
            on = [t for t in params["timbres"] if t["on"]]
            sc["content"] = {"m3r_combination": {
                "number": e["number"], "raw_hex": raw.hex(), "params": params,
                "programs_in_this_bank": [t["program"] for t in on
                                          if t["program"] and t["program"].startswith("I")],
            }}
            ident["category"] = guess_category(params["name"])
            flags += ["korg", "m3r", "combination", params["type"].replace(" ", "-")
                      if isinstance(params["type"], str) else "combination"]
            p["lost"] = ["A combination layers or splits programs (\"I\" = this bank's programs, "
                         "\"C\" = a card's). Its effect settings are kept as raw bytes."]
        else:  # cz-tone
            d = cz.decode(raw)
            sc["content"] = {"cz_tone": {"tone_hex": raw.hex(), "size": len(raw), "params": cz.params(d),
                                         "named": cz.named(d)}}
            ident["category"] = guess_category(ident["patch"])
            flags += ["casio", "cz", "phase-distortion"]
            p["lost"] = ["The CZ firmware's part is documented, not known exactly (no ROM): how key follow "
                         "scales the envelopes, vibrato in Hz and cents, and the detune's fine steps "
                         "(osp/cz.py says what is known and what is guessed)."]
        sc["status"] = "decoded"
        sc["outputs"] = {}
        sc["tags"] = build_tags(ident, [ident["patch"]], flags, ident.get("category"))

    # -- Synth1 patches (no renderer here) ----------------------------------------------

    def decode_synth1(self, c, sc):
        e = c.voice
        parsed = e["parsed"]
        named = synth1.named_params(parsed)
        ident = sc["identity"]
        sc["content"] = {"synth1": {
            "number": e["number"], "name": parsed["name"], "color": parsed["color"],
            "version": parsed["version"], "params": named["params"], "names": named["names"],
            "defaulted": named["defaulted"], "features": named["features"],
            "unknown_lines": parsed["unknown"],
            "sound_sha256": synth1.sound_sha256(parsed["values"]),
            "file_text": e["packed"].decode("latin-1"),
        }}
        ident["category"] = guess_category(parsed["name"])
        p = sc["processing"]
        p["lost"] = ["Nothing is rendered here: the references come from "
                     "tools/patch_convert/render_synth1.py (Synth1 itself, through DawDreamer)."]
        if named["defaulted"]:
            p["warnings"].append(
                f"{len(named['defaulted'])} parameters aren't in the file (version "
                f"{parsed['version'] or 'unknown'}); they take Synth1 1.13's initial values")
        if parsed["unknown"]:
            p["warnings"].append(f"{len(parsed['unknown'])} lines weren't understood; "
                                 "kept in content.synth1.unknown_lines")
        n = named["names"]
        flags = ["synth1", "synth", "subtractive", "patch-data", "decoded",
                 n.get("osc1_shape"), n.get("osc2_shape"), n.get("filter_type")]
        flags += [f.split(" (")[0].replace(" -> ", " to ") for f in named["features"]]
        sc["status"] = "decoded"
        sc["outputs"] = {}
        sc["tags"] = build_tags(ident, [parsed["name"]], [f for f in flags if f],
                                ident.get("category"))

    # -- Helm, TAL-NoiseMaker, OB-Xd and OB-Xf patches (no renderer here) ---------------

    def decode_vsynth(self, c, sc):
        e = c.voice
        ident = sc["identity"]
        p = sc["processing"]
        if c.kind == "helm-patch":
            d = e["parsed"]
            named = helm.named_params(d)
            synth, key, script = "helm", "helm", "render_vsynth.py helm"
            sc["content"] = {"helm": {
                "name": e["name"], "author": d.get("author"), "license": d.get("license"),
                "folder": d.get("folder_name"), "synth_version": d.get("synth_version"),
                "params": named["params"], "modulations": named["modulations"], "names": named["names"],
                "features": named["features"], "sound_sha256": helm.sound_sha256(d),
                "file_text": e["packed"].decode("utf-8"),
            }}
            flags = ["helm", named["names"]["osc_1_waveform"]]
        elif c.kind == "tal-patch":
            t = e["parsed"]
            named = tal.named_params(t)
            synth, key = "TAL-NoiseMaker", "tal"
            sc["content"] = {"tal": {
                "name": t["name"], "xml_version": t["version"], "params": named["params"],
                "names": named["names"], "features": named["features"], "curve": t["curve"],
                "program_xml": t["program_xml"], "programs_in_file": t["programs_in_file"],
                "curprogram": t["curprogram"], "sound_sha256": tal.sound_sha256(t),
            }}
            flags = ["tal-noisemaker", named["names"].get("filtertype")]
        elif c.kind == "surge-patch":
            s = e["parsed"]
            named = surge.named_params(s)
            synth, key = "Surge XT", "surge"
            sc["content"] = {"surge": {
                "name": e["name"], "category": s["category"], "author": s["author"], "comment": s["comment"],
                "revision": s["revision"], "params": named["params"], "mods": s["mods"], "macros": s["macros"],
                "names": named["names"], "features": named["features"], "sound_sha256": surge.sound_sha256(s),
                "chunk_b64": base64.b64encode(s["chunk"]).decode("ascii"),
            }}
            flags = ["surge-xt"]
        else:
            prog, vals = e["parsed"], e["values"]
            synth, key = "OB-Xf", "obxf"
            raw = prog["raw"]
            sc["content"] = {"obxf": {
                "name": prog["name"], "source_format": prog["kind"], "program_index": prog["index"],
                "author": raw.get("author"), "category": raw.get("category"), "license": raw.get("license"),
                "params": vals, "names": obxd.names(vals), "features": obxd.features(vals),
                "import_warnings": e["warnings"], "raw": raw, "sound_sha256": e["sound_sha256"],
            }}
            named = {"features": sc["content"]["obxf"]["features"]}
            flags = ["ob-xf", "ob-xd" if prog["kind"] != "obxf" else None]
            p["warnings"] += ["OB-Xd import: " + w for w in e["warnings"]]
        ident["category"] = guess_category(e["name"], c.rel)
        p["lost"] = ["Nothing is rendered here: the references come from "
                     f"tools/patch_convert/render_vsynth.py ({synth} itself, through DawDreamer)."]
        flags = ["synth", "subtractive", "patch-data", "decoded"] + [f for f in flags if f]
        flags += [f.split(" (")[0].replace(" -> ", " to ") for f in named["features"]]
        sc["status"] = "decoded"
        sc["outputs"] = {}
        sc["tags"] = build_tags(ident, [e["name"]], flags, ident.get("category"))

    # -- DX7 voices ---------------------------------------------------------------------

    def render_dx7(self, c, sc, work):
        v = c.voice
        vced = bytes(v["vced"])
        st = self.dx7_settings()
        p = sc["processing"]
        p["renderer"] = {"path": self.dx7_exe, "sha256": self.dx7_sha,
                         "engine": "Dexed " + ("Mark I" if st["engine"] == "mki" else "msfa"),
                         "dexed_commit": _read_commit(self.dx7_exe)}
        # The voice itself, as a standard single-voice SysEx dump any DX7 or emulator loads.
        single = bytes([0xF0, 0x43, 0x00, 0x00, 0x01, 0x1B]) + vced + bytes(
            [(-sum(vced)) & 0x7F, 0xF7])
        with open(os.path.join(work, "voice.syx"), "wb") as f:
            f.write(single)
        tmp = os.path.join(work, "_voice.bin")
        with open(tmp, "wb") as f:
            f.write(vced + bytes([0x3F]))
        renders = []
        notes = st["notes"]
        for vel in st["velocities"]:
            name = f"render_v{vel:03d}.wav"
            args = [tmp, os.path.join(work, name), "--notes", ",".join(map(str, notes)),
                    "--velocity", str(vel), "--hold", str(st["hold_s"]),
                    "--release", str(st["release_s"]), "--gap", str(st["gap_s"]),
                    "--rate", str(st["sample_rate"]), "--engine", st["engine"]]
            rc, text, cmd = cwm.run(self.dx7_exe, args, self.args.timeout)
            p["commands"].append(cwm.display_command(cmd))
            if rc != 0 or not os.path.isfile(os.path.join(work, name)):
                p["warnings"].append(f"render at velocity {vel} failed: {text.strip()[:300]}")
                continue
            info = read_wav_info(os.path.join(work, name))
            renders.append({"file": name, "velocity": vel,
                            "sha256": sha256_file(os.path.join(work, name)), **info})
        os.remove(tmp)
        params = dx7.named_params(vced)
        ident = sc["identity"]
        if not renders:
            sc["status"], sc["reason"] = "failed", "dx7render produced nothing"
            sc["tags"] = build_tags(ident, [params["name"]], ["dx7", "failed"])
            return
        step = notes[1] - notes[0] if len(notes) > 1 else 0
        uniform = all(b - a == step for a, b in zip(notes, notes[1:]))
        per = st["hold_s"] + st["release_s"] + st["gap_s"]
        sc["content"] = {
            "dx7": {
                "voice_number": v["index"],
                "name": params["name"],
                "sound_sha256": hashlib.sha256(vced[:145]).hexdigest(),
                "packed_hex": bytes(v["packed"]).hex(),
                "vced_hex": vced.hex(),
                "carriers": dx7.CARRIERS.get(params["algorithm"]),
                "params": params,
            },
            "render": {
                **st,
                "layout": "held notes in this order, each held hold_s, released and left to "
                          "ring release_s, then gap_s of silence",
                "first_note": notes[0],
                "step": step if uniform else None,
                "note_onsets_s": [round(i * per, 6) for i in range(len(notes))],
                "note_off_s": [round(i * per + st["hold_s"], 6) for i in range(len(notes))],
                "sounding_offset_semitones": params["transpose_semitones"],
                "files": renders,
            },
            "samples_summary": summarize_samples(renders),
        }
        ident["category"] = guess_category(params["name"])
        p["lost"] = [
            "Renders come from Dexed's DX7 emulation, not from hardware.",
            "Only the voice is rendered: performance settings that live outside a voice "
            "(pitch bend range, portamento, mono mode, mod wheel/breath/foot/aftertouch routing) "
            "are not part of it, and every controller stays at 0.",
        ]
        if params["transpose_semitones"]:
            p["warnings"].append(f"voice transpose {params['transpose_semitones']:+d} semitones "
                                 "is applied: the render notes sound shifted by that much")
        sc["status"] = "rendered"
        sc["outputs"] = {"voice_syx": "voice.syx", "renders": [r["file"] for r in renders]}
        flags = ["dx7", "fm", "synth", "rendered", f"algorithm-{params['algorithm']}"]
        if params["lfo"]["pitch_mod_depth"] and params["lfo"]["pitch_mod_sensitivity"]:
            flags.append("vibrato")
        sc["tags"] = build_tags(ident, [params["name"], ident["instrument"]], flags,
                                ident["category"])

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
        name_words = ([c.rel, ident.get("description") or ""] + group_names
                      + [z["sample"] for z in all_zones[:2000]])
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
        elif c.kind == "mirage":
            lost.append("Mirage disks don't store root notes: the zones' root keys are "
                        "ConvertWithMoss placeholders, so pitch has to be found from the audio.")
            lost.append("Mirage programs and wavesample settings are mapped as far as "
                        "ConvertWithMoss reads them; the samples are the Mirage's 8-bit originals.")
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
        first_by_sound = {}
        for e in entries:
            snd = e.pop("_sound", None)
            if snd:
                if snd in first_by_sound:
                    e["duplicate_of"] = first_by_sound[snd]
                else:
                    first_by_sound[snd] = e["id"]
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
            if not c.cwm_source:
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
        "root_notes": (z.get("root_notes") or content.get("notes_from_names")
                       or (content.get("render") or {}).get("notes")),
        "velocity_layers": z.get("velocity_layer_count"),
        "round_robin": (z.get("round_robin") or {}).get("likely"),
        "looped": z.get("looped") if z else content.get("looped_in_wav"),
        "channels": s.get("channels"), "sample_rates": s.get("sample_rates"),
        "bit_depths": s.get("bit_depths"), "total_duration_s": s.get("total_duration_s"),
        "tags": sc.get("tags"), "warnings": len(sc.get("processing", {}).get("warnings", [])),
        "reason": sc.get("reason"),
        "_sound": _sound_key(content),
    }


def _sound_key(content):
    """Same sound, other name: a key for duplicate marking (DX7 voices, M3R programs)."""
    if content.get("dx7"):
        return content["dx7"].get("sound_sha256")
    if content.get("synth1"):
        return "synth1:" + content["synth1"]["sound_sha256"]
    for k in ("helm", "tal", "obxf"):
        if content.get(k):
            return k + ":" + content[k]["sound_sha256"]
    m = content.get("m3r_program")
    if m:
        return "m3r:" + hashlib.sha256(bytes.fromhex(m["raw_hex"])[10:]).hexdigest()
    return None


def _read_commit(exe):
    p = os.path.join(os.path.dirname(exe), "COMMIT")
    try:
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def _write(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def _count(items, key=None):
    out = {}
    for it in items:
        k = it.get(key) if key and isinstance(it, dict) else getattr(it, key) if key else it
        out[k] = out.get(k, 0) + 1
    return out
