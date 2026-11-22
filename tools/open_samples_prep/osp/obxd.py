"""OB-Xd banks (.fxb, .fxp: <discoDSP> XML) and OB-Xf patches (.fxp: <OB-Xf> XML).

Both become OB-Xf 1.0.3's 102 parameters, normalized 0..1 as OB-Xf stores them, in the
plugin's own order (its VST3 parameters 0..101). An OB-Xd program goes through a port of
OB-Xf's own importer (src/state/ObxdImporter.cpp, OB-Xf e03452f, GPL-3.0-or-later): it
rescales LFO rates, attack times, the voice count and a few ranges so old banks sound in
OB-Xf as they did in OB-Xd. Values not in the file take OB-Xf 1.0.3's defaults (read from
the plugin).
"""

import hashlib
import math
import re

# (attribute in OB-Xf's XML, the plugin's parameter name, OB-Xf 1.0.3's default, normalized).
PARAMS = [
    ("Volume", 'Volume', 0.5),
    ("Transpose", 'Transpose', 0.5),
    ("Tune", 'Tune', 0.5),
    ("Polyphony", 'Polyphony', 0.2258064),
    ("HQMode", 'High Quality Mode', 0.0),
    ("UnisonVoices", 'Unison Voices', 0.2258064),
    ("Portamento", 'Glide', 0.0),
    ("Unison", 'Unison', 0.0),
    ("UnisonDetune", 'Unison Detune', 0.25),
    ("EnvLegatoMode", 'Envelope Legato Mode', 0.0),
    ("NotePriority", 'Note Priority', 0.0),
    ("Osc1Pitch", 'Osc 1 Pitch', 0.5),
    ("Osc2Detune", 'Osc 2 Detune', 0.0),
    ("Osc2Pitch", 'Osc 2 Pitch', 0.5),
    ("Osc1SawWave", 'Osc 1 Saw Wave', 1.0),
    ("Osc1PulseWave", 'Osc 1 Pulse Wave', 0.0),
    ("Osc2SawWave", 'Osc 2 Saw Wave', 1.0),
    ("Osc2PulseWave", 'Osc 2 Pulse Wave', 0.0),
    ("OscPW", 'Osc Pulsewidth', 0.0),
    ("Osc2PWOffset", 'Osc 2 Pulsewidth Offset', 0.0),
    ("EnvToPitchAmount", 'Filter Env to Pitch', 0.0),
    ("EnvToPitchBothOscs", 'Filter Env to Both Osc Pitch', 1.0),
    ("EnvToPitchInvert", 'Invert Filter Env to Pitch', 0.0),
    ("EnvToPWAmount", 'Filter Env to Pulsewidth', 0.0),
    ("EnvToPWBothOscs", 'Filter Env to Both Osc Pulsewidth', 1.0),
    ("EnvToPWInvert", 'Invert Filter Env to Pulsewidth', 0.0),
    ("OscCrossmod", 'Cross Modulation', 0.0),
    ("OscSync", 'Osc Sync', 0.0),
    ("OscBrightness", 'Osc Brightness', 1.0),
    ("Osc1Mix", 'Osc 1 Volume', 1.0),
    ("Osc2Mix", 'Osc 2 Volume', 0.0),
    ("RingModMix", 'Ring Mod Volume', 0.0),
    ("NoiseMix", 'Noise Volume', 0.0),
    ("NoiseColor", 'Noise Color', 0.0),
    ("PitchBendUp", 'Pitch Bend Up', 0.0416667),
    ("PitchBendDown", 'Pitch Bend Down', 0.0416667),
    ("BendOsc2Only", 'Pitch Bend Osc 2 Only', 0.0),
    ("VibratoWave", 'Vibrato Wave', 0.0),
    ("VibratoRate", 'Vibrato Rate', 0.3),
    ("Filter4PoleMode", 'Filter 4-Pole Mode', 0.0),
    ("FilterCutoff", 'Filter Cutoff', 1.0),
    ("FilterResonance", 'Filter Resonance', 0.0),
    ("FilterEnvAmount", 'Filter Env Amount', 0.0),
    ("FilterKeyFollow", 'Filter Keytrack', 0.0),
    ("FilterMode", 'Filter Mode', 0.0),
    ("Filter2PoleBPBlend", 'Filter 2-Pole BP Blend', 0.0),
    ("Filter2PolePush", 'Filter 2-Pole Push', 0.0),
    ("Filter4PoleXpander", 'Filter 4-Pole Xpander', 0.0),
    ("FilterXpanderMode", 'Filter Xpander Mode', 0.0),
    ("LFO1TempoSync", 'LFO 1 Tempo Sync', 0.0),
    ("LFO1Rate", 'LFO 1 Rate', 0.5),
    ("LFO1ModAmount1", 'LFO 1 Mod 1 Amount', 0.0),
    ("LFO1ModAmount2", 'LFO 1 Mod 2 Amount', 0.0),
    ("LFO1Wave1", 'LFO 1 Wave 1', 0.0),
    ("LFO1Wave2", 'LFO 1 Wave 2', 0.5),
    ("LFO1Wave3", 'LFO 1 Wave 3', 0.5),
    ("LFO1PW", 'LFO 1 Pulsewidth', 0.0),
    ("LFO1ToOsc1Pitch", 'LFO 1 to Osc 1 Pitch', 0.0),
    ("LFO1ToOsc2Pitch", 'LFO 1 to Osc 2 Pitch', 0.0),
    ("LFO1ToFilterCutoff", 'LFO 1 to Filter Cutoff', 0.0),
    ("LFO1ToOsc1PW", 'LFO 1 to Osc 1 PW', 0.0),
    ("LFO1ToOsc2PW", 'LFO 1 to Osc 2 PW', 0.0),
    ("LFO1ToVolume", 'LFO 1 to Volume', 0.0),
    ("LFO2TempoSync", 'LFO 2 Tempo Sync', 0.0),
    ("LFO2Rate", 'LFO 2 Rate', 0.5),
    ("LFO2ModAmount1", 'LFO 2 Mod 1 Amount', 0.0),
    ("LFO2ModAmount2", 'LFO 2 Mod 2 Amount', 0.0),
    ("LFO2Wave1", 'LFO 2 Wave 1', 0.0),
    ("LFO2Wave2", 'LFO 2 Wave 2', 0.5),
    ("LFO2Wave3", 'LFO 2 Wave 3', 0.5),
    ("LFO2PW", 'LFO 2 Pulsewidth', 0.0),
    ("LFO2ToOsc1Pitch", 'LFO 2 to Osc 1 Pitch', 0.0),
    ("LFO2ToOsc2Pitch", 'LFO 2 to Osc 2 Pitch', 0.0),
    ("LFO2ToFilterCutoff", 'LFO 2 to Filter Cutoff', 0.0),
    ("LFO2ToOsc1PW", 'LFO 2 to Osc 1 PW', 0.0),
    ("LFO2ToOsc2PW", 'LFO 2 to Osc 2 PW', 0.0),
    ("LFO2ToVolume", 'LFO 2 to Volume', 0.0),
    ("FilterEnvInvert", 'Filter Env Invert', 0.0),
    ("FilterEnvAttack", 'Filter Env Attack', 0.0),
    ("FilterEnvDecay", 'Filter Env Decay', 0.0),
    ("FilterEnvSustain", 'Filter Env Sustain', 1.0),
    ("FilterEnvRelease", 'Filter Env Release', 0.0),
    ("FilterEnvAttackCurve", 'Filter Env Attack Curve', 0.0),
    ("VelToFilterEnv", 'Velocity to Filter Env', 0.0),
    ("AmpEnvAttack", 'Amp Env Attack', 0.0),
    ("AmpEnvDecay", 'Amp Env Decay', 0.0),
    ("AmpEnvSustain", 'Amp Env Sustain', 1.0),
    ("AmpEnvRelease", 'Amp Env Release', 0.0),
    ("AmpEnvAttackCurve", 'Amp Env Attack Curve', 0.0),
    ("VelToAmpEnv", 'Velocity to Amp Env', 0.0),
    ("PortamentoSlop", 'Glide Slop', 0.25),
    ("FilterSlop", 'Filter Slop', 0.25),
    ("EnvelopeSlop", 'Envelope Slop', 0.25),
    ("LevelSlop", 'Level Slop', 0.25),
    ("PanVoice1", 'Pan Voice 1', 0.5),
    ("PanVoice2", 'Pan Voice 2', 0.5),
    ("PanVoice3", 'Pan Voice 3', 0.5),
    ("PanVoice4", 'Pan Voice 4', 0.5),
    ("PanVoice5", 'Pan Voice 5', 0.5),
    ("PanVoice6", 'Pan Voice 6', 0.5),
    ("PanVoice7", 'Pan Voice 7', 0.5),
    ("PanVoice8", 'Pan Voice 8', 0.5),
]
KEYS = [k for k, _, _ in PARAMS]
DEFAULTS = {k: d for k, _, d in PARAMS}
INDEX = {k: i for i, k in enumerate(KEYS)}

