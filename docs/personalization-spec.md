# THE MASTER PERSONALIZATION SPEC — Rently Search
### מפרט בנייה, לא מסמך חזון. מעוגן בקוד האמיתי שלנו.

> **הערת עיגון קריטית (קראו קודם):** הסקורר הפרוס בפועל ב־`aws/lambda/router/index.mjs` הוא `RANK_WEIGHTS = { freshness:0.30, popularity:0.30, completeness:0.20, priceFit:0.20 }` — **ארבע** פיצ'רים בלבד. תשע הפיצ'רים ("tag_overlap, semantic_sim, neighborhood_fit…") הם מודל־היעד, לא הקוד. `semanticSim` כבר מחושב אבל רק במסלול ה־kNN (`index.mjs:1581`), ו־`neighborhoodScore` (`lib/neighborhood.mjs`) כבר מחשב תת־ציונים אבל **התוצאה לא מוזרקת ל־`rankScore`**. משקלי השכונה `W={safety:0.30,walkability:0.25,schools:0.20,transit:0.15,green:0.10}` (neighborhood.mjs:271) **קשיחים וחסרי מודעות־קוהורט**. `profileCohort()` (index.mjs:3560) כבר מחזיר `family|single|student|couple|null`. כל הספק מתוכנן סביב העובדות האלה — הזול־ביותר־קודם.

---

## 1. רשת קוהורטים מעודכנת (Cohort Taxonomy)

היום: `{student, family, default}` (+ `single`/`couple` שכבר ב־`profileCohort` אך לא מנוצלים). זה מכסה 3 מתוך 10. הרשת החדשה — **11 קוהורטים** (10 + default), נגזרים מ־vibe chip **בשילוב** שדות פרופיל חדשים וסיגנלים מטקסט חופשי, לא מ־chip לבד.

