"""What a drum sample is, from its name: category (kick, snare, hat ...) and a finer kind.

A file's own name is read first, then its folders from the nearest up, then the machine's
name map (tools/drum_prep/name_maps/<Machine>.json) for sets whose names are codes.
Every result says which rule decided it, so later steps (analysis) can tell a guess from
a name that says so plainly.
"""

import re

CATEGORIES = ["kick", "snare", "rim", "clap", "hat", "cymbal", "tom", "perc", "fx", "vox",
              "loop", "tonal"]

# Whole tokens (after splitting camelCase, digits and punctuation) -> (category, kind).
TOKENS = {
    # kicks
    "kick": ("kick", ""), "kicks": ("kick", ""), "kik": ("kick", ""), "kick drum": ("kick", ""),
    "bd": ("kick", ""), "bdrum": ("kick", ""), "kck": ("kick", ""), "kk": ("kick", ""),
    "bassdrum": ("kick", ""), "bassdrums": ("kick", ""), "kickdrum": ("kick", ""), "ebd": ("kick", "electronic"),
    "acbd": ("kick", "acoustic"), "bdr": ("kick", ""), "bas": ("kick", ""),
    # snares
    "snare": ("snare", ""), "snares": ("snare", ""), "snr": ("snare", ""), "sn": ("snare", ""),
    "sd": ("snare", ""), "snaredrum": ("snare", ""), "esn": ("snare", "electronic"), "esnare": ("snare", "electronic"),
    "acsn": ("snare", "acoustic"), "snar": ("snare", ""), "sna": ("snare", ""), "sds": ("snare", ""),
    # rim
    "rim": ("rim", "rimshot"), "rimshot": ("rim", "rimshot"), "rimshots": ("rim", "rimshot"), "rs": ("rim", "rimshot"),
    "sidestick": ("rim", "sidestick"), "stick": ("rim", "sidestick"), "xstick": ("rim", "sidestick"),
    "rimclick": ("rim", "sidestick"), "rimsht": ("rim", "rimshot"),
    # claps
    "clap": ("clap", ""), "claps": ("clap", ""), "clp": ("clap", ""), "cp": ("clap", ""),
    "handclap": ("clap", ""), "handclaps": ("clap", ""), "snap": ("clap", "snap"), "snaps": ("clap", "snap"),
    "fingersnap": ("clap", "snap"),
    # hats
    "hat": ("hat", ""), "hats": ("hat", ""), "hihat": ("hat", ""), "hihats": ("hat", ""), "hh": ("hat", ""),
    "hhat": ("hat", ""), "highhat": ("hat", ""), "chh": ("hat", "closed"), "ohh": ("hat", "open"),
    "phh": ("hat", "pedal"), "ch": ("hat", "closed"), "oh": ("hat", "open"), "ph": ("hat", "pedal"),
    "hhopen": ("hat", "open"), "hhclosed": ("hat", "closed"), "hho": ("hat", "open"), "hhc": ("hat", "closed"),
    "hhp": ("hat", "pedal"), "openhat": ("hat", "open"), "closedhat": ("hat", "closed"), "pedalhat": ("hat", "pedal"),
    "hht": ("hat", ""), "hi-hat": ("hat", ""),
    # cymbals
    "cymbal": ("cymbal", ""), "cymbals": ("cymbal", ""), "cym": ("cymbal", ""), "cymb": ("cymbal", ""),
    "cy": ("cymbal", ""), "crash": ("cymbal", "crash"), "crashes": ("cymbal", "crash"), "cr": ("cymbal", "crash"),
    "ride": ("cymbal", "ride"), "rides": ("cymbal", "ride"), "rd": ("cymbal", "ride"), "rc": ("cymbal", "ride"),
    "china": ("cymbal", "china"), "splash": ("cymbal", "splash"), "spl": ("cymbal", "splash"),
    "gong": ("cymbal", "gong"), "gongs": ("cymbal", "gong"), "cup": ("cymbal", "ride_bell"),
    "ridebell": ("cymbal", "ride_bell"), "sizzle": ("cymbal", "ride"), "crsh": ("cymbal", "crash"),
    # toms
    "tom": ("tom", ""), "toms": ("tom", ""), "tm": ("tom", ""), "tomlo": ("tom", "low"), "tomhi": ("tom", "high"),
    "tommid": ("tom", "mid"), "lotom": ("tom", "low"), "hitom": ("tom", "high"), "midtom": ("tom", "mid"),
    "lt": ("tom", "low"), "mt": ("tom", "mid"), "ht": ("tom", "high"), "ft": ("tom", "floor"),
    "dtom": ("tom", "electronic"), "floortom": ("tom", "floor"), "rototom": ("tom", "roto"), "roto": ("tom", "roto"),
    "ton": ("tom", ""), "timpani": ("tom", "timpani"),
    # percussion
    "perc": ("perc", ""), "percs": ("perc", ""), "percussion": ("perc", ""), "percussions": ("perc", ""),
    "prc": ("perc", ""), "acperc": ("perc", "acoustic"), "eperc": ("perc", "electronic"), "per": ("perc", ""),
    "cowbell": ("perc", "cowbell"), "cowb": ("perc", "cowbell"), "cow": ("perc", "cowbell"), "cb": ("perc", "cowbell"),
    "clave": ("perc", "clave"), "claves": ("perc", "clave"), "cl": None,
    "conga": ("perc", "conga"), "congas": ("perc", "conga"), "cga": ("perc", "conga"), "tumba": ("perc", "conga"),
    "quinto": ("perc", "conga"),
    "bongo": ("perc", "bongo"), "bongos": ("perc", "bongo"), "bgo": ("perc", "bongo"),
    "timbale": ("perc", "timbale"), "timbales": ("perc", "timbale"), "timb": ("perc", "timbale"),
    "agogo": ("perc", "agogo"), "agogos": ("perc", "agogo"),
    "shaker": ("perc", "shaker"), "shakers": ("perc", "shaker"), "shk": ("perc", "shaker"), "shake": ("perc", "shaker"),
    "maracas": ("perc", "shaker"), "maraca": ("perc", "shaker"), "cabasa": ("perc", "shaker"), "afuche": ("perc", "shaker"),
    "tambourine": ("perc", "tambourine"), "tamb": ("perc", "tambourine"), "tambo": ("perc", "tambourine"),
    "tamborine": ("perc", "tambourine"), "tam": ("perc", "tambourine"), "pandeiro": ("perc", "tambourine"),
    "pandiero": ("perc", "tambourine"), "riq": ("perc", "tambourine"),
    "triangle": ("perc", "triangle"), "tri": ("perc", "triangle"), "trngl": ("perc", "triangle"),
    "woodblock": ("perc", "woodblock"), "block": ("perc", "woodblock"), "blk": ("perc", "woodblock"),
    "templeblock": ("perc", "woodblock"), "guiro": ("perc", "guiro"), "cuica": ("perc", "cuica"),
    "whistle": ("perc", "whistle"), "whistles": ("perc", "whistle"), "apito": ("perc", "whistle"),
    "tabla": ("perc", "tabla"), "tablah": ("perc", "tabla"), "baya": ("perc", "tabla"), "dholak": ("perc", "hand_drum"),
    "djembe": ("perc", "hand_drum"), "doumbek": ("perc", "hand_drum"), "darbuka": ("perc", "hand_drum"),
    "dumbek": ("perc", "hand_drum"), "udu": ("perc", "hand_drum"), "taiko": ("perc", "hand_drum"),
    "surdo": ("perc", "hand_drum"), "frame": None, "bodhran": ("perc", "hand_drum"), "cajon": ("perc", "hand_drum"),
    "talking": None, "vibraslap": ("perc", "vibraslap"), "vibra": None, "chimes": ("perc", "chimes"),
    "chime": ("perc", "chimes"), "windchime": ("perc", "chimes"), "bell": ("perc", "bell"), "bells": ("perc", "bell"),
    "castanet": ("perc", "castanet"), "castanets": ("perc", "castanet"), "quijada": ("perc", "vibraslap"),
    "slapstick": ("perc", "woodblock"), "metal": None, "anvil": ("perc", "metal"), "bongs": ("perc", "bongo"),
    "sleighbell": ("perc", "bell"), "jingle": ("perc", "bell"), "glockenspiel": ("tonal", "mallet"),
    "marimba": ("tonal", "mallet"), "vibes": ("tonal", "mallet"), "xylophone": ("tonal", "mallet"),
    "kalimba": ("tonal", "mallet"), "steeldrum": ("tonal", "mallet"), "bata": ("perc", "hand_drum"),
    "vibraphone": ("tonal", "mallet"), "celeste": ("tonal", "mallet"), "celesta": ("tonal", "mallet"),
    "glock": ("tonal", "mallet"), "tambura": ("tonal", "drone"), "tanpura": ("tonal", "drone"),
    "sitar": ("tonal", "pluck"), "koto": ("tonal", "pluck"), "harp": ("tonal", "pluck"),
    "tamborim": ("perc", "hand_drum"),
    # fx
    "fx": ("fx", ""), "sfx": ("fx", ""), "efx": ("fx", ""), "effect": ("fx", ""), "effects": ("fx", ""),
    "zap": ("fx", "zap"), "zaps": ("fx", "zap"), "laser": ("fx", "zap"), "scratch": ("fx", "scratch"),
    "scratches": ("fx", "scratch"), "noise": ("fx", "noise"), "noiz": ("fx", "noise"), "sweep": ("fx", "sweep"),
    "riser": ("fx", "sweep"), "reverse": None, "rev": None, "blip": ("fx", "blip"), "blips": ("fx", "blip"),
    "glitch": ("fx", ""), "explosion": ("fx", ""), "gun": ("fx", ""), "gunshot": ("fx", ""), "siren": ("fx", ""),
    "thunder": ("fx", ""), "impact": ("fx", "impact"), "hit": None, "hits": None, "stab": ("tonal", "stab"),
    "stabs": ("tonal", "stab"), "orch": None,
    # voice
    "vox": ("vox", ""), "voice": ("vox", ""), "voices": None,   # Yamaha's "voices" are patches "vocal": ("vox", ""), "vocals": ("vox", ""),
    "yeah": ("vox", ""), "hey": ("vox", ""), "shout": ("vox", ""), "beatbox": None, "percvoice": ("vox", ""),
    # loops
    "loop": ("loop", ""), "loops": ("loop", ""), "ptn": ("loop", ""), "pattern": ("loop", ""),
    "patterns": ("loop", ""), "groove": ("loop", ""), "grooves": ("loop", ""), "bpm": ("loop", ""),
    "phrase": ("loop", ""), "phrases": ("loop", ""), "break": ("loop", ""), "breaks": ("loop", ""),
    "fill": ("loop", "fill"), "fills": ("loop", "fill"), "roll": None,
    # tonal
    "bass": None, "synth": ("tonal", "synth"), "pad": ("tonal", "pad"), "lead": ("tonal", "lead"),
    "chord": ("tonal", "chord"), "chords": ("tonal", "chord"), "piano": ("tonal", "keys"),
    "organ": ("tonal", "keys"), "strings": ("tonal", "strings"), "brass": ("tonal", "brass"),
    "guitar": ("tonal", "guitar"), "pluck": ("tonal", "pluck"), "sine": ("tonal", "synth"),
}

