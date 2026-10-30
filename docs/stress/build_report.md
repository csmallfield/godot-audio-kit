# Stress dictionary: build report

Written by `tools/build_stress_dict.py` on 2026-10-29. Regenerate rather than edit.

| | |
| --- | --- |
| CMUdict entries read (first pronunciations, plain letters) | 117485 |
| CMUdict entries skipped (apostrophes, digits, punctuation) | 8559 |
| Frequency list | none: every CMU word ships |
| Moby Hyphenator | not used |
| Moby Pronunciator cross-check | not done yet |
| Words shipped | 116398 |
| ... with more than one syllable | 101292 |
| Wanted but not in CMU (left to the fallback rules) | 0 |

## How the spellings were split

| Adjustment | Words |
| --- | --- |
| as the runtime splits it | 103386 |
| vowel pair split | 8031 |
| vowel groups merged | 2677 |
| silent e put back | 1802 |
| dropped: fewer letter groups than syllables | 964 |
| final syllabic consonant | 899 |
| dropped: no vowel letters | 123 |
| no vowel letters, one syllable | 33 |
