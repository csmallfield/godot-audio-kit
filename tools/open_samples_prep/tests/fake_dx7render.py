"""Test double for dx7render.exe: checks the voice file, writes a short WAV per note."""

import struct
import sys
import wave


def main(argv):
    voice, out = argv[0], argv[1]
    opts = dict(zip(argv[2::2], argv[3::2]))
    data = open(voice, "rb").read()
    if len(data) not in (155, 156):
        print("bad voice size", file=sys.stderr)
        return 1
    notes = [int(n) for n in opts.get("--notes", "60").split(",")]
    rate = int(opts.get("--rate", "48000"))
    per = int((float(opts["--hold"]) + float(opts["--release"]) + float(opts["--gap"])) * rate)
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", (i * (n + data[134])) % 2000)
                               for n in notes for i in range(per)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