# Two tokens in a row -> (category, kind), checked before single tokens.
PAIRS = {
    ("bass", "drum"): ("kick", ""), ("kick", "drum"): ("kick", ""), ("snare", "drum"): ("snare", ""),
    ("hi", "hat"): ("hat", ""), ("high", "hat"): ("hat", ""), ("hi", "hats"): ("hat", ""),
    ("open", "hat"): ("hat", "open"), ("closed", "hat"): ("hat", "closed"), ("pedal", "hat"): ("hat", "pedal"),
    ("foot", "hat"): ("hat", "pedal"), ("side", "stick"): ("rim", "sidestick"), ("rim", "shot"): ("rim", "rimshot"),
    ("hand", "clap"): ("clap", ""), ("finger", "snap"): ("clap", "snap"), ("cow", "bell"): ("perc", "cowbell"),
    ("wood", "block"): ("perc", "woodblock"), ("temple", "block"): ("perc", "woodblock"),
    ("ride", "bell"): ("cymbal", "ride_bell"), ("ride", "cup"): ("cymbal", "ride_bell"),
    ("floor", "tom"): ("tom", "floor"), ("talking", "drum"): ("perc", "hand_drum"),
    ("frame", "drum"): ("perc", "hand_drum"), ("steel", "drum"): ("tonal", "mallet"),
    ("orch", "hit"): ("tonal", "stab"), ("vibra", "slap"): ("perc", "vibraslap"),
    ("wind", "chime"): ("perc", "chimes"), ("wind", "chimes"): ("perc", "chimes"),
    ("bass", "synth"): ("tonal", "bass"), ("synth", "bass"): ("tonal", "bass"),
    ("tom", "lo"): ("tom", "low"), ("tom", "low"): ("tom", "low"), ("tom", "mid"): ("tom", "mid"),
    ("tom", "hi"): ("tom", "high"), ("tom", "high"): ("tom", "high"), ("lo", "tom"): ("tom", "low"),
    ("low", "tom"): ("tom", "low"), ("mid", "tom"): ("tom", "mid"), ("hi", "tom"): ("tom", "high"),
    ("high", "tom"): ("tom", "high"), ("hh", "open"): ("hat", "open"), ("hh", "closed"): ("hat", "closed"),
    ("hh", "pedal"): ("hat", "pedal"), ("hat", "open"): ("hat", "open"), ("hat", "closed"): ("hat", "closed"),
    ("hat", "pedal"): ("hat", "pedal"), ("hh", "o"): ("hat", "open"), ("hh", "c"): ("hat", "closed"),
    ("hh", "op"): ("hat", "open"), ("hh", "cl"): ("hat", "closed"), ("cl", "hh"): ("hat", "closed"),
    ("op", "hh"): ("hat", "open"), ("o", "hh"): ("hat", "open"), ("c", "hh"): ("hat", "closed"),
    ("cl", "hat"): ("hat", "closed"), ("op", "hat"): ("hat", "open"),
    ("hat", "o"): ("hat", "open"), ("hat", "c"): ("hat", "closed"), ("hat", "cl"): ("hat", "closed"),
    ("hat", "op"): ("hat", "open"), ("hihat", "open"): ("hat", "open"), ("hihat", "closed"): ("hat", "closed"),
    ("open", "hihat"): ("hat", "open"), ("closed", "hihat"): ("hat", "closed"),
    ("crash", "cymbal"): ("cymbal", "crash"), ("ride", "cymbal"): ("cymbal", "ride"),
    ("china", "cymbal"): ("cymbal", "china"), ("splash", "cymbal"): ("cymbal", "splash"),
    ("sleigh", "bell"): ("perc", "bell"), ("sleigh", "bells"): ("perc", "bell"),
    ("bass", "kick"): ("kick", ""), ("drum", "loop"): ("loop", ""),
}

