"""Copy the converted patches out of the work folders into the clean library (docs/plans/patch-library.md,
"The clean library"):

    python tools/patch_library/export.py [--work D:/12_library/gak] [--out D:/12_library/gak/library] [--dry-run]

Every gak_patch.tres beside an instrument.json sidecar in a known work folder goes to
<out>/<source>/<bank>/<number> <name>.tres, with a small <number> <name>.json beside it, and each bank
gets a BANK.txt (its readme, creator and licence). Duplicates (the same sound in two banks) are copied
once; the copy lists the others in `also_in`. A rerun rewrites only what changed and removes patches no
longer in any work folder. Nothing outside <out> is written, and in <out> only the source folders and
README.md are touched (the index and analysis files are left alone).
"""
import argparse
import collections
import hashlib
import json
import os
import re
import statistics
import sys

VERSION = 1

# Work folder -> (source, engine). A work folder may hold several sources (DX7 and Mirage), so the
# sidecar's own kind decides; this maps a sidecar `origin.source_kind` to the source.
KINDS = {
	"synth1-patch": ("synth1", "Synth1"),
	"surge-patch": ("surge", "Surge XT"),
	"helm-patch": ("helm", "Helm"),
	"obxf-patch": ("obxf", "OB-Xf"),
	"tal-patch": ("tal", "TAL-NoiseMaker"),
	"dx7-voice": ("dx7", "DX7"),
	"cz-tone": ("cz", "CZ-101"),
}
WORK_FOLDERS = ["processed_synth1", "processed_surge", "processed_helm", "processed_obx", "processed_tal",
	"processed_soundarchive", "processed_polynominal", "processed"]
# Sidecar tags that say nothing about the sound.
DROP_TAGS = {"decoded", "patch-data", "synth", "subtractive", "unsupported", "sampler-instrument"}
SOURCE_NAMES = {"synth1": "Synth1 (Daichi Laboratory)", "surge": "Surge XT", "helm": "Helm (Matt Tytel)",
	"obxf": "OB-Xd / OB-Xf", "tal": "TAL-NoiseMaker", "dx7": "Yamaha DX7", "cz": "Casio CZ-101"}


def safe(name, limit=80):
	"""A file or folder name: no characters Windows refuses, no trailing dots or spaces, single spaces."""
	s = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "-", str(name))
	s = re.sub(r"\s+", " ", s).strip(" .")
	return (s[:limit].rstrip(" .") or "untitled")


def load_json(path):
	with open(path, encoding="utf-8") as f:
		return json.load(f)


def file_sha(path):
	h = hashlib.sha256()
	with open(path, "rb") as f:
		h.update(f.read())
	return h.hexdigest()


def median_of(notes, key):
	vals = [n[key] for n in notes if isinstance(n, dict) and isinstance(n.get(key), (int, float))]
	return round(statistics.median(vals), 2) if vals else None


def scores(report):
	"""The conversion's scores, as the checkers report them (medians over notes)."""
	if not report:
		return {}
	out = {}
	if "snr_median_db" in report:
		out["snr_db"] = report["snr_median_db"]
	notes = report.get("notes") or []
	for key, name in (("level_db", "level_db"), ("env_err_db", "env_err_db"), ("spec_err_db", "spec_err_db")):
		v = report.get(key + "_median")
		if v is None:
			v = median_of(notes, key)
		if v is not None:
			out[name] = v
	return out


