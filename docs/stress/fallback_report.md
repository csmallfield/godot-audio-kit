# Stress dictionary: how good the fallback rules are

Written by `addons/audio_kit/tools/stress_report.gd`. Regenerate rather than edit.

2000 held-out words (the most frequent words of two or more syllables past the shipped dictionary's cut, from `docs/stress/held_out.txt`) read by the rules alone, against their dictionary stress (CMUdict, or Moby where CMU lacks the word).

| | |
| --- | --- |
| The rules split the word into as many syllables as the dictionary | 1728 (86.4%) |
| ... and put the primary stress on the same syllable | 1402 (81.1% of those) |

## By rule

Words where the syllable counts agree, by the rule that placed the stress, most used first.

| Rule | Words | Right | Accuracy |
| --- | --- | --- | --- |
| first of two | 620 | 554 | 89.4% |
| antepenult | 251 | 172 | 68.5% |
| neutral -s | 208 | 165 | 79.3% |
| penult before a final vowel | 119 | 102 | 85.7% |
| neutral -ing | 106 | 84 | 79.2% |
| neutral -er | 103 | 98 | 95.1% |
| neutral -ed | 81 | 44 | 54.3% |
| neutral -es | 49 | 34 | 69.4% |
| neutral -ly | 35 | 26 | 74.3% |
| before -tion | 28 | 26 | 92.9% |
| before -ic | 24 | 23 | 95.8% |
| stressed suffix -ee | 14 | 4 | 28.6% |
| neutral -ness | 11 | 10 | 90.9% |
| verb-like prefix | 11 | 7 | 63.6% |
| before -ity | 10 | 10 | 100.0% |
| two before -ate | 8 | 8 | 100.0% |
| two before -ize | 7 | 6 | 85.7% |
| neutral -ment | 7 | 1 | 14.3% |
| before -ary, -ory | 6 | 2 | 33.3% |
| before -ical | 6 | 6 | 100.0% |
| neutral -ful | 5 | 3 | 60.0% |
| before -ian | 4 | 4 | 100.0% |
| two before -ise | 4 | 3 | 75.0% |
| neutral -ish | 2 | 2 | 100.0% |
| before -ious | 2 | 2 | 100.0% |
| neutral -less | 1 | 1 | 100.0% |
| neutral -ship | 1 | 1 | 100.0% |
| before -ial | 1 | 0 | 0.0% |
| before -sion | 1 | 1 | 100.0% |
| stressed suffix -ese | 1 | 1 | 100.0% |
| neutral -hood | 1 | 1 | 100.0% |
| stressed suffix -ette | 1 | 1 | 100.0% |

## Some misses

word: rules / dictionary (capitals: the primary stress)

- roddenberry: rod·DEN·ber·ry / ROD·den·ber·ry (antepenult)
- romulus: ro·MU·lus / RO·mu·lus (neutral -s)
- roundtree: round·TREE / ROUND·tree (stressed suffix -ee)
- rupaul: RU·paul / ru·PAUL (first of two)
- sacramental: sa·CRA·men·tal / SA·cra·men·tal (antepenult)
- saluted: SA·lu·ted / sa·LU·ted (neutral -ed)
- secretion: SE·cre·tion / se·CRE·tion (before -tion)
- sedans: SE·dans / se·DANS (neutral -s)
- seguin: SE·guin / se·GUIN (first of two)
- seraphim: SE·ra·phim / se·ra·PHIM (antepenult)
- shellacking: SHEL·lack·ing / shel·LACK·ing (neutral -ing)
- stenographer: STE·no·gra·pher / ste·NO·gra·pher (neutral -er)
- succumbs: SUC·cumbs / suc·CUMBS (neutral -s)
- supersedes: SU·per·sedes / su·per·SEDES (neutral -es)
- supplanted: SUP·plan·ted / sup·PLAN·ted (neutral -ed)
- suppressant: SUP·pres·sant / sup·PRES·sant (antepenult)
- suppresses: SUP·pres·ses / sup·PRES·ses (neutral -es)
- surveil: SUR·veil / sur·VEIL (first of two)
- swaminathan: swa·MI·na·than / swa·mi·NA·than (antepenult)
- tabu: TA·bu / ta·BU (first of two)
- tagore: TA·gore / ta·GORE (first of two)
- tapestries: ta·PE·stries / TA·pe·stries (neutral -es)
- tartare: TAR·tare / tar·TARE (first of two)
- tempura: tem·PU·ra / TEM·pu·ra (penult before a final vowel)
- traitorous: trai·TO·rous / TRAI·to·rous (neutral -s)
- transcribe: TRAN·scribe / tran·SCRIBE (first of two)
- transporters: TRAN·spor·ters / tran·SPOR·ters (neutral -s)
- trevelyan: TRE·vel·yan / tre·VEL·yan (antepenult)
- typhoons: TY·phoons / ty·PHOONS (neutral -s)
- tyrrell: TYR·rell / tyr·RELL (first of two)
- unawares: U·na·wares / u·na·WARES (neutral -es)
- unbothered: UN·bo·thered / un·BO·thered (neutral -ed)
- uncollected: UN·col·lec·ted / un·col·LEC·ted (neutral -ed)
- uncompleted: UN·com·ple·ted / un·com·PLE·ted (neutral -ed)
- unconstrained: UN·con·strained / un·con·STRAINED (neutral -ed)
- undaunted: UN·daun·ted / un·DAUN·ted (neutral -ed)
- underinsured: un·DE·rin·sured / un·de·rin·SURED (neutral -ed)
- underpowered: UN·der·po·wered / un·der·PO·wered (neutral -ed)
- underreporting: un·DER·re·por·ting / UN·der·re·POR·ting (neutral -ing)
- uneventful: U·ne·vent·ful / u·ne·VENT·ful (neutral -ful)