# Words that refine a kind once the category is known.
HAT_KIND = {"closed": "closed", "close": "closed", "cl": "closed", "c": "closed", "clsd": "closed",
            "tight": "closed", "chh": "closed", "open": "open", "op": "open", "o": "open", "opn": "open",
            "ohh": "open", "pedal": "pedal", "foot": "pedal", "ped": "pedal", "p": "pedal", "phh": "pedal"}
TOM_KIND = {"lo": "low", "low": "low", "l": "low", "floor": "floor", "fl": "floor", "mid": "mid", "md": "mid",
            "m": "mid", "hi": "high", "high": "high", "h": "high"}
CYM_KIND = {"crash": "crash", "ride": "ride", "china": "china", "splash": "splash", "gong": "gong", "bell": "ride_bell",
            "cup": "ride_bell"}
PITCH_KIND = {"lo": "low", "low": "low", "l": "low", "mid": "mid", "m": "mid", "hi": "high", "high": "high",
              "h": "high", "mute": "mute", "muted": "mute", "open": "open", "slap": "slap"}

# Model names (CR-78, CR8000, TR-808, SD-5, RS7000, DR-550, HR-16, MC-505, MV8800, XV-5080) are
# taken out before reading a name, so CR isn't a crash nor SD a snare.
_MODEL = re.compile(r"(?<![A-Za-z])(?:CR|TR|SD|RS|DR|HR|SR|MC|MV|XV|RX|RY|DD|SP|TD|SPD|DTX|MPC|LM|DMX|JD|JV|EX|ES|MS)-?\d{2,4}(?![0-9])", re.I)