XPANDER_MODES = ["LP4", "LP3", "LP2", "LP1", "HP3", "HP2", "HP1", "BP4", "BP2", "N2", "PH3",
                 "HP2+LP1", "HP3+LP1", "N2+LP1", "PH3+LP1"]
MAX_VOICES = 32
MAX_BEND_RANGE = 48
SYNCED_RATES = 21

# OB-Xd's parameter indices (Val_<n>), frozen as written to disk (OB-Xd 2.19 ParamsEnum.h).
XD = dict(VOLUME=2, VOICE_COUNT=3, TUNE=4, OCTAVE=5, BENDRANGE=6, BENDOSC2=7, LEGATOMODE=8,
          BENDLFORATE=9, VFLTENV=10, VAMPENV=11, ASPLAYEDALLOCATION=12, PORTAMENTO=13, UNISON=14,
          UDET=15, OSC2_DET=16, LFOFREQ=17, LFOSINWAVE=18, LFOSQUAREWAVE=19, LFOSHWAVE=20,
          LFO1AMT=21, LFO2AMT=22, LFOOSC1=23, LFOOSC2=24, LFOFILTER=25, LFOPW1=26, LFOPW2=27,
          OSC2HS=28, XMOD=29, OSC1P=30, OSC2P=31, OSCQuantize=32, OSC1Saw=33, OSC1Pul=34,
          OSC2Saw=35, OSC2Pul=36, PW=37, BRIGHTNESS=38, ENVPITCH=39, OSC1MIX=40, OSC2MIX=41,
          NOISEMIX=42, FLT_KF=43, CUTOFF=44, RESONANCE=45, MULTIMODE=46, FILTER_WARM=47,
          BANDPASS=48, FOURPOLE=49, ENVELOPE_AMT=50, LATK=51, LDEC=52, LSUS=53, LREL=54, FATK=55,
          FDEC=56, FSUS=57, FREL=58, ENVDER=59, FILTERDER=60, PORTADER=61, PAN1=62, LFO_SYNC=72,
          PW_ENV=73, PW_ENV_BOTH=74, ENV_PITCH_BOTH=75, FENV_INVERT=76, PW_OSC2_OFS=77,
          LEVEL_DIF=78, SELF_OSC_PUSH=79)