| קוד | שם קוהורט | טריגרים (סדר קדימות) | פרסונה |
|---|---|---|---|
| **YPS** | `young_professional_solo` | household=single + vibe=תוסס + עיר=מרכז ת"א + `isSolo=true` (גייט אנטי־שותפים) | נועה שני |
| **NPAR** | `new_parents` | household=couple + `expecting=true`/hasChildren&childAge<2 + vibe=משפחתי | נועה ותומר |
| **RELF** | `religious_family` | household=family + `sector=jewish-religious` (מ־chip משפחתי + טקסט ממ"ד/עירוב/בית כנסת/דתי לאומי) + ≥4 ילדים | שירה בן־שבת |
| **STUD** | `student_shared` | vibe=סטודנטיאלי + `listingType=room`/שותפות + עיר־אוניברסיטה | אליאור אמסלם |
| **OLEH** | `oleh_anglo` | household=family + `isOleh=true`/`langPref=en` + sector=jewish-religious | דניאל גרין |
| **SENI** | `senior_aging_in_place` | household=couple + vibe=שקט + `age≥65`/`accessibilityNeed=true` + ¬hasChildren | יוסי ונורית |
| **SPAR** | `single_parent_carfree` | household=family/single + hasChildren + `carFree=true` (היברид family×student) | שירן לוי |
| **REMO** | `remote_professional` | household=single + wfh=true + vibe∈{שקט,תוסס} + עיר־פריפריה | נועה בר־און |
| **ARAB** | `arab_town_family` | household=family + `sector=arab` (מ־whitelist יישובים ערביים) | מנאר זועבי |
| **INVE** | `investor` | `intent=investment` (דגל כוונה, **לא** vibe chip) → מפעיל מצב buy-to-let | דודו פרץ |
| **DEF** | `default` | fallback כשאין אות | — |

**עיקרון מבני:** הקוהורט נקבע ב־2 שלבים — (א) `intent` (מגורים/השקעה) חוצה־הכל; (ב) בתוך מגורים, מפתח מורכב `{household, sector, lifeStage, mobility}`. ה־vibe chip הופך מ־*מקור* קוהורט ל*סיגנל אחד מני רבים*. חובה להרחיב את `PROFILE_WRITABLE_FIELDS` (index.mjs:3548) — ראו סעיף 7.

---

## 2. מטריצת משקלים (Cohort × Feature)

יחסית ל־default של מודל־היעד: `tag_overlap.30 · price_fit.25 · semantic_sim.20 · popularity_prior.15 · neighborhood_fit.15 · recency.12 · distance_decay.10 · vibe_fit.10 · explore.08`. ↑=העלה, ↓=הורד, =שמור, ✕≈אפס. עמודת **price anchor** קריטית: ה־priceFit הנוכחי מתגמל את *אמצע* הטווח — שגוי כמעט לכולם.

| Cohort | tag_overlap | price_fit | anchor | semantic | neigh_fit | vibe | distance | popularity | explore | recency |
|---|---|---|---|---|---|---|---|---|---|---|
| **YPS** | ↑ | ↓ | **top⅓** | ↑↑ | ↑↑ | ↑ (תוסס) | ↑ (dual origin) | ↓ | ↓ | ↑ |
| **NPAR** | ↑ | ↑ | **lower½** | ↑ | ↑ | ↑ (משפחתי+שאר תוסס) | ↑ (סבתא) | ↓ | ↓ | ↑ |
| **RELF** | ↑↑ | ↑ | **priceMin** | ↑↑ | ↑↑ | ↑ | ↑ (בית כנסת) | ↓ | ↓ | ↓ |
| **STUD** | = | ↑ | **one-sided low** | ↑ | ↑ | = (שקט־סטודנט) | ↑↑ (שער אוני') | ↓ | = | ↑ |
| **OLEH** | ↑ | ↓ | **top ok** | ↑↑ | ↑↑ | ↑ | ↑ | ↓ | ↓ | ↑ |
| **SENI** | ↑↑ (מרפסת) | ↓ | **at/under-max** | ↑ | ↑ | ↑↑ (שקט) | ↑ (מרפאה+נכדים) | ↓↓ (אנטי) | ↓ | ↓ |
| **SPAR** | = | ↑ | **low end** | ↑ | ↑↑ | = | ↑↑ (משולש) | ↓ | ↓ | = |
| **REMO** | ↑ | ↑ | **lower⅓** | ↑↑ | ↑ | ↑ (שקט־אך־חי) | ↑ | ↓ | ↑ | = |
| **ARAB** | ↑↑ | ↓ | **top ok** | ↑ | ↑↑ | = | ↑ (עוגן משפחה) | ↓ | ↓ | = |
| **INVE** | ↓ | ↓ | **INVERT** (נמוך=טוב) | ↑↑ | ↑↑ | ✕ | ↑ (עוגן שוכרים) | = (="ביקוש") | ↑ | ↑ |

**נימוקים קצרים על החריגים:**
- **price_fit הוא הבאג המערכתי #1.** ל־6 קוהורטים (NPAR/RELF/STUD/SPAR/REMO) "אמצע התקציב" מקדם דירות שלא יעמדו בהן; ל־3 (YPS/OLEH/ARAB) הוא *מעניש* את הדירה היוקרתית שהם דווקא רוצים; ל־INVE הוא הפוך לגמרי. הפתרון: `priceTarget ∈ {low, mid, high, invert}` פר־קוהורט (סעיף 7).
- **popularity_prior הוא אנטי־סיגנל ל־SENI** (דירה "חמה" = בניין תחלופה/סטודנטים — בדיוק הפחד), ו**סיגנל אמיתי ל־INVE** (עדר = ביקוש/rentability) — לתייג ב־UI כ"ביקוש", לא "פופולרי".
- **semantic_sim = הדלֶתָה החינמית הגדולה ביותר** (כבר מחושב, index.mjs:1581). כמעט כל פרסונה נשענת על טקסט חופשי עשיר. הפעילו את הדגל פר־קוהורט לפני כל שאר ה"הרמות".
- **explore הפוך בין REMO/INVE** (↑ — "לגלות ג'ם לפני העדר") ל־SENI/OLEH/RELF (↓ — יריבי סיכון שרוצים מוכָּח).

---

## 3. מטריצת משקלי־שכונה (neighborhood sub-scores)

מחליף את ה־`W` הקשיח ב־neighborhood.mjs:271 בטבלה פר־קוהורט. ערכים 0–1 (ינורמלו בתוך `neighborhoodScore` בדיוק כמו הרנורמליזציה הקיימת על מקורות חסרים). ⚠️ = מטעה עד שנוסיף תת־ציון חדש (סעיף 5).

| Cohort | safety | schools | transit | walkability | green | תת־ציונים חדשים שחייבים |
|---|---|---|---|---|---|---|
| **YPS** | 0.7 (לילה) | 0.0 | 0.9 | 1.0 | 0.2 | rail/LRT type, demographic (25-34) |
| **NPAR** | 0.35 | 0.10 | 0.15 | 0.25 | 0.15 | gan/מעון, ממ"ד/מקלט, road-noise, clinic |
| **RELF** | 0.30 | 0.35 ⚠️ | 0.05 | 0.20 | 0.10 | school **פיקוח**, עירוב, בית כנסת, מקווה |
| **STUD** | 0.30 (לילה) | 0.02 | 0.28 | 0.32 | 0.08 | GTFS walk/transfer, all-in-arnona |
| **OLEH** | 0.95 | 0.85 ⚠️ | 0.25 | 0.80 | 0.50 | בית כנסת, Anglo-density, olim-track |
| **SENI** | 0.90 | 0.05 | 0.25 | 0.95 | 0.70 | clinic/בית מרקחת, age-mix %65+, road-noise |
| **SPAR** | 0.85 | 0.70 | 1.0 ⚠️ | 0.95 | 0.35 | Metronit direct-ride, gan, single-parent density |
| **REMO** | 0.15 | 0.0 | 0.15 | 0.40 | 0.30 | café-density split, fiber, socio "upgrade" index |
| **ARAB** | 0.45 ⚠️ | 0.90 ⚠️ | 0.15 | 0.85 | 0.30 | **sector** school, מסגד, socio decoupled |
| **INVE** | 0.40 | 0.20 | 1.0 ⚠️ | 0.55 | 0.10 | **future** transit, employment-gravity, yield |

**שתי מלכודות שהמנגנון הנוכחי חייב לתקן:**
1. **ARAB — לנתק את ה־socio-economic cluster מ־safety.** ב־neighborhood.mjs:218 אשכול נמוך → safety נמוך. יישובים ערביים שהיא *בוחרת* יקבלו עונש שיטתי. צריך cohort flag `decoupleSocioFromSafety=true`.
2. **SENI — schools≈0 ומנותק מ־walkability.** היום גנים מקופלים ל־walkability ובית ספר = חיובי; אצלה "ליד בית ספר" = deal-breaker רעש. צריך פיצול gan מ־walkability.

---

## 4. שערי Deal-breaker (hard-exclusion) פר־קוהורט

מיושמים אחרי ה־hard-filter הקיים (עיר/מחיר/חדרים/amenities), לפני הסקורר. 🔒=אכיף היום, ⛔=חסום עד סיגנל חדש (סעיף 5).

- **YPS:** 🔒 ¬קומת קרקע/גן · ⛔ קומה≥4 בלי מעלית (חסר floor) · ⛔ שותפים/מחיצה (`isSolo`) · ⛔ אין ממ"ד+מקלט · 🔒 keyword רטיבות/מוזנח.
- **NPAR:** ⛔ קומה≥4 בלי מעלית · ⛔ על ציר ראשי (חסר road-class) · 🔒 keyword עובש · ⛔ אין ממ"ד/מקלט · ⛔ חוזה<12ח או סעיף מכירה · ⛔ צמוד פאב · 🔒 no-pets (צריך cat-granularity).
- **RELF:** 🔒 מעל 6800 (תקרה קשה) · 🔒 חדרים<5 · ⛔ אין ממ"ד · ⛔ חוזה<12ח · ⛔ קומה≥3 בלי מעלית+ללא מחסן · ⛔ אין נתיב בי"ס ממ"ד (חסר פיקוח) · ⛔ אין עירוב.
- **STUD:** ⛔ all-in>1600 (חסר arnona) · ⛔ דרוש ערב/פיקדון גדול · ⛔ 12ח נעול בלי סבלט · ⛔ לא הליך/רכב ל־BGU · 🔒 safety<סף לילה · ⛔ עובש/בלי דוד/בלי חלון.
- **OLEH:** 🔒 חדרים<4 · 🔒 אין ממ"ד · 🔒 אין חניה · ⛔ קומה גבוהה בלי מעלית · ⛔ חוזה רב־שנתי בלי break · ⛔ בעלים לא דובר אנגלית (**soft gate = דירוג־למטה**, לא drop — למנוע תוצאות ריקות) · ⛔ key-money.
- **SENI:** ⛔ בלי מעלית · ⛔ קומה≥4 גם עם מעלית · 🔒 קומת קרקע פונה־רחוב = **שלילי** (הופך את היוריסטיקת הנגישות!) · ⛔ כניסה עם מדרגות · ⛔ ציר ראשי/מול בי"ס/פאב · ⛔ אין ממ"ד · 🔒 hasPets גייט חתול.
- **SPAR:** ⛔ קומה≥3 בלי מעלית · ⛔ מעל 600מ מ־Metronit + אין קו ישיר · ⛔ "בלי ילדים" (+דגל fair-housing) · ⛔ ערבות בנקאית/3ח · ⛔ חוזה<12ח · 🔒 עובש (ילד אסתמטי) · ⛔ קומת קרקע לא־מאובטחת.
- **REMO:** 🔒 no-pets (כלב) · ⛔ בלי חדר עבודה סגור (open-plan / חדרים<3.5) · ⛔ אין fiber · ⛔ ציר ראשי/מעל פאב · 🔒 עובש/קרקע חשוך · ⛔ חוזה<12ח/בעלים בבניין · ⛔ אפס בתי קפה ב־1ק"מ.
- **ARAB:** ⛔ יישוב יהודי/מעורב (חסר sector flag) · ⛔ אין כניסה פרטית/מדרגות משותפות · ⛔ תוספת גג לא־חוקית · ⛔ קומה עליונה בלי מעלית · 🔒 אפס חניה.
- **INVE:** ⛔ ת"א/תשואה<3.5% · ⛔ בניין לשימור/אפס התחדשות · ⛔ קרקע/קומה־גבוהה־בלי־מעלית (נזילות יציאה) · ⛔ תזרים שלילי · ⛔ יישוב מתכווץ · ⛔ פרמיית lifestyle מעל ממוצע מ"ר.

**דפוס חוזר:** רוב ה־⛔ תלויים ב־**5 סיגנלים חסרים** (floor/elevator, ממ"ד/מקלט, lease-terms, road-class, sector) — לכן סעיף 5 הוא נעל־המנעול.

---

## 5. הפערים הקריטיים בדאטה — האיחוד, מתועדף ⭐ (הסעיף החשוב ביותר)

דירוג לפי **(מס' פרסונות × 1/מאמץ)**. כל שורה: מקור ציבורי ישראלי קונקרטי + נקודת החיבור בקוד.

### דרג A — זול + מכסה הכי הרבה (עשו קודם)

| # | סיגנל | פרסונות | מקור נתונים | חיבור לקוד |
|---|---|---|---|---|
| **A1** | **גרנולריות אזור־סטטיסטי** (במקום locality-name) | 8 (YPS,NPAR,RELF,STUD,SENI,SPAR,ARAB,OLEH) | למ"ס אזורים סטטיסטיים + **muni_ids `cbs_id`** שכבר קיים (muni.mjs:53 `resolveLocality`) | תשתית־על. מפתח־ג'וין דק ל־A2/A3/A5. הרחיבו `buildLocalityMap` (neighborhood.mjs:181) ל־key אזור־סטטיסטי. |
| **A2** | **פשע per-capita** (במקום absolute) | 8 | RES_CRIME שכבר נמשך (neighborhood.mjs:223) ÷ אוכלוסיית למ"ס | תקנו את ה־TODO ב־`crimeCountToSafety` (neighborhood.mjs:198). חלוקה אחת. |
| **A3** | **floor + elevator + private-entrance** (שדות מובנים) | 7 (YPS,NPAR,RELF,OLEH,SENI,SPAR,ARAB) | אין מקור ציבורי — schema פנימי + NLP על התיאור; validate מול היתרי בנייה | שדה listing חדש. פותח ~15 שערי ⛔. **ה־ROI הכי גבוה.** |
| **A4** | **school פיקוח/מגזר/שפה** | 3 החלטיים (RELF,OLEH,ARAB) | **RES_SCHOOLS כבר נמשך** (neighborhood.mjs:25) — הדאטהסט **כבר נושא** עמודת פיקוח שאנחנו זורקים | ב־`schoolsScore` (neighborhood.mjs:135) שמרו `pikuah`/`sector`/`language`; סננו/שקללו. כמעט חינם. |
| **A5** | **גן/מעון בנפרד** מ־walkability | 5 (NPAR,RELF,OLEH,SPAR,ARAB) | אותו RES education, מסונן ל`גני ילדים` | תת־ציון `kindergarten` חדש, distance-decay כמו schools. |
| **A6** | **POI דת** (בית כנסת+nusach / מסגד / מקווה) מ־walkability | 4 (RELF,OLEH,SENI,ARAB) | ה־Overpass שכבר רץ (neighborhood.mjs:91) + `amenity=place_of_worship[religion]` + משרד הדתות | הוסיפו bucket ל־`osmCounts`. תת־ציון `worship`. |
| **A7** | **דגל sector יישוב** (ערבי/יהודי/מעורב) | 1 קשיח (ARAB) | למ"ס "רשימת יישובים ואוכלוסייתם" data.gov.il, ג'וין ב־cbs_id | boolean פר locality. גייט קשיח + ניתוק socio. |

### דרג B — מאמץ בינוני, כיסוי רחב

| # | סיגנל | פרסונות | מקור | חיבור |
|---|---|---|---|---|
| **B1** | **all-in cost (arnona+vaad)** | 5 (STUD,OLEH,SPAR,NPAR,INVE) | צווי ארנונה עירוניים ₪/מ"ר לפי אזור + data.gov.il; vaad=שדה listing | מודֵל price_fit על all-in, לא sticker. |
| **B2** | **ממ"ד + מקלט ציבורי (GIS)** | 5 (YPS,NPAR,RELF,OLEH,SENI) | פיקוד העורף oref.org.il + GIS עירוני | תת־ציון shelter + explainability "ממ"ד+מקלט ב־Xמ'". |
| **B3** | **lease terms + landlord flags** (מינ' תקופה/סבלט/break/no-sale/ילדים/אנגלית/pet-species/ערב) | 8 | אין מקור — schema landlord/listing פנימי | מזין רוב שערי ⛔ הרכים. UX intake לבעלים. |
| **B4** | **composition דמוגרפי** (גיל/משק בית/olim/דתיות/single-parent) | 7 | למ"ס אזור־סטטיסטי + ועדת בחירות קלפי (דתי־לאומי proxy) + Nefesh B'Nefesh | תת־ציון `demographic` בתוך neighborhood_fit. **לעולם לא כפילטר/הסבר גלוי.** |
| **B5** | **clinic/קופ"ח/טיפת חלב** | 4 (NPAR,SENI,OLEH,SPAR) | משרד הבריאות מרשם מוסדות + OSM | תת־ציון `health`. |
| **B6** | **road-hierarchy + רעש** | 3 (NPAR,SENI,REMO) | OSM `highway=primary/trunk` (כבר נמשך OSM!) + מפות רעש המשרד להגנ"ס | feature "מרחק מציר מסווג". |
| **B7** | **parking reality** (count/מקורה/שמור) | 4 | שדה listing + GIS חניה עירוני | להחליף boolean ב־count. |

### דרג C — יקר/נישתי (דחו או מודל נפרד)

| # | סיגנל | פרסונות | מקור |
|---|---|---|---|
| **C1** | **transit type + GTFS pedestrian/transfer** (LRT/רכבת נפרד, isochrone) | 5 (YPS,NPAR,STUD,SPAR,INVE) | GTFS ארצי gtfs.mot.gov.il + נת"ע/דנקל geometry + OSRM foot |
| **C2** | **fiber + כיסוי סלולרי** | 1-2 (REMO) | משרד התקשורת מפת פריסת סיבים + מפות כיסוי |
| **C3** | **חבילת INVE** (מצב purchase-price, yield נטו, התחדשות תמ"א/פינוי, future-transit, employment-gravity, exit-liquidity, מוכר לחוץ) | 1 (INVE) | נדל"ן: nadlan.gov.il · רשות התחדשות עירונית · נת"ע planned · הוצל"פ/כונס |
| **C4** | **socio "upgrade" index + creative-scene** | 1 (REMO) | למ"ס מדד חברתי־כלכלי (ג'וין cbs_id) + עוסקים־מורשים density |

**המלצה חדה:** דרג A (A1–A7) הוא ~שבועיים עבודה, נשען כמעט כולו על נתונים ש**כבר נמשכים** (RES_SCHOOLS, RES_CRIME, Overpass, muni_ids), ופותח את רוב השערים ל־8 מ־10 הפרסונות. INVE (C3) הוא מוצר נפרד — אל תזהמו בו את סקורר המגורים.

---

## 6. הדקויות ל"פרסונליזציה מושלמת" (חוצה־קוהורט)

1. **גמישות תקציב אינה סימטרית — אף פעם.** ה־`priceFitScore` הנוכחי מניח פעמון סביב האמצע. החליפו ל־`priceTarget` פר־קוהורט: `low` (STUD/SPAR/RELF/REMO/NPAR — חד־צדדי, זול=טוב), `high` (YPS/OLEH/ARAB — שליש עליון), `invert` (INVE — ₪/מ"ר מתחת לחציון). ל־YPS/RELF דירה "זולה מדי" במיקום מרכזי = חשד (מחיצה/קרקע), לא מציאה.
2. **למידת משקלים מ־swipes (index.mjs:172 כבר לוגג feature-vector + outcome).** התחילו bandit קל: per-cohort logistic על ה־4 פיצ'רים החיים, מעדכן משקלים ב־nightly batch. אל תקפצו ל־LightGBM עד שיש נפח לוגים לקוהורט. cold-start: ירש משקלי־ברירת־מחדל של הקוהורט מהמטריצה בסעיף 2.
3. **מתי לסמוך על הפרופיל מול השאילתה:** השאילתה **גוברת** על searchProfile כשהיא ספציפית (עיר/מחיר/חדרים מפורשים) — היא כוונת־הרגע. הפרופיל ממלא **חוסרים** ומזין vibe/sector/carFree שהמשתמש לא מקליד. חריג: גייטים חברתיים (sector, religiosity) — תמיד מהפרופיל/טקסט, לעולם לא מוצגים כסיבה גלויה.
4. **דו־קידוד:** "קומה גבוהה" (YPS) = גם אור וגם בטיחות; "קומה נמוכה" (SENI/RELF/SPAR) = נגישות. אותו פיצ'ר, סימן הפוך פר־קוהורט — לכן floor חייב scorer פר־band, לא amenity boolean.
5. **פרדוקס שקט⇄תוסס בשני מוקדים** (REMO, NPAR): ה**יחידה** חייבת לצבור שקט (¬ציר/¬nightlife ב־100מ), ה**אזור** חייב חיים (café ב־800מ). לעולם לא לספק אחד ע"ח השני — שני תת־ציונים נפרדים.
6. **multi-origin distance_decay:** 5 פרסונות צריכות ≥2 מוקדים עם משמעויות שונות (YPS: רק"ל+רכבת; NPAR/SENI: מרפאה+סבתא; SPAR: משולש gan→בי"ס→עבודה→ק.אתא). אל תמצעו — אובדן מוקד אחד לא צריך להתבטל בממוצע. השתמשו ב־max/soft-OR, לא avg.
7. **popularity כאות דו־פני:** אנטי־סיגנל ל־SENI/ARAB/REMO (תחלופה/עדר = בדיוק מה שהם בורחים ממנו), אות אמיתי ל־INVE (ביקוש). המשקל תלוי־קוהורט, לא גלובלי.
8. **explainability מרגיע:** ל־OLEH/STUD (פחד freier) — פרטו "בלי ערב · סבלט מותר · מחיר הוגן מול שוק". ל־SENI/RELF — "ממ"ד+מקלט ב־Xמ' · חוזה ארוך". הציון לבדו לא מספיק; הצדקה = מוצר.
9. **cold-start פר־פרסונה:** high-intent decisive (YPS/OLEH/INVE) → הורידו explore, תנו את הטוב. discovery-seekers (REMO/INVE) → העלו explore. deadline-driven (NPAR/OLEH/STUD) → העלו recency + סננו לזמינות בחלון.
10. **גייטים חברתיים = internal-only.** sector, religiosity-band, "avoiding discrimination", single-mom density, "temporary lease" — נכנסים לדירוג פנימית, יוצאים ב־UI כ"קרוב למשפחה / מתאים למשפחתך". חשיפתם = פוגעני ומרתיע.

---

## 7. תוכנית יישום מדורגת (זול־ביותר־קודם, קשור לקוד)

**שלב 0 — חיווט מה שכבר קיים (ימים, לא שבועות):**
- הזריקו את `neighborhoodScore().score` ל־`rankScore` ב־`attachRankSignals` (index.mjs:1343) — היום מחושב ולא בשימוש. משקל התחלתי 0.15.
- הפעילו את `semanticSim` (index.mjs:1581) בתוך הסקורר הראשי, מאחורי דגל פר־קוהורט.

**שלב 1 — משקלים פר־קוהורט (שינוי טהור בקוד, אפס דאטה):**
- הפכו את `RANK_WEIGHTS` הקבוע (index.mjs:1334) ל־`RANK_WEIGHTS_BY_COHORT` (מפה מסעיף 2), נבחר ע"י `profileCohort()`.
- הפכו את `W` הקשיח (neighborhood.mjs:271) לפרמטר: `neighborhoodScore({lat,lng,locality,cohort})` → בוחר טבלת sub-weights מסעיף 3. הרנורמליזציה הקיימת (neighborhood.mjs:285) כבר תומכת בזה.
- הוסיפו `priceTarget` פר־קוהורט ל־`priceFitScore` (low/mid/high/invert).

**שלב 2 — הרחבת קוהורטים + פרופיל:**
- הרחיבו `PROFILE_WRITABLE_FIELDS` (index.mjs:3548): `sector, isReligious, isOleh, langPref, age/lifeStage, carFree, isInvestor, expecting, familyAnchors[], leaseFlex`.
- הרחיבו `profileCohort()` (index.mjs:3560) למפתח מורכב + intent (סעיף 1).

**שלב 3 — דרג A דאטה (נשען על מקורות שכבר נמשכים):**
- A4: הפסיקו לזרוק את `pikuah` ב־`schoolsScore` (neighborhood.mjs:135).
- A2: per-capita ב־`crimeCountToSafety` (neighborhood.mjs:198, ה־TODO כבר שם).
- A5/A6: buckets חדשים ב־`osmCounts` (neighborhood.mjs:87) — gan, worship.
- A1: מפתח אזור־סטטיסטי ב־`buildLocalityMap` (neighborhood.mjs:181) דרך muni_ids.
- A3/A7: שדות listing חדשים (floor, elevator, privateEntrance, localitySector) + גייטים.

**שלב 4 — דרג B (בינוני):** arnona all-in, ממ"ד/מקלט GIS, lease/landlord fields, demographic sub-score.

**שלב 5 — נפרד:** GTFS/transit-type (C1), חבילת INVE כ־mode נפרד (C3) — אל תערבבו עם סקורר המגורים.

**כלל ברזל:** כל שלב חייב שלא לשבור fail-soft — הרנורמליזציה של neighborhood.mjs והתפיסה "מקור חסר ≠ שכונה גרועה" הם עמוד השדרה; כל תת־ציון חדש חייב לצאת `null` על כשל ולהירנרמל, לא להתאפס.

**קבצים לגעת בהם:** `aws/lambda/router/index.mjs` (סקורר, קוהורט, פרופיל), `aws/lambda/router/lib/neighborhood.mjs` (sub-weights, תת־ציונים חדשים, per-capita), `aws/lambda/router/lib/muni.mjs` (אזור־סטטיסטי join), schema ה־listings (floor/elevator/sector/lease/pet-species).