"""Build the patch library's index (docs/plans/patch-library.md, Fields):

    python tools/patch_library/index.py [--library D:/12_library/gak/library] [--dry-run]

Reads the clean library (each patch's .json and .tres, written by export.py), the tables beside this script
(categories.json, emulation.json, creators.json, tags.json) and, when present, the analysis results
(<library>/analysis/features.json and categories.json), and writes <library>/gak_library.json: one entry per
patch with every field the browser filters on, and where each value came from. The file is rewritten only
when its content changes.
"""
import argparse
import fnmatch
import hashlib
import json
import os
import re
import sys
from collections import Counter

VERSION = 1
HERE = os.path.dirname(os.path.abspath(__file__))
# Sidecar tags that name the source, a bank or the conversion rather than the sound.
SOURCE_TAGS = {"synth1", "daichi-laboratory", "surge-xt", "helm", "ob-xd", "ob-xf", "tal-noisemaker", "obxd-banks",
	"obxf-factory", "patches-3rdparty", "patches-factory", "factory", "kvr-cleanzipbank", "daichi-factory",
	"daichi-rydsound", "casio", "casio-cz-101", "yamaha", "yamaha-dx7", "factory-patches"}


def slug(s):
	return re.sub(r"[^a-z0-9]+", "-", str(s).lower()).strip("-")


def load_table(name):
	with open(os.path.join(HERE, name), encoding="utf-8") as f:
		return json.load(f)


class Rules:
	def __init__(self):
		self.cat = load_table("categories.json")
		self.emu = load_table("emulation.json")
		self.cre = load_table("creators.json")
		self.keywords = [(c, [re.compile(p, re.I) for p in pats]) for c, pats in self.cat["keywords"].items()]
		self.emu_names = [(re.compile(p, re.I), mk, md) for p, mk, md in self.emu["names"]]
		self.suffixes = [(re.compile(p, re.I), c) for p, c in self.cre["suffixes"]]
		h = hashlib.sha256()
		for n in ("categories.json", "emulation.json", "creators.json"):
			with open(os.path.join(HERE, n), "rb") as f:
				h.update(f.read())
		self.hash = h.hexdigest()[:16]

	def keyword_categories(self, text):
		found = []
		for c, pats in self.keywords:
			if any(p.search(text) for p in pats):
				found.append(c)
		return found

	def category(self, m):
		"""(category, from, confidence, second guess) from the source's folder, the name or the bank."""
		folder = (m.get("source_folder") or "").strip().lower()
		if m["source"] in self.cat["declared_sources"] and folder in self.cat["folders"]:
			return self.cat["folders"][folder], "source", 1.0, ""
		name = re.sub(r"^\d+\s+", "", m["name"])
		found = self.keyword_categories(name)
		if found:
			return found[0], "name", 0.9 if len(found) == 1 else 0.6, found[1] if len(found) > 1 else ""
		found = [] if re.search(r"\+|&| and ", m["bank"]) else self.keyword_categories(m["bank"])
		if len(found) == 1:
			return found[0], "bank", 0.7, ""
		return "", "", 0.0, ""

	def emulation(self, m):
		bs = self.emu["by_source"].get(m["source"])
		if bs:
			return bs[0], bs[1], "source"
		for text in (m["name"], m["bank"]):
			for p, mk, md in self.emu_names:
				if p.search(text):
					return mk, md, "name"
		if m.get("maker") and m["source"] not in ("synth1", "surge", "helm", "obxf", "tal"):
			return m["maker"], m.get("model") or "", "source"
		return "", "", ""

	def creator(self, m):
		if m.get("author"):
			return m["author"], "patch"
		key = m["source"] + "/" + m["_bank_dir"]
		banks = self.cre["banks"]
		hit = banks.get(key)
		if hit is None:
			for pat, c in banks.items():
				if "*" in pat and fnmatch.fnmatchcase(key, pat):
					hit = c
					break
		if hit and "," not in hit:
			return hit, "bank"
		for p, c in self.suffixes:
			if p.search(m["name"]):
				return c, "name"
		if hit:
			return hit, "bank"
		if m["source"] in self.cre["by_source"]:
			return self.cre["by_source"][m["source"]], "source"
		return "", ""


def tres_facts(path):
	"""Playing facts read from the patch text: mono or legato, the arpeggiator."""
	with open(path, encoding="utf-8") as f:
		text = f.read()
	tags = []
	mm = re.search(r'^mode = "(\w+)"', text, re.M)
	if mm and mm.group(1) in ("mono", "legato"):
		tags.append("mono")
	am = re.search(r"^arp = \{(.*?)^\}", text, re.M | re.S)
	if am and am.group(1).strip() and not re.search(r'"on": false', am.group(1)):
		tags.append("arp")
	return tags


