# Stress dictionary: build report

Written by `tools/build_stress_dict.py` on 2026-10-30. Regenerate rather than edit.

| | |
| --- | --- |
| CMUdict entries read (first pronunciations, plain letters) | 117485 |
| CMUdict entries skipped (apostrophes, digits, punctuation) | 8559 |
| Frequency list | eng_news_2023_1M-words.txt, top 20000 forms |
| Moby Hyphenator | not used |
| Moby Pronunciator | 94382 words with a usable stress mark |
| Words shipped | 18893 |
| ... with more than one syllable | 14811 |
| ... from Moby (not in CMU) | 186 |
| ... where CMU and Moby put the primary stress on different syllables (CMU kept) | 255 |
| Wanted but in neither (left to the fallback rules) | 958 |
| Held-out words written for the fallback report | 3000 |

Over every word both know: 29369 compared (two or more syllables, same count), 27843 agree on the primary stress, 1526 differ (5.2%); 6214 not comparable (one syllable or different syllable counts).

## How the spellings were split

| Adjustment | Words |
| --- | --- |
| as the runtime splits it | 17078 |
| vowel pair split | 1000 |
| vowel groups merged | 508 |
| silent e put back | 197 |
| final syllabic consonant | 133 |
| dropped: fewer letter groups than syllables | 86 |
| dropped: no vowel letters | 63 |
| no vowel letters, one syllable | 28 |

## CMU vs Moby: primary stress disagreements in the shipped words

