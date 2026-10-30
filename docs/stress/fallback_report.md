# Stress dictionary: how good the fallback rules are

Written by `addons/audio_kit/tools/stress_report.gd`. Regenerate rather than edit.

2000 dictionary words of two or more syllables (picked by a fixed hash) read by the rules alone, against the dictionary (CMUdict).

| | |
| --- | --- |
| The rules split the word into as many syllables as the dictionary | 1771 (88.5%) |
| ... and put the primary stress on the same syllable | 1336 (75.4% of those) |

## By rule

Words where the syllable counts agree, by the rule that placed the stress, most used first.

| Rule | Words | Right | Accuracy |
| --- | --- | --- | --- |
| first of two | 614 | 550 | 89.6% |
| antepenult | 239 | 116 | 48.5% |
| neutral -s | 213 | 171 | 80.3% |
| heavy penult | 181 | 98 | 54.1% |
| neutral -er | 132 | 124 | 93.9% |
| neutral -ing | 95 | 79 | 83.2% |
| neutral -ed | 73 | 41 | 56.2% |
| neutral -es | 50 | 36 | 72.0% |
| verb-like prefix | 46 | 13 | 28.3% |
| neutral -ly | 24 | 20 | 83.3% |
| before -tion | 19 | 17 | 89.5% |
| before -ic | 15 | 15 | 100.0% |
| two before -ate | 11 | 10 | 90.9% |
| before -ity | 10 | 8 | 80.0% |
| stressed suffix -ette | 8 | 7 | 87.5% |
| before -sion | 7 | 4 | 57.1% |
| before -ious | 6 | 6 | 100.0% |
| neutral -ful | 4 | 4 | 100.0% |
| neutral -ment | 4 | 1 | 25.0% |
| two before -ize | 3 | 3 | 100.0% |
| neutral -ish | 3 | 3 | 100.0% |
| stressed suffix -ee | 3 | 0 | 0.0% |
| neutral -ness | 3 | 3 | 100.0% |
| before -ical | 3 | 3 | 100.0% |
| stressed suffix -ese | 2 | 1 | 50.0% |
| stressed suffix -eer | 2 | 2 | 100.0% |
| before -ian | 1 | 1 | 100.0% |

## Some misses

word: rules / dictionary (capitals: the primary stress)

- repka: rep·KA / REP·ka (verb-like prefix)
- mactan: MAC·tan / mac·TAN (first of two)
- expansionist: ex·pan·SIO·nist / ex·PAN·sio·nist (heavy penult)
- promenades: PRO·me·nades / pro·me·NADES (neutral -es)
- wattenbarger: wat·TEN·bar·ger / WAT·ten·bar·ger (neutral -er)
- baluchi: BA·lu·chi / ba·LU·chi (antepenult)
- effervescent: ef·FER·ve·scent / ef·fer·VE·scent (antepenult)
- disavowed: DI·sa·vowed / di·sa·VOWED (neutral -ed)
- disclaimed: DIS·claimed / dis·CLAIMED (neutral -ed)
- rebar: re·BAR / RE·bar (verb-like prefix)
- berlex: ber·LEX / BER·lex (verb-like prefix)
- thivierge: THI·vierge / thi·VIERGE (first of two)
- stigmata: STIG·ma·ta / stig·MA·ta (antepenult)
- brentanos: BREN·ta·nos / bren·TA·nos (neutral -s)
- indict: IN·dict / in·DICT (first of two)
- cantina: CAN·ti·na / can·TI·na (antepenult)
- indigest: IN·di·gest / in·di·GEST (antepenult)
- norenberg: no·REN·berg / NO·ren·berg (heavy penult)
- postlethwait: post·LETH·wait / POST·leth·wait (heavy penult)
- postponed: POST·poned / post·PONED (neutral -ed)
- indirectly: IN·di·rect·ly / in·di·RECT·ly (neutral -ly)
- normalcy: nor·MAL·cy / NOR·mal·cy (heavy penult)
- arnaud: AR·naud / ar·NAUD (first of two)
- butulesi: bu·TU·le·si / bu·tu·LE·si (antepenult)
- romancing: RO·man·cing / ro·MAN·cing (neutral -ing)
- subscribe: SUB·scribe / sub·SCRIBE (first of two)
- demore: de·MORE / DE·more (verb-like prefix)
- lakota: LA·ko·ta / la·KO·ta (antepenult)
- becky: beck·Y / BECK·y (verb-like prefix)
- lalit: LA·lit / la·LIT (first of two)
- buttermore: but·TER·more / BUT·ter·more (heavy penult)
- legault: LE·gault / le·GAULT (first of two)
- milissent: mi·LIS·sent / MI·lis·sent (heavy penult)
- crestfallen: crest·FAL·len / CREST·fal·len (heavy penult)
- eckenroth: eck·EN·roth / ECK·en·roth (heavy penult)
- rengel: reng·EL / RENG·el (verb-like prefix)
- frankiewicz: fran·KIE·wicz / FRAN·kie·wicz (heavy penult)
- abbenhaus: ab·BEN·haus / AB·ben·haus (neutral -s)
- ecuadoran: e·CUA·do·ran / e·cua·DO·ran (antepenult)
- ecosystems: e·CO·sy·stems / E·co·sy·stems (neutral -s)
