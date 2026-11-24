"""Reading and writing sample files without re-quantising: WAV and AIFF in, WAV out.

A `Sound` holds the PCM exactly as stored (little-endian, interleaved), with its format.
Converting AIFF only swaps bytes, joining two mono files only interleaves them, and
folding identical channels only keeps one. The one decode is MS ADPCM, to 16-bit PCM,
since nothing else reads it.
"""

import array
import hashlib
import math
import struct

FMT_PCM = 1
FMT_ADPCM = 2
FMT_FLOAT = 3
FMT_EXTENSIBLE = 0xFFFE


class AudioError(Exception):
    pass


class Sound:
    """PCM as stored: `data` little-endian interleaved frames, `width` bytes a sample."""

    def __init__(self, rate, channels, bits, data, is_float=False):
        self.rate = int(rate)
        self.channels = int(channels)
        self.bits = int(bits)
        self.is_float = bool(is_float)
        self.data = bytes(data)
        self.root_note = -1
        self.loop = None          # (start, end) in frames, end exclusive
        self.source_format = ""   # wav, aiff, aifc-sowt, wav-adpcm ...

    @property
    def width(self):
        return (self.bits + 7) // 8

    @property
    def block(self):
        return self.width * self.channels

    @property
    def frames(self):
        return len(self.data) // self.block if self.block else 0

    @property
    def seconds(self):
        return self.frames / self.rate if self.rate else 0.0

    def channel(self, c):
        """One channel's bytes (mono PCM of the same width)."""
        w, b = self.width, self.block
        if self.channels == 1:
            return self.data
        out = bytearray(self.frames * w)
        for k in range(w):
            out[k::w] = self.data[c * w + k::b][: self.frames]
        return bytes(out)

    def channels_identical(self):
        if self.channels != 2:
            return False
        return self.channel(0) == self.channel(1)

    def to_mono_from(self, c):
        s = Sound(self.rate, 1, self.bits, self.channel(c), self.is_float)
        s.root_note, s.loop, s.source_format = self.root_note, self.loop, self.source_format
        return s

    def samples(self):
        """Every sample as a float in -1..1 (interleaved), for measuring only."""
        w = self.width
        d = self.data[: self.frames * self.block]
        if self.is_float:
            a = array.array("f" if w == 4 else "d")
            a.frombytes(d)
            return a
        if w == 1:
            return [(x - 128) / 128.0 for x in d]
        if w == 2:
            a = array.array("h")
            a.frombytes(d)
            return [x / 32768.0 for x in a]
        if w == 3:
            out = []
            for i in range(0, len(d) - 2, 3):
                v = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16)
                out.append((v - 16777216 if v & 0x800000 else v) / 8388608.0)
            return out
        a = array.array("i")
        a.frombytes(d)
        return [x / 2147483648.0 for x in a]

    def peak(self):
        """Largest absolute sample, 0..1 (cheaply for the common widths)."""
        w = self.width
        d = self.data[: self.frames * self.block]
        if not d:
            return 0.0
        if not self.is_float and w == 2:
            a = array.array("h")
            a.frombytes(d)
            return max(max(a), -min(a)) / 32768.0
        if not self.is_float and w == 4:
            a = array.array("i")
            a.frombytes(d)
            return max(max(a), -min(a)) / 2147483648.0
        if self.is_float:
            s = self.samples()
            return max(abs(max(s)), abs(min(s)))
        s = self.samples()
        return max(max(s), -min(s)) if s else 0.0

    def content_hash(self):
        """The sound itself (format and samples), for finding duplicates."""
        h = hashlib.sha256()
        h.update(struct.pack("<IHHB", self.rate, self.channels, self.bits, int(self.is_float)))
        h.update(self.data[: self.frames * self.block])
        return h.hexdigest()


def sniff(head):
    if len(head) >= 12 and head[:4] == b"RIFF" and head[8:12] == b"WAVE":
        return "wav"
    if len(head) >= 12 and head[:4] == b"FORM" and head[8:12] in (b"AIFF", b"AIFC"):
        return "aiff"
    return ""


def read(data):
    kind = sniff(data[:12])
    if kind == "wav":
        return read_wav(data)
    if kind == "aiff":
        return read_aiff(data)
    raise AudioError("not WAV or AIFF")


# ------------------------------------------------------------------ WAV

