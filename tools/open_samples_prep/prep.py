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