def _attrs(tag_text):
    return dict(re.findall(r'([\w:.-]+)="([^"]*)"', tag_text))


def _xml_of(data):
    """The XML in an fxb/fxp chunk (after 'VC2!' and its length)."""
    i = data.find(b"<?xml")
    if i < 0:
        i = data.find(b"<")
    if i < 0:
        raise ValueError("no XML in the chunk")
    return data[i:].split(b"\0", 1)[0].decode("utf-8", "replace")


def detect(data):
    """'obxd-bank', 'obxd-program', 'obxf' or None."""
    if data[:4] != b"CcnK" or len(data) < 60:
        return None
    if b"<OB-Xf" in data:
        return "obxf"
    if data[16:20] == b"Obxd" or b"<discoDSP" in data or b"<Datsounds" in data:
        return "obxd-bank" if data[8:12] == b"FBCh" else "obxd-program"
    return None


def read(data):
    """Bytes of an .fxb/.fxp -> list of programs {index, name, kind, raw {attr: str}}.
    Raises ValueError when it isn't an OB-Xd or OB-Xf file."""
    kind = detect(data)
    if kind is None:
        raise ValueError("not an OB-Xd or OB-Xf file")
    x = _xml_of(data)
    if kind == "obxf":
        m = re.search(r"<OB-Xf\b([^>]*?)/?>", x)
        if not m:
            raise ValueError("no <OB-Xf> element")
        a = _attrs(m.group(1))
        return [{"index": 0, "name": a.get("programName", ""), "kind": kind, "raw": a}]
    root = re.search(r"<(discoDSP|Datsounds)\b([^>]*)>", x)
    if not root:
        raise ValueError("no <discoDSP> element")
    if kind == "obxd-program":
        a = _attrs(root.group(2))
        return [{"index": 0, "name": a.get("programName", ""), "kind": kind, "raw": a}]
    out = []
    for i, m in enumerate(re.finditer(r"<program\b([^>]*?)/?>", x)):
        if i >= 128:
            break
        a = _attrs(m.group(1))
        out.append({"index": i, "name": a.get("programName", "Default"), "kind": kind, "raw": a})
    if not out:
        raise ValueError("a bank without programs")
    return out