def read_wav(b):
    pos, fmt, data_at, data_len = 12, None, None, 0
    root, loop = -1, None
    while pos + 8 <= len(b):
        cid = b[pos:pos + 4]
        size = struct.unpack("<I", b[pos + 4:pos + 8])[0]
        body = pos + 8
        if cid == b"fmt ":
            if size < 16:
                raise AudioError("short fmt chunk")
            tag, ch, rate, _, block, bits = struct.unpack("<HHIIHH", b[body:body + 16])
            extra = b[body + 16: body + size]
            if tag == FMT_EXTENSIBLE and size >= 40:
                tag = struct.unpack("<H", b[body + 24:body + 26])[0]
            fmt = (tag, ch, rate, block, bits, extra)
        elif cid == b"data":
            data_at, data_len = body, min(size, len(b) - body)
        elif cid == b"smpl" and size >= 36:
            unity = struct.unpack("<I", b[body + 12:body + 16])[0]
            root = unity if unity <= 127 else -1
            if struct.unpack("<I", b[body + 28:body + 32])[0] > 0 and size >= 60:
                s, e = struct.unpack("<II", b[body + 44:body + 52])
                if e >= s:
                    loop = (s, e + 1)
        pos = body + size + (size & 1)
    if fmt is None:
        raise AudioError("no fmt chunk")
    if data_at is None:
        raise AudioError("no data chunk")
    tag, ch, rate, block, bits, extra = fmt
    if ch < 1 or rate < 1:
        raise AudioError("bad format (%d channels at %d Hz)" % (ch, rate))
    raw = b[data_at:data_at + data_len]
    if tag == FMT_ADPCM:
        s = _ms_adpcm(raw, ch, rate, block, extra)
        s.source_format = "wav-msadpcm"
    elif tag == FMT_PCM and bits in (8, 16, 24, 32):
        s = Sound(rate, ch, bits, raw)
        s.source_format = "wav"
    elif tag == FMT_FLOAT and bits in (32, 64):
        s = Sound(rate, ch, bits, raw, True)
        s.source_format = "wav-float"
    elif tag == FMT_FLOAT and bits in (8, 16, 24):
        # No float format is this narrow: the tag is wrong, the data is PCM (Korg MS-10 Crash.wav).
        s = Sound(rate, ch, bits, raw)
        s.source_format = "wav-pcm-tagged-float"
    else:
        raise AudioError("unsupported WAV encoding (format %d, %d bits)" % (tag, bits))
    if tag != FMT_ADPCM and block and block != s.block:
        # padded frames (e.g. 20-bit in 3 bytes is fine; odd block layouts are not)
        raise AudioError("unexpected block align %d for %d x %d bits" % (block, ch, bits))
    s.data = s.data[: s.frames * s.block]
    s.root_note, s.loop = root, loop
    return s


_ADAPT = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
_COEF = [(256, 0), (512, -256), (0, 0), (192, 64), (240, 0), (460, -208), (392, -232)]


def _ms_adpcm(raw, ch, rate, block, extra):
    """Microsoft ADPCM to 16-bit PCM."""
    if block <= 0:
        raise AudioError("ADPCM without a block size")
    coefs = list(_COEF)
    if len(extra) >= 6:
        n = struct.unpack("<H", extra[4:6])[0] if len(extra) >= 6 else 0
        if n and len(extra) >= 6 + 4 * n:
            coefs = [struct.unpack("<hh", extra[6 + 4 * i: 10 + 4 * i]) for i in range(n)]
    out = array.array("h")
    for bs in range(0, len(raw) - 7 * ch + 1, block):
        blk = raw[bs:bs + block]
        if len(blk) < 7 * ch:
            break
        o = 0
        pred = list(blk[o:o + ch]); o += ch
        delta = list(struct.unpack("<%dh" % ch, blk[o:o + 2 * ch])); o += 2 * ch
        s1 = list(struct.unpack("<%dh" % ch, blk[o:o + 2 * ch])); o += 2 * ch
        s2 = list(struct.unpack("<%dh" % ch, blk[o:o + 2 * ch])); o += 2 * ch
        for c in range(ch):
            out.append(s2[c])
        for c in range(ch):
            out.append(s1[c])
        c = 0
        for byte in blk[o:]:
            for nib in (byte >> 4, byte & 15):
                p = pred[c] if pred[c] < len(coefs) else 0
                c1, c2 = coefs[p]
                x = s1[c] * c1 + s2[c] * c2
                lin = x // 256 if x >= 0 else -((-x) // 256)   # C division, toward zero (as the reference decoders)
                sn = nib - 16 if nib & 8 else nib
                v = max(-32768, min(32767, lin + sn * delta[c]))
                s2[c], s1[c] = s1[c], v
                out.append(v)
                delta[c] = max(16, (_ADAPT[nib] * delta[c]) >> 8)
                c = (c + 1) % ch
    if len(out) % ch:
        del out[len(out) - len(out) % ch:]
    return Sound(rate, ch, 16, out.tobytes())


def write_wav(s):
    """WAV bytes: PCM or float as held, plus a smpl chunk when there's a root or loop."""
    tag = FMT_FLOAT if s.is_float else FMT_PCM
    fmt = struct.pack("<HHIIHH", tag, s.channels, s.rate, s.rate * s.block, s.block, s.bits)
    chunks = [_chunk(b"fmt ", fmt)]
    if s.root_note >= 0 or s.loop:
        smpl = bytearray(36)
        struct.pack_into("<I", smpl, 8, int(round(1e9 / s.rate)))
        struct.pack_into("<I", smpl, 12, s.root_note if s.root_note >= 0 else 60)
        if s.loop:
            struct.pack_into("<I", smpl, 28, 1)
            smpl += struct.pack("<IIIIII", 0, 0, s.loop[0], s.loop[1] - 1, 0, 0)
        chunks.append(_chunk(b"smpl", bytes(smpl)))
    chunks.append(_chunk(b"data", s.data))
    body = b"WAVE" + b"".join(chunks)
    return b"RIFF" + struct.pack("<I", len(body)) + body


