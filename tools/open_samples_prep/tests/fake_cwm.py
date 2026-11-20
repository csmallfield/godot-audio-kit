"""Test double for ConvertWithMossCLI: same arguments, canned output.

Writes the fixture SFZ (or a matching .dspreset) plus small WAVs for every sample
it references. A source file containing b"ENCRYPTED" is refused like CWM does.
"""

import os
import re
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "Fake Inst"


def write_wav(path, seed):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b"".join(struct.pack("<h", (i * seed) % 20000 - 10000) for i in range(4410)))


def main(argv):
    if "-V" in argv:
        print("ConvertWithMoss 9.9.9")
        return 0
    dest = argv[argv.index("-d") + 1]
    positional = [a for a in argv if not a.startswith("-")]
    positional = [a for a in positional if a not in (argv[argv.index("-s") + 1], dest)]
    src, out = positional[0], positional[-1]
    with open(src, "rb") as f:
        data = f.read()
    print("ConvertWithMoss 9.9.9")
    if b"ENCRYPTED" in data:
        print("Error: Encrypted files are not supported.")
        return 0
    if "-ad" in argv:
        print("Detected Kontakt Container format (fake)")
        print(f"Analysis of '{NAME}':")
        print("  Metadata: category 'Keys', creator 'Tester', keywords 'warm, soft'")
        print("  Group 1 'rr1': 2 zones")
        print("    Zone 'c4_soft': keys A#3/58..D4/62")
        print("      Loop: forwards 20000..44000")
        print("      Amplitude envelope: attack 0.010 s")
        print("  Group 2 'rr2': 1 zone")
        print(f"Analyze: '{NAME}' OK")
        return 0
    with open(os.path.join(HERE, "fixtures", "sample.sfz"), encoding="utf-8") as f:
        sfz = f.read().replace("default_path=Test Samples/", f"default_path={NAME} Samples/")
    samples = re.findall(r"^sample=(.+)$", sfz, flags=re.M)
    for i, s in enumerate(samples):
        write_wav(os.path.join(out, f"{NAME} Samples", s.strip()), 7 + i)
    if dest == "sfz":
        with open(os.path.join(out, f"{NAME}.sfz"), "w", encoding="utf-8") as f:
            f.write(sfz)
    elif dest == "decentsampler":
        with open(os.path.join(out, f"{NAME}.dspreset"), "w", encoding="utf-8") as f:
            f.write("<DecentSampler><groups/></DecentSampler>\n")
    print(f"Storing: {out}")
    print("Note: 1 of the 2 loops wraps with an audible step.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