def describe(work_dir, sidecar_dir):
	"""One converted patch: everything the library needs from its work folder, or None."""
	sc = load_json(os.path.join(sidecar_dir, "instrument.json"))
	origin = sc.get("origin") or {}
	kind = origin.get("source_kind")
	if kind not in KINDS:
		return None
	source, engine = KINDS[kind]
	ident = sc.get("identity") or {}
	content = sc.get("content") or {}
	body = content.get({"dx7": "dx7", "cz": "cz_tone"}.get(source, source)) or {}
	name = (body.get("name") if isinstance(body, dict) else None) or ident.get("patch") or sc["id"].split("/")[-1]
	name = re.sub(r"\s+", " ", str(name)).strip()
	number = None
	for key in ("number", "voice_number", "program_index"):
		if isinstance(body, dict) and body.get(key) not in (None, ""):
			number = body.get(key)
			break
	if number is None and ident.get("number") not in (None, ""):
		number = ident.get("number")
	if source == "obxf" and isinstance(number, int):
		# program_index is 0-based in a bank (.fxb); a single patch file (.fxp) has no number.
		is_bank = (origin.get("source_path") or "").split("#")[0].lower().endswith(".fxb")
		number = number + 1 if is_bank else None
	folders = ident.get("folders") or []
	# The bank: the source's own grouping, as a folder.
	if source == "synth1":
		bank = ident.get("instrument") or "bank"
	elif source == "surge":
		fam = ident.get("family") or ""
		bank = "factory" if "factory" in fam else "third-party " + (folders[0] if folders else "unknown")
	elif source in ("helm", "tal"):
		bank = ident.get("family") or "factory"
	elif source == "obxf":
		# A bank file (.fxb) is the bank; a single patch file (.fxp) belongs to its folder.
		sf = (origin.get("source_path") or "").split("#")[0].replace("\\", "/")
		base, ext = os.path.splitext(os.path.basename(sf))
		bank = base if ext.lower() == ".fxb" else "factory " + (os.path.basename(os.path.dirname(sf)) or "patches")
	elif source == "dx7":
		bank = ident.get("instrument") or "cartridge"
	else:  # cz
		bank = folders[0] if folders else "tones"
	author = body.get("author") if isinstance(body, dict) else None
	category = ident.get("category")
	if source == "helm" and not category and folders:
		category = folders[0]
	if isinstance(body, dict) and not category and body.get("category"):
		category = body.get("category")
	if category in ("Unknown", ""):
		category = None
	report_path = os.path.join(sidecar_dir, "gak_report.json")
	report = load_json(report_path) if os.path.exists(report_path) else {}
	notes_text = []
	for n in origin.get("notes") or []:
		if isinstance(n, dict) and n.get("text"):
			notes_text.append((n.get("path") or "", n["text"]))
	return {
		"id": source + ":" + sc["id"],
		"source": source,
		"engine": engine,
		"name": name,
		"number": number,
		"bank": str(bank),
		"source_category": category,
		"author": author or None,
		"maker": ident.get("manufacturer"),
		"model": ident.get("model"),
		"license": (origin.get("license") or {}).get("name"),
		"source_file": origin.get("source_path"),
		"source_sha256": origin.get("source_sha256"),
		"sound_sha256": body.get("sound_sha256") if isinstance(body, dict) else None,
		"converter": report.get("converter"),
		"scores": scores(report),
		"caveats": report.get("caveats") or [],
		"tags": sorted(t for t in (sc.get("tags") or []) if t not in DROP_TAGS),
		"_tres": os.path.join(sidecar_dir, "gak_patch.tres"),
		"_notes": notes_text,
		"_work": work_dir,
	}


def gather(work_root):
	found = []
	for wf in WORK_FOLDERS:
		top = os.path.join(work_root, wf)
		if not os.path.isdir(top):
			continue
		for root, dirs, files in os.walk(top):
			dirs[:] = [d for d in dirs if not d.startswith(".") and d != "logs"]
			if "gak_patch.tres" in files and "instrument.json" in files:
				try:
					d = describe(wf, root)
				except (ValueError, KeyError, OSError) as e:
					print("skipped %s: %s" % (root, e), file=sys.stderr)
					continue
				if d:
					found.append(d)
	return found