def _chunk(cid, body):
    return cid + struct.pack("<I", len(body)) + body + (b"\0" if len(body) & 1 else b"")


# ------------------------------------------------------------------ AIFF

def _ext80(b):
    e = ((b[0] & 0x7F) << 8) | b[1]
    if e == 0:
        return 0.0
    hi, lo = struct.unpack(">II", b[2:10])
    v = hi * math.pow(2.0, e - 16383 - 31) + lo * math.pow(2.0, e - 16383 - 63)
    return -v if b[0] & 0x80 else v


def read_aiff(b):
    kind = b[8:12]
    pos, comm, ssnd = 12, None, None
    comp = b"NONE"
    markers, base, loop_ids = {}, -1, None
    while pos + 8 <= len(b):
        cid = b[pos:pos + 4]
        size = struct.unpack(">I", b[pos + 4:pos + 8])[0]
        body = pos + 8
        if cid == b"COMM":
            ch, frames, bits = struct.unpack(">HIH", b[body:body + 8])
            rate = _ext80(b[body + 8:body + 18])
            if kind == b"AIFC" and size >= 22:
                comp = b[body + 18:body + 22]
            comm = (ch, frames, bits, rate)
        elif cid == b"SSND":
            off = struct.unpack(">I", b[body:body + 4])[0]
            at = body + 8 + off
            ssnd = (at, max(0, min(size - 8 - off, len(b) - at)))
        elif cid == b"MARK":
            n = struct.unpack(">H", b[body:body + 2])[0]
            o = body + 2
            for _ in range(n):
                if o + 7 > len(b):
                    break
                mid, mpos = struct.unpack(">HI", b[o:o + 6])
                markers[mid] = mpos
                ln = b[o + 6]
                o += 7 + ln + ((ln + 1) & 1)
        elif cid == b"INST" and size >= 20:
            base = b[body]
            if struct.unpack(">H", b[body + 8:body + 10])[0] != 0:
                loop_ids = struct.unpack(">HH", b[body + 10:body + 14])
        pos = body + size + (size & 1)
    if comm is None:
        raise AudioError("no COMM chunk")
    if ssnd is None:
        raise AudioError("no SSND chunk")
    ch, frames, bits, rate = comm
    c = comp.decode("latin-1")
    is_float = c.lower() in ("fl32", "fl64")
    if is_float:
        bits = 32 if c.lower() == "fl32" else 64
    if c not in ("NONE", "twos", "sowt") and not is_float:
        raise AudioError("unsupported AIFF-C compression %r" % c)
    w = (bits + 7) // 8
    if (not is_float and w not in (1, 2, 3, 4)) or (is_float and w not in (4, 8)):
        raise AudioError("unsupported AIFF encoding (%d bits)" % bits)
    at, ln = ssnd
    frames = min(frames, ln // (w * ch))
    raw = b[at:at + frames * w * ch]
    if w == 1:
        le = raw.translate(bytes((x + 128) & 0xFF for x in range(256)))
    elif c == "sowt":
        le = raw
    else:
        out = bytearray(len(raw))
        for k in range(w):
            out[k::w] = raw[w - 1 - k::w]
        le = bytes(out)
    # AIFF stores 8..32 bits left-justified in whole bytes, as WAV does
    s = Sound(round(rate), ch, w * 8 if not is_float else bits, le, is_float)
    s.source_format = "aiff" if kind == b"AIFF" else "aifc-" + c.strip().lower()
    if 0 <= base <= 127:
        s.root_note = base
    if loop_ids and loop_ids[0] in markers and loop_ids[1] in markers:
        a, e = markers[loop_ids[0]], markers[loop_ids[1]]
        if e > a:
            s.loop = (a, e)
    return s


# ------------------------------------------------------------------ joining

def join_stereo(left, right):
    """Two mono sounds of one format as one stereo sound (the shorter padded with silence)."""
    if (left.channels, right.channels) != (1, 1) or left.rate != right.rate or left.bits != right.bits \
            or left.is_float != right.is_float:
        raise AudioError("can't join: formats differ")
    w = left.width
    n = max(left.frames, right.frames)
    zero = b"\x80" if (w == 1 and not left.is_float) else b"\0"
    ld = left.data + zero * ((n - left.frames) * w)
    rd = right.data + zero * ((n - right.frames) * w)
    out = bytearray(n * 2 * w)
    for k in range(w):
        out[k::2 * w] = ld[k::w]
        out[w + k::2 * w] = rd[k::w]
    s = Sound(left.rate, 2, left.bits, bytes(out), left.is_float)
    s.root_note, s.loop, s.source_format = left.root_note, left.loop, left.source_format
    return s