def is_init(prog):
    """OB-Xf's importer skips bank programs named "Default" (empty slots)."""
    return prog["kind"] != "obxf" and prog["name"].strip().lower() in ("default", "")


# OB-Xd's logsc/linsc and their inverses (OB-Xd AudioUtils.h, as the importer has them).
def _logsc(p, lo, hi, rolloff=19.0):
    return ((math.exp(p * math.log(rolloff + 1.0)) - 1.0) / rolloff) * (hi - lo) + lo


def _clamp01(v):
    return min(1.0, max(0.0, v))


def _inv_linsc(y, lo, hi):
    return 0.0 if hi == lo else _clamp01((y - lo) / (hi - lo))


def _inv_logsc(y, lo, hi, rolloff=19.0):
    if hi == lo:
        return 0.0
    t = rolloff * (y - lo) / (hi - lo) + 1.0
    return 0.0 if t <= 0.0 else _clamp01(math.log(t) / math.log(rolloff + 1.0))


def from_obxd(raw):
    """An OB-Xd program's attributes -> (OB-Xf values {key: normalized}, warnings)."""
    def val(k):
        n = XD[k] if isinstance(k, str) else k
        for key in ("Val_%d" % n, str(n)):
            if key in raw:
                try:
                    return float(raw[key])
                except ValueError:
                    return 0.0
        return 0.0

    v = dict(DEFAULTS)
    warn = []
    # Defaults the importer sets to OB-Xd's hard-wired behaviour.
    for k in ("EnvToPitchInvert", "EnvToPWInvert", "RingModMix", "NoiseColor", "Filter4PoleXpander",
              "FilterXpanderMode", "AmpEnvAttackCurve", "FilterEnvAttackCurve", "LFO1PW", "LFO1ToVolume",
              "VibratoWave", "NotePriority", "EnvLegatoMode"):
        v[k] = 0.0
    new_format = "voiceCount" in raw
    lfo_sync = val("LFO_SYNC") > 0.5
    osc_step = val("OSCQuantize") > 0.5
    transpose = int(round(val("OCTAVE") * 4.0) + 1)
    v["Volume"] = val("VOLUME")
    v["Tune"] = val("TUNE")
    v["Transpose"] = min(4, max(0, transpose)) * 0.25
    vc = val("VOICE_COUNT") * (1.0 if new_format else 0.25)
    voices = min(MAX_VOICES, max(1, int(round(vc * 31.0) - 0.000001) + 1))
    v["Polyphony"] = (voices - 1 + 0.5) / MAX_VOICES
    v["HQMode"] = val("FILTER_WARM")
    rng = 12 if val("BENDRANGE") > 0.5 else 2
    v["PitchBendUp"] = v["PitchBendDown"] = rng / MAX_BEND_RANGE
    v["BendOsc2Only"] = val("BENDOSC2")
    v["VibratoRate"] = _inv_linsc(_logsc(val("BENDLFORATE"), 3.0, 10.0), 2.0, 12.0)
    v["Portamento"] = val("PORTAMENTO")
    v["Unison"] = val("UNISON")
    v["UnisonDetune"] = _inv_logsc(_logsc(val("UDET"), 0.001, 0.90), 0.001, 1.0)
    v["EnvLegatoMode"] = val("LEGATOMODE")
    v["NotePriority"] = 0.0 if val("ASPLAYEDALLOCATION") > 0.5 else 0.5
    p1, p2 = val("OSC1P") * 48.0, val("OSC2P") * 48.0
    if p1 <= 36.0 and p2 <= 36.0 and transpose > 4:
        p1, p2 = p1 + 12.0, p2 + 12.0
        warn.append("transpose was already at its top; both oscillators were raised an octave")
    v["Osc1Pitch"] = (int(p1) if osc_step else p1) / 48.0
    v["Osc2Pitch"] = (int(p2) if osc_step else p2) / 48.0
    v["Osc2Detune"] = val("OSC2_DET")
    v["Osc1SawWave"] = val("OSC1Saw")
    v["Osc1PulseWave"] = val("OSC1Pul")
    v["Osc2SawWave"] = val("OSC2Saw")
    v["Osc2PulseWave"] = val("OSC2Pul")
    v["OscSync"] = val("OSC2HS")
    v["OscCrossmod"] = val("XMOD") * 0.5
    v["OscPW"] = val("PW")
    v["Osc2PWOffset"] = val("PW_OSC2_OFS") * (0.75 / 0.95)
    v["EnvToPWAmount"] = val("PW_ENV") * (0.85 / 1.0555555555)
    v["EnvToPWBothOscs"] = val("PW_ENV_BOTH")
    v["EnvToPitchAmount"] = val("ENVPITCH") * (36.0 / 40.0)
    v["EnvToPitchBothOscs"] = val("ENV_PITCH_BOTH")
    v["OscBrightness"] = val("BRIGHTNESS")
    v["Osc1Mix"] = val("OSC1MIX")
    v["Osc2Mix"] = val("OSC2MIX")
    v["NoiseMix"] = _logsc(val("NOISEMIX"), 0.0, 1.0, 35.0)
    v["FilterCutoff"] = val("CUTOFF")
    v["FilterResonance"] = val("RESONANCE")
    v["FilterMode"] = val("MULTIMODE")
    v["Filter2PoleBPBlend"] = val("BANDPASS")
    v["Filter4PoleMode"] = val("FOURPOLE")
    v["Filter2PolePush"] = val("SELF_OSC_PUSH")
    v["FilterKeyFollow"] = val("FLT_KF")
    v["FilterEnvAmount"] = val("ENVELOPE_AMT")
    v["FilterEnvInvert"] = val("FENV_INVERT")

    def attack(x, lo, hi):
        return _inv_logsc(_logsc(x, lo, hi, 900.0) / 3.0, lo, hi, 900.0)

    v["AmpEnvAttack"] = attack(val("LATK"), 4.0, 60000.0)
    v["AmpEnvDecay"] = val("LDEC")
    v["AmpEnvSustain"] = val("LSUS")
    v["AmpEnvRelease"] = val("LREL")
    v["VelToAmpEnv"] = val("VAMPENV")
    v["FilterEnvAttack"] = attack(val("FATK"), 1.0, 60000.0)
    v["FilterEnvDecay"] = val("FDEC")
    v["FilterEnvSustain"] = val("FSUS")
    v["FilterEnvRelease"] = val("FREL")
    v["VelToFilterEnv"] = val("VFLTENV")
    v["LFO1TempoSync"] = 1.0 if lfo_sync else 0.0
    if lfo_sync:
        table = [1, 4, 5, 7, 10, 11, 13, 15, 16]
        v["LFO1Rate"] = table[min(8, max(0, int(val("LFOFREQ") * 8.0)))] / (SYNCED_RATES - 1)
        warn.append("OB-Xd's tempo sync was unreliable; OB-Xf syncs exactly")
    else:
        v["LFO1Rate"] = _inv_logsc(_logsc(val("LFOFREQ"), 0.0, 50.0, 120.0), 0.0, 250.0, 3775.0)

    def blend(x):
        return 0.0 if x >= 0.5 else 0.5

    def tri(x):
        return 0.5 if x >= 0.5 else 0.0

    v["LFO1Wave1"] = blend(val("LFOSINWAVE"))
    v["LFO1Wave2"] = blend(val("LFOSQUAREWAVE"))
    v["LFO1Wave3"] = blend(val("LFOSHWAVE"))
    v["LFO1ModAmount1"] = val("LFO1AMT")
    v["LFO1ModAmount2"] = val("LFO2AMT")
    v["LFO1ToOsc1Pitch"] = tri(val("LFOOSC1"))
    v["LFO1ToOsc2Pitch"] = tri(val("LFOOSC2"))
    v["LFO1ToFilterCutoff"] = tri(val("LFOFILTER"))
    v["LFO1ToOsc1PW"] = tri(val("LFOPW1"))
    v["LFO1ToOsc2PW"] = tri(val("LFOPW2"))
    v["PortamentoSlop"] = val("PORTADER")
    v["FilterSlop"] = val("FILTERDER")
    v["EnvelopeSlop"] = val("ENVDER")
    v["LevelSlop"] = val("LEVEL_DIF")
    for n in range(8):
        v["PanVoice%d" % (n + 1)] = val(XD["PAN1"] + n)
    return v, warn