def tres_key(path):
	"""A duplicate key for patches without a sound fingerprint: the .tres without its name."""
	with open(path, encoding="utf-8") as f:
		text = re.sub(r'^resource_name = .*$', "", f.read(), flags=re.M)
	return hashlib.sha256(text.encode("utf-8")).hexdigest()


def plan(patches):
	"""Fold duplicates and give each kept patch its place: {relative path stem: patch}."""
	by_source = collections.defaultdict(list)
	for p in patches:
		by_source[p["source"]].append(p)
	placed = {}
	for source, items in sorted(by_source.items()):
		items.sort(key=lambda p: p["id"])
		groups = collections.OrderedDict()
		for p in items:
			key = p["sound_sha256"] or tres_key(p["_tres"])
			groups.setdefault(key, []).append(p)
		used = set()
		for group in groups.values():
			keep = group[0]
			keep["also_in"] = [{"id": o["id"], "bank": o["bank"], "name": o["name"]} for o in group[1:]]
			bank_dir = safe(keep["bank"])
			stem = (("%03d " % keep["number"]) if isinstance(keep["number"], int) else
				(str(keep["number"]) + " " if keep["number"] not in (None, "") else "")) + keep["name"]
			stem = safe(stem)
			rel = "%s/%s/%s" % (source, bank_dir, stem)
			k = 2
			while rel.lower() in used:
				rel = "%s/%s/%s (%d)" % (source, bank_dir, stem, k)
				k += 1
			used.add(rel.lower())
			placed[rel] = keep
	return placed


def meta_json(p, rel):
	m = {k: v for k, v in p.items() if not k.startswith("_")}
	m["path"] = rel + ".tres"
	m["exporter"] = VERSION
	return json.dumps(m, indent=1, ensure_ascii=False, sort_keys=True) + "\n"


def bank_text(source, bank, members):
	lines = ["%s: %s" % (SOURCE_NAMES.get(source, source), bank), ""]
	authors = sorted({p["author"] for p in members if p.get("author")})
	if authors:
		lines.append("Creator%s: %s" % ("s" if len(authors) > 1 else "", ", ".join(authors)))
	lic = sorted({p["license"] for p in members if p.get("license")})
	for l in lic:
		lines.append("Licence: " + l)
	lines.append("Patches: %d" % len(members))
	notes = collections.OrderedDict()
	for p in members:
		for path, text in p["_notes"]:
			notes.setdefault(path, text)
	for path, text in notes.items():
		lines += ["", "--- %s ---" % path, text.replace("\r\n", "\n").rstrip()]
	return "\n".join(lines) + "\n"


def write_if_changed(path, data, dry, counts, key):
	"""Write text or bytes when it differs from what's there; count what happened."""
	b = data.encode("utf-8") if isinstance(data, str) else data
	if os.path.exists(path):
		with open(path, "rb") as f:
			if f.read() == b:
				counts[key + "_same"] += 1
				return
		counts[key + "_changed"] += 1
	else:
		counts[key + "_new"] += 1
	if not dry:
		os.makedirs(os.path.dirname(path), exist_ok=True)
		tmp = path + ".tmp"
		with open(tmp, "wb") as f:
			f.write(b)
		os.replace(tmp, path)