def build(library, rules):
	entries = []
	feats = {}
	ana_cat = {}
	fp = os.path.join(library, "analysis", "features.json")
	if os.path.exists(fp):
		with open(fp, encoding="utf-8") as f:
			feats = json.load(f).get("patches", {})
	cp = os.path.join(library, "analysis", "categories.json")
	if os.path.exists(cp):
		with open(cp, encoding="utf-8") as f:
			ana_cat = json.load(f).get("patches", {})
	for source in sorted(os.listdir(library)):
		top = os.path.join(library, source)
		if not os.path.isdir(top) or source == "analysis" or source.startswith("."):
			continue
		for bank_dir in sorted(os.listdir(top)):
			bdir = os.path.join(top, bank_dir)
			if not os.path.isdir(bdir):
				continue
			for fn in sorted(os.listdir(bdir)):
				if not fn.endswith(".json"):
					continue
				with open(os.path.join(bdir, fn), encoding="utf-8") as f:
					m = json.load(f)
				m["_bank_dir"] = bank_dir
				tres = os.path.join(bdir, fn[:-5] + ".tres")
				if not os.path.exists(tres):
					continue
				cat, cfrom, conf, alt = rules.category(m)
				facts = tres_facts(tres)
				if not cat and "arp" in facts:
					cat, cfrom, conf = "arp", "patch", 0.8
				if not cat and m["id"] in ana_cat:
					a = ana_cat[m["id"]]
					cat, cfrom, conf, alt = a["category"], "analysis", a["confidence"], a.get("alt", "")
				mk, md, efrom = rules.emulation(m)
				creator, crfrom = rules.creator(m)
				drop = SOURCE_TAGS | {slug(m["bank"]), slug(m["name"]), slug(bank_dir)}
				tags = sorted(set(t for t in m.get("tags", []) if t not in drop and not t.startswith("osc1-") or t in ("osc1-unison",)) | set(facts)
					| set((feats.get(m["id"]) or {}).get("tags", [])))
				sc = m.get("scores") or {}
				e = {
					"id": m["id"],
					"name": m["name"],
					"path": "%s/%s/%s" % (source, bank_dir, fn[:-5] + ".tres"),
					"source": m["source"],
					"origin": "ingested",
					"engine": m["engine"],
					"bank": m["bank"],
					"category": cat or "other",
					"category_from": cfrom,
					"category_conf": round(conf, 2),
					"category_alt": alt,
					"emulates_maker": mk,
					"emulates_model": md,
					"emulates_from": efrom,
					"creator": creator,
					"creator_from": crfrom,
					"tags": tags,
					"also_in": sorted({o["bank"] for o in m.get("also_in", []) if o.get("bank") != m["bank"]}),
					"dups": len(m.get("also_in", [])),
					"spec_err_db": sc.get("spec_err_db"),
					"snr_db": sc.get("snr_db"),
					"caveats": len(m.get("caveats") or []),
				}
				entries.append(e)
	return entries


def main():
	ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
	ap.add_argument("--library", default="D:/12_library/gak/library")
	ap.add_argument("--dry-run", action="store_true")
	a = ap.parse_args()
	rules = Rules()
	entries = build(a.library, rules)
	counts = {
		"patches": len(entries),
		"category_from": dict(Counter(e["category_from"] or "none" for e in entries)),
		"category": dict(Counter(e["category"] for e in entries)),
		"creator": sum(1 for e in entries if e["creator"]),
		"emulates": sum(1 for e in entries if e["emulates_maker"]),
		"emulates_from_name": sum(1 for e in entries if e["emulates_from"] == "name"),
		"by_source": dict(Counter(e["source"] for e in entries)),
	}
	doc = {"version": VERSION, "tables": rules.hash, "counts": counts, "patches": entries}
	text = json.dumps(doc, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
	out = os.path.join(a.library, "gak_library.json")
	old = None
	if os.path.exists(out):
		with open(out, encoding="utf-8") as f:
			old = f.read()
	print(json.dumps(counts, indent=1))
	if old == text:
		print("gak_library.json unchanged")
	elif not a.dry_run:
		tmp = out + ".tmp"
		with open(tmp, "w", encoding="utf-8", newline="\n") as f:
			f.write(text)
		os.replace(tmp, out)
		print("wrote %s (%d patches, %.1f MB)" % (out, len(entries), len(text.encode("utf-8")) / 1e6))


if __name__ == "__main__":
	main()