_CAMEL = re.compile(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])")


# A capital before a capitalised word ('EBassDrum', 'SBrass'), tried when the plain split finds nothing.
_INITIAL = re.compile(r"(?<=[A-Z])(?=[A-Z][a-z]{2})")


def tokens(text, initials=False):
    """Lower-case word tokens: punctuation, camelCase and letter/digit boundaries split."""
    t = _MODEL.sub(" ", text)
    if initials:
        t = _INITIAL.sub(" ", t)
    t = _CAMEL.sub(" ", t)
    return [w for w in re.split(r"[^A-Za-z0-9]+", t.lower()) if w and not w.isdigit()]


def _refine(cat, kind, toks):
    if kind:
        return kind
    table = {"hat": HAT_KIND, "tom": TOM_KIND, "cymbal": CYM_KIND}.get(cat)
    if table:
        for w in toks:
            if w in table:
                return table[w]
    return ""


def _match(toks):
    """All (category, kind, words) found in a token list, in order of position."""
    out = []
    i = 0
    while i < len(toks):
        if i + 1 < len(toks) and (toks[i], toks[i + 1]) in PAIRS:
            c, k = PAIRS[(toks[i], toks[i + 1])]
            out.append((c, k, toks[i] + " " + toks[i + 1]))
            i += 2
            continue
        v = TOKENS.get(toks[i])
        if v:
            out.append((v[0], v[1], toks[i]))
        i += 1
    return out


