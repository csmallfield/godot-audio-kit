# Stress dictionary: how good the fallback rules are

Written by `addons/audio_kit/tools/stress_report.gd`. Regenerate rather than edit.

2000 held-out words (the most frequent words of two or more syllables past the shipped dictionary's cut, from `docs/stress/held_out.txt`) read by the rules alone, against their dictionary stress (CMUdict, or Moby where CMU lacks the word).

| | |
| --- | --- |
| The rules split the word into as many syllables as the dictionary | 1745 (87.2%) |
| ... and put the primary stress on the same syllable | 1326 (76.0% of those) |

## By rule

Words where the syllable counts agree, by the rule that placed the stress, most used first.

| Rule | Words | Right | Accuracy |
| --- | --- | --- | --- |
| first of two | 534 | 448 | 83.9% |
| neutral -s | 234 | 197 | 84.2% |
| antepenult | 168 | 89 | 53.0% |
| neutral -ing | 166 | 123 | 74.1% |
| neutral -ed | 124 | 78 | 62.9% |
| heavy penult | 103 | 48 | 46.6% |
| neutral -er | 91 | 81 | 89.0% |
| neutral -es | 74 | 52 | 70.3% |
| verb-like prefix | 44 | 23 | 52.3% |
| neutral -ly | 43 | 39 | 90.7% |
| before -tion | 38 | 35 | 92.1% |
| before -ic | 19 | 19 | 100.0% |
| before -ity | 15 | 14 | 93.3% |
| two before -ate | 15 | 15 | 100.0% |
| before -ical | 9 | 9 | 100.0% |
| neutral -ish | 8 | 7 | 87.5% |
| neutral -ment | 8 | 4 | 50.0% |
| neutral -ness | 8 | 8 | 100.0% |
| before -sion | 7 | 7 | 100.0% |
| neutral -less | 6 | 6 | 100.0% |
| two before -ize | 5 | 5 | 100.0% |
| before -ious | 4 | 4 | 100.0% |
| before -ial | 4 | 4 | 100.0% |
| two before -ise | 4 | 3 | 75.0% |
| neutral -ful | 4 | 4 | 100.0% |
| before -ian | 3 | 3 | 100.0% |
| stressed suffix -ee | 3 | 0 | 0.0% |
| neutral -ship | 1 | 0 | 0.0% |
| stressed suffix -ique | 1 | 0 | 0.0% |
| stressed suffix -ese | 1 | 1 | 100.0% |
| stressed suffix -ette | 1 | 0 | 0.0% |

## Some misses

word: rules / dictionary (capitals: the primary stress)

- unclaimed: UN·claimed / un·CLAIMED (neutral -ed)
- unnecessarily: un·ne·CES·sa·ri·ly / un·NE·ces·sa·ri·ly (neutral -ly)
- vuitton: VUIT·ton / vuit·TON (first of two)
- watermelon: wa·TER·me·lon / WA·ter·me·lon (antepenult)
- allotment: AL·lot·ment / al·LOT·ment (neutral -ment)
- alternating: al·TER·na·ting / AL·ter·na·ting (neutral -ing)
- behemoth: BE·he·moth / be·HE·moth (antepenult)
- caicedo: CAI·ce·do / cai·CE·do (antepenult)
- cementing: CE·men·ting / ce·MEN·ting (neutral -ing)
- chandigarh: CHAN·di·garh / chan·di·GARH (antepenult)
- coherent: CO·he·rent / co·HE·rent (antepenult)
- concentrating: con·CEN·tra·ting / CON·cen·tra·ting (neutral -ing)
- couture: COU·ture / cou·TURE (first of two)
- denzel: den·ZEL / DEN·zel (verb-like prefix)
- dissolve: DIS·solve / dis·SOLVE (first of two)
- equipping: E·quip·ping / e·QUIP·ping (neutral -ing)
- georgina: GEOR·gi·na / geor·GI·na (antepenult)
- imprint: IM·print / im·PRINT (first of two)
- infiltrated: in·FIL·tra·ted / IN·fil·tra·ted (neutral -ed)
- inhumane: IN·hu·mane / in·hu·MANE (antepenult)
- insolvency: in·sol·VEN·cy / in·SOL·ven·cy (heavy penult)
- joaquin: JOA·quin / joa·QUIN (first of two)
- kareem: KA·reem / ka·REEM (first of two)
- khalifa: KHA·li·fa / kha·LI·fa (antepenult)
- lanarkshire: la·NARK·shire / LA·nark·shire (heavy penult)
- macleod: MA·cleod / ma·CLEOD (first of two)
- melanoma: me·LA·no·ma / me·la·NO·ma (antepenult)
- moldova: MOL·do·va / mol·DO·va (antepenult)
- motorbikes: mo·TOR·bikes / MO·tor·bikes (neutral -es)
- nuveen: NU·veen / nu·VEEN (first of two)
- outperforming: out·PER·for·ming / OUT·per·for·ming (neutral -ing)
- overflow: o·VER·flow / O·ver·flow (heavy penult)
- overlooks: o·VER·looks / O·ver·looks (neutral -s)
- overt: O·vert / o·VERT (first of two)
- philosopher: PHI·lo·so·pher / phi·LO·so·pher (neutral -er)
- premiering: PRE·mie·ring / pre·MIE·ring (neutral -ing)
- proficient: PRO·fi·cient / pro·FI·cient (antepenult)
- redundancy: re·dun·DAN·cy / re·DUN·dan·cy (heavy penult)
- restrooms: re·STROOMS / RE·strooms (neutral -s)
- rutherford: ru·THER·ford / RU·ther·ford (heavy penult)
