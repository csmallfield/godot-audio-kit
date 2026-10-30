# Stress dictionary: how good the fallback rules are

Written by `addons/audio_kit/tools/stress_report.gd`. Regenerate rather than edit.

2000 held-out words (the most frequent words of two or more syllables past the shipped dictionary's cut, from `docs/stress/held_out.txt`) read by the rules alone, against their dictionary stress (CMUdict, or Moby where CMU lacks the word).

| | |
| --- | --- |
| The rules split the word into as many syllables as the dictionary | 1728 (86.4%) |
| ... and put the primary stress on the same syllable | 1304 (75.5% of those) |

## By rule

Words where the syllable counts agree, by the rule that placed the stress, most used first.

| Rule | Words | Right | Accuracy |
| --- | --- | --- | --- |
| first of two | 610 | 544 | 89.2% |
| antepenult | 253 | 138 | 54.5% |
| neutral -s | 208 | 158 | 76.0% |
| heavy penult | 123 | 61 | 49.6% |
| neutral -ing | 106 | 82 | 77.4% |
| neutral -er | 103 | 96 | 93.2% |
| neutral -ed | 81 | 43 | 53.1% |
| neutral -es | 49 | 36 | 73.5% |
| neutral -ly | 35 | 25 | 71.4% |
| before -tion | 28 | 26 | 92.9% |
| before -ic | 24 | 23 | 95.8% |
| verb-like prefix | 21 | 7 | 33.3% |
| stressed suffix -ee | 14 | 4 | 28.6% |
| neutral -ness | 11 | 10 | 90.9% |
| before -ity | 10 | 10 | 100.0% |
| two before -ate | 8 | 8 | 100.0% |
| two before -ize | 7 | 6 | 85.7% |
| neutral -ment | 7 | 1 | 14.3% |
| before -ical | 6 | 6 | 100.0% |
| neutral -ful | 5 | 3 | 60.0% |
| before -ian | 4 | 4 | 100.0% |
| two before -ise | 4 | 3 | 75.0% |
| before -ious | 2 | 2 | 100.0% |
| neutral -ish | 2 | 2 | 100.0% |
| neutral -less | 1 | 1 | 100.0% |
| neutral -ship | 1 | 1 | 100.0% |
| before -ial | 1 | 0 | 0.0% |
| before -sion | 1 | 1 | 100.0% |
| stressed suffix -ese | 1 | 1 | 100.0% |
| neutral -hood | 1 | 1 | 100.0% |
| stressed suffix -ette | 1 | 1 | 100.0% |

## Some misses

word: rules / dictionary (capitals: the primary stress)

- roddenberry: rod·den·BER·ry / ROD·den·ber·ry (heavy penult)
- roundtree: round·TREE / ROUND·tree (stressed suffix -ee)
- rowena: RO·we·na / ro·WE·na (antepenult)
- rupaul: RU·paul / ru·PAUL (first of two)
- sacramental: sa·cra·MEN·tal / SA·cra·men·tal (heavy penult)
- saluted: SA·lu·ted / sa·LU·ted (neutral -ed)
- samsara: SAM·sa·ra / sam·SA·ra (antepenult)
- sanofi: SA·no·fi / sa·NO·fi (antepenult)
- sarcoma: SAR·co·ma / sar·CO·ma (antepenult)
- secretion: SE·cre·tion / se·CRE·tion (before -tion)
- sedans: SE·dans / se·DANS (neutral -s)
- seguin: SE·guin / se·GUIN (first of two)
- seraphim: SE·ra·phim / se·ra·PHIM (antepenult)
- shellacking: SHEL·lack·ing / shel·LACK·ing (neutral -ing)
- silicosis: si·LI·co·sis / si·li·CO·sis (neutral -s)
- silverton: sil·VER·ton / SIL·ver·ton (heavy penult)
- skyrockets: sky·ROCK·ets / SKY·rock·ets (neutral -s)
- southernmost: sou·THERN·most / SOU·thern·most (heavy penult)
- stenographer: STE·no·gra·pher / ste·NO·gra·pher (neutral -er)
- stepchildren: step·CHIL·dren / STEP·CHIL·dren (heavy penult)
- succumbs: SUC·cumbs / suc·CUMBS (neutral -s)
- summarily: SUM·ma·ri·ly / sum·MA·ri·ly (neutral -ly)
- supercharger: su·PER·char·ger / SU·per·char·ger (neutral -er)
- superfan: su·PER·fan / SU·per·fan (heavy penult)
- supersedes: SU·per·sedes / su·per·SEDES (neutral -es)
- supplanted: SUP·plan·ted / sup·PLAN·ted (neutral -ed)
- suppresses: SUP·pres·ses / sup·PRES·ses (neutral -es)
- surveil: SUR·veil / sur·VEIL (first of two)
- svoboda: SVO·bo·da / svo·BO·da (antepenult)
- swaminathan: swa·MI·na·than / swa·mi·NA·than (antepenult)
- tabu: TA·bu / ta·BU (first of two)
- tagore: TA·gore / ta·GORE (first of two)
- takeda: TA·ke·da / ta·KE·da (antepenult)
- tartare: TAR·tare / tar·TARE (first of two)
- tejada: TE·ja·da / te·JA·da (antepenult)
- telekinesis: te·le·KI·ne·sis / te·le·ki·NE·sis (neutral -s)
- teradata: te·RA·da·ta / te·ra·DA·ta (antepenult)
- tiramisu: ti·RA·mi·su / ti·ra·MI·su (antepenult)
- torino: TO·ri·no / to·RI·no (antepenult)
- toyoda: TO·yo·da / to·YO·da (antepenult)