# Pieces of run-together names ('Ambcrsh1', 'Atttomh', '20rdbel1'), most specific first.
# Each: (fragment, category, kind, where): where "any" = anywhere in a word, "edge" = at
# a word's start or end (short fragments only).
FRAGMENTS = [
    ("ridebell", "cymbal", "ride_bell", "any"), ("rdbel", "cymbal", "ride_bell", "any"),
    ("ridbel", "cymbal", "ride_bell", "any"), ("bellcym", "cymbal", "ride_bell", "any"),
    ("bassdrum", "kick", "", "any"), ("kickdrum", "kick", "", "any"), ("snaredrum", "snare", "", "any"),
    ("hihat", "hat", "", "any"), ("hatcl", "hat", "closed", "any"), ("hatop", "hat", "open", "any"),
    ("hatpd", "hat", "pedal", "any"), ("hhcl", "hat", "closed", "any"), ("hhop", "hat", "open", "any"),
    ("hhpd", "hat", "pedal", "any"), ("ophat", "hat", "open", "any"), ("opnhat", "hat", "open", "any"),
    ("openhat", "hat", "open", "any"), ("clhat", "hat", "closed", "any"), ("cldhat", "hat", "closed", "any"),
    ("closedhat", "hat", "closed", "any"), ("clsdhat", "hat", "closed", "any"), ("pdhat", "hat", "pedal", "any"),
    ("vibraphone", "tonal", "mallet", "any"), ("tambura", "tonal", "drone", "any"), ("tamborim", "perc", "hand_drum", "any"), ("clhh", "hat", "closed", "any"), ("ophh", "hat", "open", "any"),
    ("sidestick", "rim", "sidestick", "any"), ("rimshot", "rim", "rimshot", "any"),
    ("cowbell", "perc", "cowbell", "any"), ("cowbel", "perc", "cowbell", "any"), ("cwbl", "perc", "cowbell", "any"),
    ("tambourine", "perc", "tambourine", "any"), ("woodblock", "perc", "woodblock", "any"),
    ("castanet", "perc", "castanet", "any"), ("castane", "perc", "castanet", "any"), ("castnt", "perc", "castanet", "any"),
    ("triangle", "perc", "triangle", "any"), ("timbale", "perc", "timbale", "any"), ("vibraslap", "perc", "vibraslap", "any"),
    ("belltree", "perc", "chimes", "any"), ("beltree", "perc", "chimes", "any"), ("whistle", "perc", "whistle", "any"),
    ("handclap", "clap", "", "any"), ("fingersnap", "clap", "snap", "any"),
    ("crash", "cymbal", "crash", "any"), ("crsh", "cymbal", "crash", "any"), ("china", "cymbal", "china", "any"),
    ("chna", "cymbal", "china", "any"), ("splash", "cymbal", "splash", "any"), ("splsh", "cymbal", "splash", "any"),
    ("cymbal", "cymbal", "", "any"), ("ride", "cymbal", "ride", "any"), ("rde", "cymbal", "ride", "edge"),
    ("snare", "snare", "", "any"), ("snr", "snare", "", "any"), ("kick", "kick", "", "any"), ("kik", "kick", "", "any"),
    ("kck", "kick", "", "any"), ("tomh", "tom", "high", "any"), ("toml", "tom", "low", "any"), ("tomm", "tom", "mid", "any"),
    ("tomf", "tom", "floor", "any"), ("tom", "tom", "", "edge"), ("conga", "perc", "conga", "any"),
    ("cnga", "perc", "conga", "any"), ("cng", "perc", "conga", "edge"), ("bongo", "perc", "bongo", "any"),
    ("bngo", "perc", "bongo", "any"), ("bng", "perc", "bongo", "edge"), ("agogo", "perc", "agogo", "any"),
    ("ago", "perc", "agogo", "edge"), ("agg", "perc", "agogo", "edge"), ("shaker", "perc", "shaker", "any"),
    ("shkr", "perc", "shaker", "any"), ("shak", "perc", "shaker", "any"), ("cabasa", "perc", "shaker", "any"),
    ("caba", "perc", "shaker", "any"), ("maraca", "perc", "shaker", "any"), ("marc", "perc", "shaker", "edge"),
    ("tamb", "perc", "tambourine", "any"), ("guiro", "perc", "guiro", "any"), ("guiero", "perc", "guiro", "any"),
    ("cuica", "perc", "cuica", "any"), ("timb", "perc", "timbale", "any"), ("clave", "perc", "clave", "any"),
    ("clav", "perc", "clave", "edge"), ("clap", "clap", "", "any"), ("clp", "clap", "", "edge"),
    ("stik", "rim", "sidestick", "any"), ("rim", "rim", "rimshot", "edge"), ("hat", "hat", "", "edge"),
    ("cym", "cymbal", "", "any"), ("perc", "perc", "", "any"), ("prc", "perc", "", "edge"), ("gong", "cymbal", "gong", "any"),
    ("zap", "fx", "zap", "edge"), ("scratch", "fx", "scratch", "any"), ("noise", "fx", "noise", "any"),
]