def main():
	ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
	ap.add_argument("--work", default="D:/12_library/gak")
	ap.add_argument("--out", default="D:/12_library/gak/library")
	ap.add_argument("--dry-run", action="store_true")
	a = ap.parse_args()
	out = os.path.abspath(a.out)
	patches = gather(a.work)
	placed = plan(patches)
	counts = collections.Counter()
	wanted = set()
	banks = collections.defaultdict(list)
	for rel, p in sorted(placed.items()):
		with open(p["_tres"], "rb") as f:
			tres = f.read()
		tpath = os.path.join(out, rel + ".tres")
		write_if_changed(tpath, tres, a.dry_run, counts, "tres")
		write_if_changed(os.path.join(out, rel + ".json"), meta_json(p, rel), a.dry_run, counts, "json")
		wanted.add(os.path.normcase(os.path.join(out, rel + ".tres")))
		wanted.add(os.path.normcase(os.path.join(out, rel + ".json")))
		banks[(p["source"], rel.split("/")[1], p["bank"])].append(p)
		for o in p["also_in"]:
			banks[(p["source"], rel.split("/")[1], o["bank"])]  # noqa: the bank exists through its duplicates
	for (source, bank_dir, bank), members in banks.items():
		if not members:
			continue
		bpath = os.path.join(out, source, bank_dir, "BANK.txt")
		if os.path.normcase(bpath) in wanted:
			continue  # a second bank name folding into the same folder: the first one's text stands
		write_if_changed(bpath, bank_text(source, bank, members), a.dry_run, counts, "bank")
		wanted.add(os.path.normcase(bpath))
	# Remove what no work folder produces any more (only in the source folders, only our files).
	for source in set(KINDS[k][0] for k in KINDS):
		top = os.path.join(out, source)
		if not os.path.isdir(top):
			continue
		for root, dirs, files in os.walk(top, topdown=False):
			for f in files:
				fp = os.path.normcase(os.path.join(root, f))
				if fp not in wanted and (f.endswith((".tres", ".json", ".tmp")) or f == "BANK.txt"):
					counts["removed"] += 1
					if not a.dry_run:
						os.remove(fp)
			if not a.dry_run and root != top and not os.listdir(root):
				os.rmdir(root)
	# Counts per source, into README.md.
	per = collections.Counter(p["source"] for p in placed.values())
	folded = collections.Counter()
	for p in placed.values():
		folded[p["source"]] += len(p["also_in"])
	total_in = collections.Counter(p["source"] for p in patches)
	rows = ["| %s | %d | %d | %d | %d |" % (SOURCE_NAMES[s], total_in[s], folded[s], per[s],
		len({rel.split("/")[1] for rel, p in placed.items() if p["source"] == s})) for s in sorted(per)]
	licences = collections.Counter((p["source"], p["license"]) for p in placed.values())
	lic_rows = ["- %s: %s (%d)" % (SOURCE_NAMES[s], l or "unknown", n) for (s, l), n in sorted(licences.items(), key=lambda x: (x[0][0], str(x[0][1])))]
	readme = "\n".join([
		"# GAK patch library",
		"",
		"Every patch the converters have made, copied out of the work folders by `tools/patch_library/export.py` "
		"(godot-audio-kit; plan in `docs/plans/patch-library.md`). Don't edit files here by hand: the next export "
		"rewrites them. Rerun the export after a converter improves.",
		"",
		"Layout: `<source>/<bank>/<number> <name>.tres` (the patch, an `AKPatch`; it loads in any project with the "
		"addon), the `.json` beside it (name, source, bank, declared category, author, licence, provenance, the "
		"conversion's scores and caveats, `also_in`: duplicates in other banks, copied once), and `BANK.txt` per bank "
		"(its readme, creator and licence). `gak_library.json` is the index and `analysis/` the analysis features; "
		"the export leaves them alone.",
		"",
		"| Source | Converted | Duplicates folded | In the library | Banks |",
		"| --- | --- | --- | --- | --- |",
	] + rows + [
		"| **All** | %d | %d | %d | |" % (len(patches), sum(folded.values()), len(placed)),
		"",
		"## Licences",
		"",
		"Most collections are shared for personal use only; keep this library personal.",
		"",
	] + lic_rows) + "\n"
	write_if_changed(os.path.join(out, "README.md"), readme, a.dry_run, counts, "readme")
	print("%d converted patches, %d in the library (%d duplicates folded)" % (len(patches), len(placed), sum(folded.values())))
	for s in sorted(per):
		print("  %-7s %6d converted, %6d kept" % (s, total_in[s], per[s]))
	print("files: " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
	if a.dry_run:
		print("(dry run: nothing written)")


if __name__ == "__main__":
	main()