def from_obxf(raw):
    """An OB-Xf program's attributes -> (values {key: normalized}, warnings)."""
    v = dict(DEFAULTS)
    warn = []
    for k in KEYS:
        if k in raw:
            try:
                v[k] = float(raw[k])
            except ValueError:
                warn.append("%s=%r isn't a number; the default is kept" % (k, raw[k]))
    extra = sorted(k for k in raw if k not in DEFAULTS and k not in (
        "xf_version", "voiceCount", "programName", "author", "license", "category", "project"))
    if extra:
        warn.append("attributes OB-Xf 1.0.3 doesn't have: " + ", ".join(extra))
    return v, warn


def values(prog):
    return from_obxf(prog["raw"]) if prog["kind"] == "obxf" else from_obxd(prog["raw"])


def sound_sha256(vals):
    return hashlib.sha256(",".join("%.6f" % vals[k] for k in KEYS).encode()).hexdigest()


def names(v):
    """Readable meanings of the values that set the sound's character."""
    on = lambda k: v[k] >= 0.5  # noqa: E731
    return {
        "polyphony": min(MAX_VOICES, 1 + int(v["Polyphony"] * (MAX_VOICES - 1) + 0.5)),
        "transpose_semitones": round((v["Transpose"] - 0.5) * 48),
        "osc1_pitch_semitones": round((v["Osc1Pitch"] - 0.5) * 48, 2),
        "osc2_pitch_semitones": round((v["Osc2Pitch"] - 0.5) * 48, 2),
        "filter": ("xpander " + XPANDER_MODES[int(round(v["FilterXpanderMode"] * 14))]
                   if on("Filter4PoleMode") and on("Filter4PoleXpander")
                   else "4-pole" if on("Filter4PoleMode") else "2-pole"),
        "cutoff_hz": round(440.0 * 2 ** ((-45.0 + 120.0 * v["FilterCutoff"]) / 12.0), 1),
    }


def features(v):
    on = lambda k: v[k] >= 0.5  # noqa: E731
    f = []
    if on("Unison"):
        f.append("unison")
    if on("OscSync"):
        f.append("sync")
    if v["OscCrossmod"] > 0.01:
        f.append("cross mod")
    if v["RingModMix"] > 0.01:
        f.append("ring mod")
    if v["NoiseMix"] > 0.01:
        f.append("noise")
    if on("Filter4PoleMode"):
        f.append("xpander filter" if on("Filter4PoleXpander") else "4-pole filter")
    else:
        f.append("2-pole filter")
    if v["OscBrightness"] < 0.98:
        f.append("brightness")
    for n in ("1", "2"):
        if v["LFO%sModAmount1" % n] > 0.01 or v["LFO%sModAmount2" % n] > 0.01:
            f.append("lfo%s" % n + (" (tempo sync)" if on("LFO%sTempoSync" % n) else ""))
    if any(abs(v["PanVoice%d" % i] - 0.5) > 0.01 for i in range(1, 9)):
        f.append("voice pan")
    if v["EnvToPitchAmount"] > 0.01:
        f.append("filter env to pitch")
    if v["Portamento"] > 0.01:
        f.append("glide")
    return f