# A drum named by one capital letter after a word ('78_K', 'Amb S', '808_T', 'Clsd_H2'),
# Roland R-8 style. Never a name that is only the letter and a number ('T03' is a slot).
# C (cymbal) only after a short code word and '_' ('Brrd_C1'), since 'Drums_C2' is a note.
_LETTER = re.compile(r"[A-Za-z0-9][\s_\-]+(?P<l>[KSTH])\d?$")
_LETTER_CAT = {"K": ("kick", ""), "S": ("snare", ""), "T": ("tom", ""), "H": ("hat", ""), "C": ("cymbal", "")}


def _fragments(toks):
    for w in toks:
        for frag, cat, kind, where in FRAGMENTS:
            if (where == "any" and frag in w) or (where == "edge" and (w.startswith(frag) or w.endswith(frag))):
                return [(cat, kind, frag + "~")]
    return []


def classify_text(text):
    """(category, kind, matched words, other categories) from one name, or None."""
    toks = tokens(text)
    found = _match(toks)
    if not found:
        alt = tokens(text, initials=True)
        if alt != toks:
            found = _match(alt)
            if found:
                toks = alt
    if not found:
        found = _fragments(toks)
    if not found:
        m = _LETTER.search(text.strip())
        if m:
            letter = m.group("l")
            c, k = _LETTER_CAT[letter]
            found = [(c, k, letter + "!")]
    if not found:
        return None
    # A loop is a loop; then a drum word beats a rim, a rim beats percussion, and those beat
    # fx, voice and tonal words ('Zap Kick', 'Tam Kick', 'Impact Snare'); then position.
    rank = {"loop": 0, "kick": 1, "snare": 1, "clap": 1, "hat": 1, "cymbal": 1, "tom": 1, "rim": 2, "perc": 3,
            "fx": 4, "vox": 4, "tonal": 4}
    cat, kind, words = min(found, key=lambda f: rank.get(f[0], 5))
    others = sorted({c for c, _, _ in found if c != cat})
    kind = _refine(cat, kind or next((k for c, k, _ in found if c == cat and k), ""), toks)
    if cat == "perc" and kind:
        pitch = next((PITCH_KIND[w] for w in toks if w in PITCH_KIND), "")
        if pitch:
            kind = kind + ":" + pitch
    return cat, kind, words, others