CMU wins. word: CMU / Moby (capitals: the primary stress). Most are noun/verb homographs (CMU's first reading) and names.

- central: CEN·tral / cen·TRAL
- address: AD·dress / ad·DRESS
- content: CON·tent / con·TENT
- sometimes: some·TIMES / SOME·times
- unique: uni·QUE / UNI·que
- perfect: per·FECT / PER·fect
- infrastructure: in·fra·STRUC·ture / IN·fra·struc·ture
- afternoon: af·ter·NOON / AF·ter·NOON
- toward: to·WARD / TO·ward
- upcoming: UP·co·ming / up·CO·ming
- decade: de·CADE / DE·cade
- transport: tran·SPORT / TRAN·sport
- produce: pro·DUCE / PRO·duce
- robert: RO·bert / ro·BERT
- debut: de·BUT / DE·but
- survey: sur·VEY / SUR·vey
- expert: EX·pert / ex·PERT
- concert: CON·cert / con·CERT
- richard: RI·chard / ri·CHARD
- outperform: OUT·per·form / out·per·FORM
- impacted: IM·pac·ted / im·PAC·ted
- engineering: ENG·i·NEE·ring / eng·i·NEE·ring
- detail: de·TAIL / DE·tail
- passes: PAS·ses / pas·SES
- reporter: re·POR·ter / re·por·TER
- upgrade: up·GRADE / UP·grade
- collect: col·LECT / COL·lect
- recall: RE·call / re·CALL
- concrete: con·CRETE / CON·crete
- overcome: O·ver·come / o·ver·COME
- inventory: in·ven·TO·ry / IN·ven·to·ry
- overseas: O·ver·SEAS / o·ver·SEAS
- export: EX·port / ex·PORT
- magazine: MA·ga·zine / ma·ga·ZINE
- caribbean: ca·RIB·be·an / ca·rib·BE·an
- excess: EX·cess / ex·CESS
- proceeds: pro·CEEDS / PRO·ceeds
- permit: per·MIT / PER·mit
- engineer: ENG·i·NEER / eng·i·NEER
- karen: KA·ren / ka·REN
- desert: DE·sert / de·SERT
- smoking: SMO·king / smo·KING
- offset: off·SET / OFF·set
- combine: COM·bine / com·BINE
- westminster: west·MIN·ster / WEST·min·ster
- rebound: re·BOUND / RE·bound
- refugee: RE·fu·gee / re·fu·GEE
- superstar: su·per·STAR / SU·per·star
- outdoors: OUT·DOORS / out·DOORS
- duration: DU·RA·tion / du·RA·tion
- qatar: qa·TAR / QA·tar
- analytics: a·na·LY·tics / a·NA·ly·tics
- canberra: can·BER·ra / CAN·ber·ra
- photograph: PHO·to·graph / pho·TO·graph
- referee: re·fe·REE / RE·fe·ree
- costume: co·STUME / CO·stume
- unite: U·nite / u·NITE
- gabriel: GA·bri·el / ga·bri·EL
- sharon: SHA·ron / sha·RON
- triumph: TRI·umph / tri·UMPH
- intellectual: in·tel·LEC·tu·al / in·TEL·lec·tu·al
- straightforward: STRAIGHT·FOR·ward / straight·FOR·ward
- overhaul: O·ver·haul / o·ver·HAUL
- coordination: co·or·di·NA·tion / co·or·DI·na·tion
- syndrome: SYN·drome / syn·DROME
- inverness: IN·ver·ness / in·ver·NESS
- reject: re·JECT / RE·ject
- undermine: UN·der·mine / un·der·MINE
- thereby: THERE·BY / there·BY
- avatar: A·va·tar / a·va·TAR
- janet: JA·net / ja·NET
- undertake: UN·der·take / un·der·TAKE
- overturn: O·ver·turn / o·ver·TURN
- circulation: CIR·cu·la·tion / cir·cu·LA·tion
- contracted: CON·trac·ted / con·TRAC·ted
- extract: EX·tract / ex·TRACT
- tamil: ta·MIL / TA·mil
- surcharge: sur·CHARGE / SUR·charge
- relay: RE·lay / re·LAY
- leon: LE·on / le·ON
- exploit: EX·ploit / ex·PLOIT
- andrea: AN·dre·a / an·DRE·a
- continental: con·ti·NEN·tal / con·TI·nen·tal
- overhead: O·ver·HEAD / o·ver·HEAD
- underwater: UN·der·wa·ter / un·der·WA·ter
- islam: i·SLAM / I·slam
- gasoline: GA·so·line / ga·so·LINE
- hezbollah: HEZ·bol·lah / hez·bol·LAH
- upfront: UP·front / up·FRONT
- undertaking: UN·der·ta·king / un·der·TA·king
- oversee: O·ver·see / o·ver·SEE
- goodwill: GOOD·WILL / good·WILL
- cyclone: cy·CLONE / CY·clone
- outrageous: ou·TRA·geous / OU·tra·geous
- portuguese: POR·tu·guese / por·tu·GUESE
- kazakhstan: ka·zakh·STAN / ka·ZAKH·stan
- reminiscent: re·mi·NI·scent / re·MI·ni·scent
- midwest: mid·WEST / MID·WEST
- regeneration: re·GE·ne·RA·tion / re·ge·ne·RA·tion
- ferdinand: FER·di·nand / fer·di·NAND
- hyderabad: hy·DE·ra·bad / HY·de·ra·bad
- xavier: XA·vier / xa·VIER
- bengal: BENG·al / beng·AL
- outdated: OUT·da·ted / out·DA·ted
- fifteen: fif·TEEN / FIF·TEEN
- herbert: HER·bert / her·BERT
- indoors: IN·doors / in·DOORS
- jammu: jam·MU / JAM·mu
- patriotic: pa·tri·O·tic / PA·tri·o·tic
- ramadan: RA·ma·dan / ra·ma·DAN
- accent: ac·CENT / AC·cent
- navigation: NA·vi·GA·tion / na·vi·GA·tion
- kerala: ke·RA·la / KE·ra·la
- underweight: UN·der·weight / un·der·WEIGHT
- carlisle: CARLI·sle / carli·SLE
- forbidden: FOR·bid·den / for·BID·den
- overdue: O·ver·DUE / o·ver·DUE
- picturesque: PIC·tures·que / pic·tures·QUE
- onstage: on·STAGE / ON·STAGE
- rampage: RAM·page / ram·PAGE
- lebanese: LE·ba·nese / le·ba·NESE
- standalone: STAN·da·lone / stan·da·LONE
- gallant: GAL·lant / gal·LANT
- hassan: has·SAN / HAS·san
- nicolas: NI·co·las / ni·co·LAS
- academia: a·ca·DE·mi·a / A·ca·DE·mi·a
- sofia: so·FI·a / SO·fi·a
- endurance: EN·du·rance / en·DU·rance
- ivan: I·van / i·VAN
- voluntarily: vo·lun·TA·ri·ly / VO·lun·ta·ri·ly
- outspoken: OUT·SPO·ken / out·SPO·ken
- conversely: CON·ver·sely / con·VER·sely
- firsthand: firs·THAND / FIRS·THAND
- durant: DU·rant / du·RANT
- wolverine: wol·ve·RINE / WOL·ve·rine
- insecure: IN·se·cure / in·se·CURE
- recognizable: re·cog·NI·za·ble / RE·cog·ni·za·ble
- kathleen: kath·LEEN / KATH·leen
- nana: NA·na / na·NA
- advertisement: ad·VER·tise·ment / ad·ver·TISE·ment
- bangkok: bang·KOK / BANG·kok
- deterioration: de·TE·ri·o·ra·tion / de·te·ri·o·RA·tion
- dictator: dic·TA·tor / DIC·ta·tor
- buffet: BUF·fet / buf·FET
- harassed: ha·RASSED / HA·rassed
- ovation: o·VA·tion / O·va·tion
- uprising: u·PRI·sing / U·pri·sing
- jihad: JI·had / ji·HAD
- uplift: U·plift / u·PLIFT
- overcame: O·ver·CAME / o·ver·CAME
- governmental: GO·vern·men·tal / go·vern·MEN·tal
- overlook: O·ver·look / o·ver·LOOK
- sixteen: six·TEEN / SIX·TEEN
- palette: PA·lette / pa·LETTE
- recreate: RE·cre·ate / re·cre·ATE
- instinct: IN·stinct / in·STINCT
- vacate: VA·cate / va·CATE
- asean: a·SE·an / A·se·an
- escort: e·SCORT / E·scort
- jenin: JE·nin / je·NIN
- gerard: ge·RARD / GE·rard
- outpouring: out·POU·ring / OUT·pou·ring
- yoruba: yo·RU·ba / YO·ru·ba
- benin: BE·nin / be·NIN
- extraordinarily: ex·traor·di·NA·ri·ly / ex·traor·DI·na·ri·ly
- liaison: lia·I·son / lia·i·SON
- preschool: pres·CHOOL / PRES·chool
- consort: con·SORT / CON·sort
- intercontinental: in·ter·con·ti·NEN·tal / in·ter·con·TI·nen·tal
- narrator: NAR·ra·tor / nar·RA·tor
- tanzania: tan·ZA·ni·a / tan·za·NI·a
- copenhagen: CO·pen·ha·gen / co·pen·HA·gen
- hardworking: HARD·wor·king / hard·WOR·king
- moray: mo·RAY / MO·ray
- ventilation: ven·ti·LA·tion / ven·TI·la·tion
- automobile: AU·to·mo·bile / au·to·mo·BILE
- homegrown: HOME·GROWN / home·GROWN
- legit: LE·git / le·GIT
- perfume: per·FUME / PER·fume
- celebratory: ce·LE·bra·to·ry / CE·le·bra·to·ry
- colon: CO·lon / co·LON
- dupont: DU·pont / du·PONT
- para: PA·ra / pa·RA
- pauline: pau·LINE / PAU·line
- accolade: AC·co·lade / ac·co·LADE
- marin: MA·rin / ma·RIN
- upright: u·PRIGHT / U·pright
- abdomen: ab·DO·men / AB·do·men
- ruben: RU·ben / ru·BEN
- carousel: CA·rou·sel / ca·rou·SEL
- forearm: fo·REARM / FO·rearm
- gabrielle: GA·briel·le / ga·briel·LE
- belgrade: BEL·grade / bel·GRADE
- sabine: sa·BINE / SA·bine
- taiwanese: TAI·wa·NESE / tai·wa·NESE
- adolescent: a·do·LE·scent / a·DO·le·scent
- nonpartisan: non·PAR·ti·san / NON·PAR·ti·san
- prasad: PRA·sad / pra·SAD
- superpower: su·per·PO·wer / SU·per·po·wer
- carnegie: CAR·ne·gie / car·NE·gie
- michel: mi·CHEL / MI·chel
- uzbekistan: uz·BE·ki·stan / uz·be·ki·STAN
- adept: a·DEPT / A·dept
- cameroon: CA·me·roon / ca·me·ROON
- sarawak: SA·ra·wak / sa·RA·wak
- westmoreland: west·MORE·land / WEST·more·land
- dunedin: DU·ne·din / du·NE·din
- pervasive: per·VA·sive / PER·va·sive
- underscore: un·der·SCORE / UN·der·score
- costello: co·STEL·lo / CO·stel·lo
- onscreen: on·SCREEN / ON·screen
- understatement: UN·der·state·ment / un·der·STATE·ment
- despicable: de·SPI·ca·ble / DE·spi·ca·ble
- raphael: ra·pha·EL / RA·pha·el
- trainee: TRAI·NEE / trai·NEE
- viola: vi·O·la / VI·o·la
- impasse: im·PASSE / IM·passe
- curtail: cur·TAIL / CUR·tail
- lagrange: LA·grange / la·GRANGE
- override: O·ver·ride / o·ver·RIDE
- archdiocese: ARCH·DI·o·cese / arch·DI·o·cese
- diagnose: di·ag·NOSE / DI·ag·nose
- lemonade: LE·mo·NADE / le·mo·NADE
- overrun: O·ver·run / o·ver·RUN
- underestimate: UN·de·RE·sti·mate / un·de·RE·sti·mate
- diagnostics: di·ag·NO·stics / DI·ag·NO·stics
- fiance: fi·AN·ce / fi·an·CE
- unborn: UN·BORN / un·BORN
- andres: AN·dres / an·DRES
- annex: AN·nex / an·NEX
- eighteen: eigh·TEEN / EIGH·TEEN
- overtake: O·ver·take / o·ver·TAKE
- defect: DE·fect / de·FECT
- detour: de·TOUR / DE·tour
- digest: di·GEST / DI·gest
- andrei: AN·drei / an·DREI
- colbert: COL·bert / col·BERT
- misogyny: MI·so·gy·ny / mi·SO·gy·ny
- srinagar: SRI·na·gar / sri·NA·gar
- madeleine: ma·de·LEINE / MA·de·leine
- sergey: SER·gey / ser·GEY
- suarez: sua·REZ / SUA·REZ
- carlyle: CAR·lyle / car·LYLE
- davos: DA·vos / da·VOS
- kiosk: KI·osk / ki·OSK
- lingerie: LING·e·rie / ling·e·RIE
- mustafa: mu·STA·fa / MU·sta·fa
- outweigh: OU·tweigh / ou·TWEIGH
- luzon: LU·zon / lu·ZON
- assay: AS·say / as·SAY
- attendee: at·TEN·DEE / at·ten·DEE
- ballon: BAL·lon / bal·LON
- colleen: col·LEEN / COL·leen
- incarnation: in·CAR·NA·tion / in·car·NA·tion
- obsolete: OB·so·lete / ob·so·LETE

## From Moby (not in CMU)

aa, abbotsford, aberdeenshire, abia, ahmedabad, analyse, anil, apis, armoured, artemis, authorised, aviva, bakhmut, basildon, bayern, bedfordshire, behavioural, benue, bihar, blantyre, boko, bournemouth, buckinghamshire, cambridgeshire, carabao, carriageway, cheltenham, chilli, clothesline, coachella, coastguard, colchester, collaboratively, collation, colourful, councillor, criticise, crore, crossbar, croydon, cwm, damar, defenseman, demerara, dodgy, doncaster, donegal, donetsk, doubleheader, dubbo, dumfries, dunfermline, dup, ea, embiid, enugu, eurovision, fa, falkirk, favourable, favoured, fermanagh, fertiliser, flavour, flintshire, footy, fulham, gaffer, ganesha, gateshead, ge, geelong, geode, gerrard, gloucestershire, goaltender, gosling, greenock, grimsby, gruelling, hampden, haram, heatwave, helmed, helpline, herefordshire, hertfordshire, hoodie, hotspur, huddersfield, ibadan, idris, igbo, impactful, indore, instalment, interment, ipswich, jewellery, jota, juneteenth, kaduna, kamala, kamloops, keighley, kherson, kidderminster, kildare, kraken, lahaina, lakh, layup, leicestershire, leinster, lilongwe, litre, loki, lucknow, macron, maduro, manipur, maths, medallist, mercia, mescal, midfield, mindfulness, minimise, moneta, motorway, neckline, netball, nnamdi, northamptonshire, northumberland, nottinghamshire, obi, offence, offside, organise, oxfordshire, paedophile, panchayat, penticton, physicality, playable, playmaker, positivity, postcode, powys, prof, punjabi, quran, racecourse, raja, rajasthan, realising, regenerative, renfrewshire, rishi, rotherham, salford, sceptical, scrum, sei, shiv, sith, sligo, snowpack, sokoto, swansea, tailwind, takedown, tallinn, tamworth, thakur, torquay, tripura, trope, tumour, warwickshire, wigan, wollongong, wolverhampton, yarmouth, zonal

## Wanted but in neither CMU nor Moby (the fallback rules read these)

Most frequent first. Names a project uses belong in its lexicon.

etf, eps, covid, tiktok, rs, mp, nhs, ii, tinubu, btc, bjp, nsw, marketbeat, sunak, gop, jpmorgan, chatgpt, offences, organised, lgbtq, pe, midfielder, mps, councillors, iii, abuja, pdp, wwe, cllr, kyiv, ebitda, fc, ncaa, ishares, inec, snp, cryptocurrency, plc, programmes, citigroup, rbi, elon, mcu, buhari, rcmp, cybersecurity, td, nhl, qb, ubs, wrexham, postseason, cbd, fentanyl, organisers, afc, gp, km, itv, afp, evs, enquiries, aew, coronavirus, criticised, openai, immersive, mvp, antisemitism, cm, idf, uae, zelensky, ethereum, karnataka, usd, cbn, relegation, djokovic, influencer, mlb, prigozhin, brexit, belarusian, avengers, mla, narendra, sabha, volodymyr, airpods, emphasised, imf, anc, cpi, erdogan, esg, mahomes, messi, yousaf, truist, jalen, ufc, usc, chatbot, atiku, svb, bengaluru, ohtani, cumbria, favourites, ucla, bmo, cryptocurrencies, airbnb, carers, gbx, madhya, abubakar, footballer, kc, evp, sc, multiverse, lockdowns, msci, ny, cr, etfs, verstappen, antisemitic, dlc, telangana, earbuds, opioid, organising, rtx, zelenskyy, cpr, muhammadu, influencers, capex, icc, metaverse, vr, aktiengesellschaft, vpn, ft, gb, mizuho, msp, ahsoka, cbi, ftx, llp, pti, var, podcasts, lsu, renewables, guyanese, iv, nxt, cu, huskies, kelce, macquarie, ransomware, anambra, cagr, uefa, gmt, lng, ramaswamy, uc, mls, anfield, imran, honours, relatable, sourced, vaping, adani, ipl, ndp, rpg, suplex, brics, hd, fct, kg, yadav, coun, pnc, ageing, belichick, conor, dei, flavours, rbis, aap, jinping, alhaji, counselling, emoji, pt, brentford, jokic, oled, backstory, eskom, thestreet, captrust, doj, harrogate, odisha, hc, mm, osun, ctv, luffy, mjf, nyc, ps, dem, equaliser, arteta, fy, kishida, nc, coinbase, fintech, gaap, quarterfinals, merseyside, aj, ecowas, inclusivity, rukh, skincare, humza, maga, ofsted, ogun, mlas, yusuf, oneplus, fanbase, lgbt, mifepristone, psg, roku, tcu, va, adv, pfas, sb, unc, abdullahi, efcc, ep, ipo, jd, guterres, prioritise, wga, binance, netizens, odi, organiser, rashford, rb, cvs, fx, nj, levelling, lg, pickleball, specialised, diy, fmr, mailonline, millennials, rsf, yatra, belta, gofundme, serie, thc, wpial, bayelsa, gt, middlesbrough, nlc, upi, crimestoppers, dcu, jey, macos, npp, nrl, sofi, uttar, bolsonaro, bps, csu, ftse, glastonbury, kelowna, litres, mma, nadu, nia, oc, qr, shortlisted, smackdown, wrestlemania, zayn, apr, barangay, bros, ecb, lga, mou, pawar, ryzen, sp, spdr, ulez, vapes, xl, allspring, customization, inverclyde, osimhen, usman, headteacher, illawarra, ips, ssd, tayyip, walsall, bnp, faa, hochul, ppp, sportsbook, stocknews, zac, covestor, diamondbacks, kanye, leyen, lukashenko, rnli, showrunner, suella, utes, esports, hdmi, kwara, priyanka, acl, aws, ceos, hai, mw, oyo, rafah, tds, nft, ozempic, pune, rohit, trc, uconn, umar, underwhelming, vivek, cj, dpp, footballers, iot, kody, lineker, pregame, shonen, cibc, dems, efl, envestnet, evercore, hospitalised, ibrox, ioc, isi, postecoglou, pushback, wnba, creatives, mandalorian, transitioned, chatbots, finalised, frontman, livestream, nagar, penrith, rspca, sf, alibaba, declan, fdic, jj, personalised, psni, recep, tropes, walgreens, analysed, asiwaju, dmitry, exxonmobil, fsb, ftc, gummies, hotspots, nl, rt, rumoured, unitedhealth, wilko, abbvie, juventus, quarterfinal, southend, starlink, timberwolves, kolkata, ncp, okanagan, ramped, alia, bundesliga, davido, hartlepool, holyrood, huawei, jp, kourtney, letby, lionesses, mv, onlyfans, pochettino, shohei, akwa, andhra, cp, defences, eth, jonny, liga, mods, naruto, wagga, boj, cma, gdax, hitmaker, lidl, mk, norges, rivian, tmz, unhoused, vijay, albertans, bsp, dashcam, ig, mga, ml, nyse, swindon, thewill, yakubu, boebert, cif, draftkings, dwp, gw, kohberger, maximise, mna, mysterio, ndc, npc, rd, rubiales, shortlist, wr, ymca, ebonyi, fcf, hibs, ibom, mn, nio, omicron, pics, roadworks, smes, stellantis, winless, adamawa, buffaloes, centred, emefiele, eur, fandom, gta, hmrc, nearfall, opioids, pmi, sustainably, virat, wakanda, wolverines, adebayo, basingstoke, borno, eff, esa, gauteng, lizzo, mbappe, messaged, obasanjo, rj, shazam, siddaramaiah, sq, uaw, unauthorised, brs, ccc, councilmember, hse, jada, lavrov, loltron, rba, rv, sabalenka, zaporizhzhia, bauchi, canaccord, changelly, dropkick, genuity, icu, jaylen, katsina, lenovo, narrabri, pf, pnp, rmt, ufj, afcon, akpabio, bharatiya, ces, chhattisgarh, criticising, dystopian, foodbank, gmb, goku, gpus, inked, inrix, lightsaber, meghalaya, oban, onana, punters, rebranded, runtime, tyneside, utilise, wwii, zamfara, adeleke, boba, bu, characterised, ec, ekiti, foldable, goalless, goulburn, houthi, kaur, kejriwal, matchday, mobilised, nasarawa, oswestry, redshirt, sd, springboks, varadkar, adverts, bulley, caf, cena, cms, deepika, det, dod, emphasising, fortnite, holidaymakers, ivf, kardashians, lt, midfielders, millwall, mkm, nfts, nnpp, oleksandr, psa, rgb, saka, sussexes, tripadvisor, youtuber, atmos, bvas, cnbc, eversource, farage, femi, grogu, kharge, lvii, nollywood, pbs, rsv, signaturefd, tj, usyk, wirral, aquaman, bromsgrove, bytedance, cf, crowdstrike, dps, kharkiv, khloe, kkr, msnbc, naloxone, pd, rajya, shettima, shopify, stormwater, utd, wbc, xander, yarra, dpr, easyjet, emojis, fanduel, gabi, llms, lpl, predeceased, pwc, rhp, scoreline, buttigieg, endeavours, gaa, gershkovich, gst, jmp, merch, ofcom, remix, rhyl, sadiq, smartwatch, ucp, utilised, bts, cricketer, footballing, ict, iga, ir, iss, morrisons, ol, paltrow, quinnipiac, raac, rbc, sahel, scotiabank, undrafted, aed, ak, bafta, elland, empls, ifp, insp, inu, jeddah, ktrk, nyu, ppg, prioritising, rc, retrmt, rnc, shabbat, soc, sys, teesside, yr, aclu, ajit, ats, bpd, crores, cw, cymru, docuseries, ebit, gonzaga, hvac, iit, iplayer, isd, msps, obrador, pathaan, prioritised, quantumania, redditch, sundowns, tailwinds, utilising, vc, webcast, xrp, ardern, atletico, babet, bawumia, bst, duterte, hb, hijab, homered, hyrule, isro, kfsn, pattaya, pg, postpartum, qatari, tsa, yahaya, zahawi, balogun, bezos, cavs, dandenong, defenceman, ds, etihad, fomc, garba, heatwaves, housemates, hq, ipob, ix, jaden, kalu, lawal, lululemon, matildas, mpc, repurposed, sonos, tagovailoa, tmc, ug, unlv, webcam, abiodun, adamu, astana, asuka, conocophillips, cybercrime, cyberpunk, equalised, ganduje, gea, geforce, kirsty, leanne, leeton, ligue, malam, mobilisation, mrna, nassr, ncis, nda, npa, qbs, rx, shehu, shetty, shinde, touchscreen, vii, vw, xr, zelenskiy, abhishek, asx, aukus, belpointe, beshear, borussia, broadcom, bvi, casemiro, coffs, dm, dp, eze, facetime, fubara, ghostface, govt, gpa, hmp, jaishankar, jv, kabc, kanu, lexi, morecambe, nca, omagh, poilievre, practising, psc, ranbir, sh, tfl, uso, alliancebernstein, cqc, crossbody, cs, deadpool, dnipro, dont, dreamlight, fr, gauff, gautam, gehlot, havertz, hdr, hemsworth, manoj, marginalised, noi, pcc, rebranding, roblox, sasuke, sheamus, shoigu, specialises, tn, tsitsipas, tumours, verlander, woolworths, yeoh, accretive, aussies, bachchan, banshees, burna, cardi, cavill, derozan, dijk, garnacho, hm, hoa, ipc, jagdeo, mirae, oceangate, pollinators, proteas, sco, sharad, tx, undead, verticals, vpns, antetokounmpo, artistes, bdc, bridgwater, chromebook, ci, dhoni, fadnavis, fantastical, ffa, igp, makinde, mnangagwa, mustapha, narcan, natixis, ndlea, nis, nnpc, palantir, peloton, quezon, resetting, rss, shiba, soundbar
