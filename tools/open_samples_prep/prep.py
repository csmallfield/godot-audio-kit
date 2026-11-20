#!/usr/bin/env python3
"""Pre-convert the Open Samples collection: Kontakt/EXS24/SF2 -> WAV + SFZ (+ DecentSampler)
with ConvertWithMoss, plus a sidecar and catalog entry for every instrument. See README.md."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from osp import TOOL_VERSION  # noqa: E402
from osp.runner import Run  # noqa: E402


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--source", required=True, help="root of the Open Samples collection (read only)")
    ap.add_argument("--out", required=True, help="output folder (outside the collection)")
    ap.add_argument("--cwm", help="path to ConvertWithMossCLI.exe (default: OSP_CWM, "
                                  r"D:\tools\ConvertWithMoss\..., or PATH)")
    ap.add_argument("--workers", type=int, default=max(1, min(4, (os.cpu_count() or 2) // 2)),
                    help="conversions run in parallel (default: %(default)s)")
    ap.add_argument("--only", action="append", metavar="GLOB",
                    help="work only on sources whose path (relative to the collection, '/' "
                         "separated) matches; a folder path selects everything under it. "
                         "Repeatable. The catalog still lists everything.")
    ap.add_argument("--exclude", action="append", metavar="GLOB",
                    help="leave out sources matching this (same matching as --only); they are "
                         "listed in the catalog as 'excluded'. Repeatable.")
    ap.add_argument("--dry-run", action="store_true", help="print what would happen; write nothing")
    ap.add_argument("--force", action="store_true", help="redo even unchanged instruments")
    ap.add_argument("--retry-failed", action="store_true",
                    help="redo unchanged instruments whose last attempt failed")
    ap.add_argument("--copy-wav", action="store_true",
                    help="also copy plain-WAV instruments into the output tree (byte for byte)")
    ap.add_argument("--no-decentsampler", action="store_true",
                    help="write only SFZ, not the DecentSampler preset")
    ap.add_argument("--timeout", type=int, default=3600,
                    help="seconds per ConvertWithMoss call (default: %(default)s)")
    ap.add_argument("--collection-name", default="Open Samples",
                    help="name recorded as the collection (default: %(default)s)")
    ap.add_argument("--collection-url", default="https://github.com/pumodi/open-samples",
                    help="where the collection comes from (default: %(default)s)")
    ap.add_argument("--license-note", help="licence text to record when the collection has no "
                                           "docs/LICENSE.md")
    ap.add_argument("--disk-images", metavar="FORMAT",
                    help="treat .img/.hfe/.edm/.ede/.eda/.iso files as disk images of this "
                         "ConvertWithMoss source format (e.g. mirage, ensoniq, emax, s1000)")
    g = ap.add_argument_group("DX7 voices (.syx banks)")
    g.add_argument("--dx7render", help=r"path to dx7render.exe (default: OSP_DX7RENDER or "
                                       r"D:\tools\dx7render\dx7render.exe)")
    g.add_argument("--dx7-notes", default="36,48,60,72,84",
                   help="MIDI keys played, in order (default: %(default)s)")
    g.add_argument("--dx7-velocities", default="100",
                   help="one render per velocity (default: %(default)s)")
    g.add_argument("--dx7-hold", type=float, default=2.0, help="seconds each key is held")
    g.add_argument("--dx7-release", type=float, default=2.5, help="seconds of release tail")
    g.add_argument("--dx7-gap", type=float, default=0.25, help="seconds of silence after each")
    g.add_argument("--dx7-rate", type=int, default=48000, help="sample rate (default: 48000)")
    g.add_argument("--dx7-engine", choices=["mki", "msfa"], default="mki",
                   help="Dexed engine: mki (Mark I, Dexed's default, closest to the hardware) "
                        "or msfa (the original Music Synthesizer for Android core)")
    ap.add_argument("--collection-version", help="override the collection version (default: "
                                                 "read from its README)")
    ap.add_argument("--collection-commit", help="git commit of the collection, if known")
    ap.add_argument("--download-date", help="date the collection was downloaded (YYYY-MM-DD)")
    ap.add_argument("--version", action="version", version=f"open_samples_prep {TOOL_VERSION}")
    return ap.parse_args(argv)


def main(argv=None):
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    return Run(parse_args(argv)).main()


if __name__ == "__main__":
    sys.exit(main())