# ------------------------------------------------------------------ name maps

# General MIDI drum keys (35-81) and the GM2 / XG additions above them (the low GM2 keys,
# 27-34, hold extra kicks and snares on the Triton, so they're left to analysis).
GM_DRUMS = {
    35: ("kick", ""), 36: ("kick", ""), 37: ("rim", "sidestick"), 38: ("snare", ""), 39: ("clap", ""),
    40: ("snare", "electronic"), 41: ("tom", "floor"), 42: ("hat", "closed"), 43: ("tom", "floor"),
    44: ("hat", "pedal"), 45: ("tom", "low"), 46: ("hat", "open"), 47: ("tom", "mid"), 48: ("tom", "mid"),
    49: ("cymbal", "crash"), 50: ("tom", "high"), 51: ("cymbal", "ride"), 52: ("cymbal", "china"),
    53: ("cymbal", "ride_bell"), 54: ("perc", "tambourine"), 55: ("cymbal", "splash"), 56: ("perc", "cowbell"),
    57: ("cymbal", "crash"), 58: ("perc", "vibraslap"), 59: ("cymbal", "ride"), 60: ("perc", "bongo:high"),
    61: ("perc", "bongo:low"), 62: ("perc", "conga:mute"), 63: ("perc", "conga:open"), 64: ("perc", "conga:low"),
    65: ("perc", "timbale:high"), 66: ("perc", "timbale:low"), 67: ("perc", "agogo:high"), 68: ("perc", "agogo:low"),
    69: ("perc", "shaker"), 70: ("perc", "shaker"), 71: ("perc", "whistle"), 72: ("perc", "whistle"),
    73: ("perc", "guiro"), 74: ("perc", "guiro"), 75: ("perc", "clave"), 76: ("perc", "woodblock:high"),
    77: ("perc", "woodblock:low"), 78: ("perc", "cuica:mute"), 79: ("perc", "cuica:open"),
    80: ("perc", "triangle:mute"), 81: ("perc", "triangle:open"), 82: ("perc", "shaker"), 83: ("perc", "bell"),
    84: ("perc", "chimes"), 85: ("perc", "castanet"), 86: ("perc", "hand_drum"), 87: ("perc", "hand_drum"),
}
_NOTE = {"c": 0, "c#": 1, "d": 2, "d#": 3, "e": 4, "f": 5, "f#": 6, "g": 7, "g#": 8, "a": 9, "a#": 10, "b": 11}


