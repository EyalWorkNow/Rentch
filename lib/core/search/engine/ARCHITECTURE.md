# Rently Recommendation Engine — Architecture & Research

מנוע המלצות הדירות של העוזר האישי. מחליף את `advanced_matcher.dart` היחיד
בארכיטקטורת **Cascade Hybrid Ranking** מודולרית בת 4 שכבות.

---

## 1. Research — איזה אלגוריתם מתאים כאן?

### מאפייני הבעיה
- **פריטים מובְנים** עם הרבה אטריביוטים (מחיר, חדרים, מיקום, גודל, מאפיינים, מצב).
- **העדפות מפורשות** מהשיחה עם Gemini → `SearchQuery`.
- **אותות התנהגותיים** על כל נכס (`PropertyMarketSignals`: views/likes/saves/skips/contacts/funnel).
- **Cold-start**: למשתמש חדש כמעט אין היסטוריית אינטראקציה.
- **דרישת הסבּרוּת (explainability)**: העוזר חייב להסביר *למה* נכס הומלץ.
- **On-device**: Dart/Flutter, בלי תשתית אימון ML בשרת (בשלב זה).
- **לעולם לא להיתקע (never dead-end)**: תמיד מחזירים את ה-N הטובים ביותר.

### השוואת גישות

| גישה | יתרון | חיסרון | בשימוש |
|------|-------|--------|--------|
| Content-based + cosine | פשוט, cold-start טוב | לינארי, לא לוכד אינטראקציות | חלק |
| **MAUT** (Multi-Attribute Utility Theory) | בסיס תאורטי (von Neumann–Morgenstern), הסברתי מאוד | צריך פונקציות utility מכוילות | ✅ ליבה |
| **TOPSIS** (MCDA) | דירוג לפי קרבה לפתרון אידאלי, יציב | תלוי בקבוצת המועמדים | ✅ ליבה |
| Learning-to-Rank (LambdaMART) | state-of-the-art | דורש labels ואימון offline | חלקי (GBM stumps) |
| Bayesian preference learning | מנהל אי-ודאות, exploration | יקר חישובית | ✅ משקלים |
| Matrix factorization (CF) | חזק כשיש הרבה דאטה | נכשל ב-cold-start | ❌ (אין מספיק דאטה) |

### ההחלטה: **Hybrid Cascade**
שילוב משוקלל ומכויל של ארבעה scorers משלימים (MAUT + TOPSIS + Cosine +
Gradient-Boosted stumps), עם מודל העדפות בייסיאני שלומד online מהתנהגות,
ושכבת re-ranking ל-diversity (MMR) ו-exploration (Thompson sampling).
זה מספק דיוק מתמטי, עמידות ב-cold-start, והסברתיות מלאה.

---

## 2. הארכיטקטורה — 4 חלקים

```
SearchQuery + TenantProfile + List<RentalProperty>
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ PART 1 — Feature Engineering  (feature_engineering.dart) │
│  • MarketContext: התפלגויות מחיר/גודל/חדרים, percentiles  │
│  • HedonicPriceModel: OLS → מחיר צפוי → residual (value)  │
│  • IsraelGeoIndex: תחנות רכבת, מרכזי ערים, חופים, אונ׳    │
│  • ~35 פיצ׳רים מהונדסים לכל נכס → PropertyFeatureVector   │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ PART 2 — Preference Model  (preference_model.dart)       │
│  • AttributeUtility: Gaussian / Sigmoid / Budget / Range │
│  • Bayesian weights: μ,σ² לכל ממד (אי-ודאות)             │
│  • FTRL-Proximal online logistic learner (לומד מ-swipes) │
│  • HardConstraints + deal-breakers (רכים, ניתנים להרפיה) │
│   → UserPreferenceModel                                   │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ PART 3 — Ranking Engine  (ranking_engine.dart)           │
│  • MautScorer: Σ w·u(x) משוקלל + attribution             │
│  • TopsisScorer: קרבה לאידאל/אנטי-אידאל                  │
│  • CosineScorer: דמיון בוקטור מנורמל                      │
│  • GradientBoostedScorer: ensemble של decision stumps    │
│  • CalibratedEnsemble: שילוב + Platt sigmoid calibration  │
│   → List<RankedCandidate>                                 │
└─────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ PART 4 — Orchestration  (recommendation_orchestrator)    │
│  • DiversityReranker: MMR (מונע 10 דירות זהות)           │
│  • ExplorationPolicy: Thompson sampling (אי-ודאות)       │
│  • Explainer: SHAP-like attribution → הסבר בעברית         │
│  • RecommendationEngine.recommend() — API ציבורי         │
│   → List<Recommendation>                                  │
└─────────────────────────────────────────────────────────┘
```

---

## 3. המתמטיקה המרכזית

**Hedonic price (Part 1):** `log(price) = β₀ + β·features + ε`, נפתר ב-OLS
(normal equations, `β = (XᵀX)⁻¹Xᵀy`). ה-residual `ε` = עד כמה הנכס מתומחר
מתחת/מעל השוק → אות "value".

**MAUT (Part 3):** `U(p) = Σ_d w_d · u_d(x_d) / Σ_d w_d`, כאשר `u_d` פונקציית
utility מכוילת לכל ממד ו-`w_d` משקל מ-Part 2.

**TOPSIS (Part 3):** מנרמל מטריצת החלטה (`r_ij = x_ij/√Σx²`), משקלל, מוצא
פתרון אידאלי `A⁺` ואנטי-אידאלי `A⁻`, ומדרג לפי `C_i = d⁻/(d⁺+d⁻)`.

**Wilson lower bound (Part 1):** ביטחון על like-rate עם מעט צפיות — מונע
ניפוח של נכסים עם 1 like מתוך 1 view.

**MMR (Part 4):** `argmax[λ·rel(p) − (1−λ)·max_sim(p, selected)]` — איזון בין
רלוונטיות לגיוון.

**Thompson sampling (Part 4):** דוגם משקל מ-`N(μ_d, σ_d²)` → לפעמים מקדם נכס
עם אי-ודאות גבוהה (exploration), במקום תמיד exploitation.

---

## 4. אינטגרציה ותאימות לאחור
`SmartSearch.rankAdvanced` מאציל ל-`RecommendationEngine`, וממפה
`Recommendation → ScoredProperty`. ה-`advanced_matcher.dart` הישן נשאר
כ-fallback. הבאג של מפתחות `feat_*` (שלא תאמו את ה-catalog) מתוקן ב-Part 1
דרך `canonicalFeatureKey()`.
