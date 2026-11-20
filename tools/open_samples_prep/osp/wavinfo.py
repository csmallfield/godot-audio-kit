"""Minimal RIFF/WAVE header reader (standard library only).

Reads format, length and the smpl / inst / LIST-INFO chunks without loading audio.
Handles WAVE_FORMAT_EXTENSIBLE and float files, which the `wave` module rejects.
"""

import struct

FORMAT_NAMES = {1: "pcm", 3: "float", 6: "alaw", 7: "ulaw"}


def _read_chunks(f, limit):
    while f.tell() + 8 <= limit:
        head = f.read(8)
        if len(head) < 8:
            return
        cid, size = struct.unpack("<4sI", head)
        start = f.tell()
        yield cid, size, start
        f.seek(start + size + (size & 1))


def read_wav_info(path):
    with open(path, "rb") as f:
        f.seek(0, 2)
        file_size = f.tell()
        f.seek(0)
        riff = f.read(12)
        if len(riff) < 12 or riff[0:4] not in (b"RIFF", b"RF64") or riff[8:12] != b"WAVE":
            raise ValueError(f"not a RIFF/WAVE file: {path}")
        info = {"format": None, "format_tag": None, "channels": None, "sample_rate": None,
                "bit_depth": None, "frames": None, "duration_s": None}
        data_bytes = None
        block_align = None
        for cid, size, start in _read_chunks(f, file_size):
            if cid == b"fmt ":
                raw = f.read(min(size, 40))
                tag, ch, rate, _brate, block_align, bits = struct.unpack("<HHIIHH", raw[:16])
                if tag == 0xFFFE and len(raw) >= 26:
                    tag = struct.unpack("<H", raw[24:26])[0]  # first two bytes of SubFormat GUID
                info.update(format=FORMAT_NAMES.get(tag, f"tag-{tag}"), format_tag=tag,
                            channels=ch, sample_rate=rate, bit_depth=bits)
            elif cid == b"data":
                data_bytes = min(size, file_size - start)
            elif cid == b"smpl" and size >= 36:
                raw = f.read(size)
                (_man, _prod, period, unity, fraction, _sf, _so, nloops, _sd) = struct.unpack(
                    "<9I", raw[:36])
                loops = []
                for i in range(nloops):
                    off = 36 + 24 * i
                    if off + 24 > len(raw):
                        break
                    _lid, ltype, lstart, lend, lfrac, lcount = struct.unpack("<6I", raw[off:off + 24])
                    loops.append({"type": {0: "forward", 1: "alternating", 2: "backward"}.get(
                        ltype, ltype), "start": lstart, "end": lend, "play_count": lcount})
                info["smpl"] = {"midi_unity_note": unity,
                                "pitch_fraction_cents": round(fraction / 4294967296 * 100, 4),
                                "sample_period_ns": period, "loops": loops}
            elif cid == b"inst" and size >= 7:
                raw = f.read(7)
                note, fine, gain, lo, hi, lov, hiv = struct.unpack("<BbbBBBB", raw)
                info["inst"] = {"unshifted_note": note, "fine_tune_cents": fine, "gain_db": gain,
                                "key_range": [lo, hi], "velocity_range": [lov, hiv]}
            elif cid == b"LIST" and size >= 4:
                raw = f.read(size)
                if raw[:4] == b"INFO":
                    tags = {}
                    pos = 4
                    while pos + 8 <= len(raw):
                        sid, ssize = struct.unpack("<4sI", raw[pos:pos + 8])
                        val = raw[pos + 8:pos + 8 + ssize].split(b"\x00", 1)[0]
                        tags[sid.decode("ascii", "replace")] = val.decode("latin-1").strip()
                        pos += 8 + ssize + (ssize & 1)
                    if tags:
                        info["info"] = tags
        if data_bytes is not None and block_align:
            info["frames"] = data_bytes // block_align
            if info["sample_rate"]:
                info["duration_s"] = round(info["frames"] / info["sample_rate"], 6)
        return info