class NameMap:
    """A machine's rules for names that are codes, from name_maps/<Machine>.json:

    {"machine": ..., "source": "where the scheme comes from", "rules": [
       {"match": "<regex on the path inside the machine>", "category": .., "kind": ..,
        "settings": {"group": "name"} (optional: knob values from named groups; 'A' = 10)},
       {"match": "<regex with groups note and octave>", "gm_key": <MIDI note of octave 0's C>,
        "confidence": "high" | "medium"}
    ]}
    The first rule that matches decides.
    """

    def __init__(self, data):
        self.data = data
        self.rules = [(re.compile(r["match"], re.I), r) for r in data.get("rules", [])]

    def lookup(self, path):
        for rx, r in self.rules:
            m = rx.search(path)
            if not m:
                continue
            if "gm_key" in r:
                key = int(r["gm_key"]) + 12 * int(m.group("octave")) + _NOTE[m.group("note").lower()]
                hit = GM_DRUMS.get(key)
                if not hit:
                    return {"category": "", "kind": "", "by": "map", "words": "key %d (no GM drum)" % key,
                            "also": [], "key": key}
                return {"category": hit[0], "kind": hit[1], "by": "map", "words": "GM key %d" % key, "also": [],
                        "key": key, "confidence": r.get("confidence", "medium")}
            if not r["category"]:
                return {"category": "", "kind": "", "by": "map", "words": r.get("note", "says nothing"), "also": []}
            out = {"category": r["category"], "kind": r.get("kind", ""), "by": "map", "words": r.get("note", r["match"]),
                   "also": [], "confidence": r.get("confidence", "high")}
            if r.get("settings"):
                out["settings"] = {name: (10 if m.group(g).upper() == "A" else int(m.group(g)))
                                   for g, name in r["settings"].items() if m.group(g) is not None}
            return out
        return None


def load_name_maps(folder):
    import json
    import os
    maps = {}
    if os.path.isdir(folder):
        for f in os.listdir(folder):
            if f.endswith(".json"):
                with open(os.path.join(folder, f), encoding="utf-8") as fh:
                    d = json.load(fh)
                maps[d["machine"]] = NameMap(d)
    return maps


def classify(path, name_map=None):
    """A file's category from its path inside the machine ('Snares/Snr05-Classic.wav').

    Returns {category, kind, by, words, also, confidence}; category "" when nothing says.
    `by`: "map" (the machine's name map), "file" (its own name), "folder" (a folder it's in).
    `words` ends in "~" for a piece of a run-together word, "!" for a one-letter code.
    Confidence: a whole word in the file's name is high; a folder, a word piece or a letter
    code medium; a map rule says its own.
    """
    r = _classify(path, name_map)
    if r["category"] and "confidence" not in r:
        r["confidence"] = "high" if r["by"] == "file" and not r["words"].endswith(("~", "!")) else "medium"
    return r


def _folder(text):
    """A folder's category: like a file's, but its two-letter abbreviations (SN, RD, CH) count only
    when they're the folder's only word ('BD', 'SD'), since folders carry serials and initials."""
    toks = tokens(text)
    if len(toks) > 1:
        kept = [t for t in toks if len(t) > 2 or (TOKENS.get(t) is None)]
        if not kept:
            return None
        text = " ".join(kept)
    return classify_text(text)


def _classify(path, name_map=None):
    if name_map:
        hit = name_map.lookup(path)
        if hit:
            return hit
    parts = path.split("/")
    base = parts[-1].rsplit(".", 1)[0]
    r = classify_text(base)
    if r:
        cat, kind, words, others = r
        folder_r = None
        for f in reversed(parts[:-1]):
            folder_r = _folder(f)
            if folder_r:
                break
        # A one-letter code ('Brsh H') gives way to a folder that says otherwise.
        if folder_r and words.endswith("!") and folder_r[0] != cat:
            return {"category": folder_r[0], "kind": _refine(folder_r[0], folder_r[1], tokens(base)),
                    "by": "folder", "words": folder_r[2], "also": [cat]}
        # A bare file word ('Hit 3', 'Perc') under a more specific folder takes the folder's kind.
        if folder_r and folder_r[0] == cat and not kind and folder_r[1]:
            kind = folder_r[1]
        return {"category": cat, "kind": kind, "by": "file", "words": words, "also": others}
    for f in reversed(parts[:-1]):
        r = _folder(f)
        if r:
            cat, kind, words, others = r
            kind = _refine(cat, kind, tokens(base))
            return {"category": cat, "kind": kind, "by": "folder", "words": words, "also": others}
    return {"category": "", "kind": "", "by": "", "words": "", "also": []}
