# Stress dictionary: coverage of real dialogue

Written by `addons/audio_kit/tools/stress_coverage.gd`. Regenerate rather than edit.

Every word token read the way the runtime reads it (no lexicon), against each dictionary. Function words are never stressed and are left out. "Wrong" means the primary stress lands on another syllable than the full CMU dictionary's, or the syllable count differs; tokens the full dictionary lacks (names, coinages) aren't scored.

Left out as lexicon words (the characters' names): algernon, bracknell, cecily, chasuble, doolittle, eynsford, farquhar, freddy, gwendolen, higgins, liza, merriman, moncrieff, pearce, pickering, prism, pygmalion, worthing.

## demo lines (29 content-word tokens, 25 distinct)

| Dictionary | Words | In the dictionary | Stem + suffix | Compound | Rules, one syllable | Rules, longer | Wrong primary stress |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20k | 18893 | 96.6% | 0.0% | 0.0% | 0.0% | 3.4% | 0.0% |
| 50k | 40890 | 96.6% | 0.0% | 0.0% | 0.0% | 3.4% | 0.0% |

## pygmalion (16061 content-word tokens, 4219 distinct)

| Dictionary | Words | In the dictionary | Stem + suffix | Compound | Rules, one syllable | Rules, longer | Wrong primary stress |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20k | 18893 | 85.0% | 3.9% | 1.1% | 3.8% | 6.1% | 2.1% |

Wrong with 20k (most frequent first): whats ×21, pronunciation ×7, resolutely ×7, undeserving ×7, bachelors ×6, elizabethan ×6, impatiently ×6, agreeable ×5, dialects ×5, divan ×5, awfully ×4, dialect ×4, genteel ×4, aha ×3, disagreeable ×3, melancholy ×3, reproducing ×3, savagely ×3, ungrateful ×3, amazement ×2, amiable ×2, anwell ×2, apostrophes ×2, asparagus ×2, biologically ×2

| 50k | 40890 | 91.3% | 2.2% | 1.0% | 3.1% | 2.4% | 0.9% |

Wrong with 50k (most frequent first): whats ×21, phonetics ×11, undeserving ×7, elizabethan ×6, phonetic ×6, divan ×5, disagreeable ×3, miltonic ×3, savagely ×3, ungrateful ×3, anwell ×2, apostrophes ×2, brusquely ×2, confounded ×2, dickensian ×2, incorrigible ×2, niceness ×2, presumptuous ×2, rudely ×2, absurdities, alliteration, apologetically, assailing, astride, attired


## earnest (9863 content-word tokens, 2475 distinct)

| Dictionary | Words | In the dictionary | Stem + suffix | Compound | Rules, one syllable | Rules, longer | Wrong primary stress |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 20k | 18893 | 90.3% | 1.9% | 0.8% | 1.6% | 5.3% | 1.6% |

Wrong with 20k (most frequent first): amazement ×3, excessively ×3, hopelessly ×3, indignant ×3, tedious ×3, amuse ×2, amuses ×2, apoplexy ×2, astounded ×2, bachelors ×2, baptism ×2, celibacy ×2, curiously ×2, distasteful ×2, entanglement ×2, entrapped ×2, excesses ×2, forte ×2, gravely ×2, grosvenor ×2, incomparable ×2, indignantly ×2, induce ×2, instinctively ×2, invariably ×2

| 50k | 40890 | 94.7% | 1.0% | 1.1% | 1.1% | 2.1% | 0.4% |

Wrong with 50k (most frequent first): indignant ×3, apoplexy ×2, celibacy ×2, indignantly ×2, remotest ×2, triviality ×2, untruthful ×2, analogies, attentively, depress, disown, effrontery, fluently, indiscretion, irretrievably, lessee, matrimony, messrs, mislaid, perrier, precept, presumptuous, punctual, recollect, redoubled
