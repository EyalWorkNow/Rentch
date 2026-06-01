# 🏢 Rentch - Tinder for Apartment Rentals 💖

[![Flutter](https://img.shields.io/badge/Flutter-v3.13.0+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-v3.1.0+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-blue)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**Rentch** is a revolutionary mobile application that reimagines the apartment rental search as a Tinder-like matching experience. Instead of scrolling through endless static listings, tenants swipe on potential homes, and landlords swipe on qualified applicants. When a double-opt-in match is made, a chat opens up to directly sign the contract!

---

## 📸 App Showcase

<div align="center">
  <img src="Rentch logo.svg" width="600" alt="Rentch Brand Logo" />
</div>

---

## 📖 Detailed System Guide & Explanation (הסבר מפורט)

### 🔄 The Matchmaking Workflow

Rentch operates on a dual-sided marketplace model:
1. **Tenants (Renters)** swipe through a card deck of apartments.
   - **Swipe Right (Like)**: Expresses interest in renting the apartment.
   - **Swipe Left (Pass)**: Skips the property.
   - **Super Like (Star)**: Signals high interest.
2. **Landlords (Owners)** view a dedicated queue of tenants who liked their apartments.
   - **Swipe Right (Approve)**: Confirms the tenant's profile is suitable.
   - **Swipe Left (Reject)**: Passes on the tenant.
3. **The Match (Lease Match)**: When a landlord approves a tenant who liked their apartment, a **Match** is generated. Both parties are notified, and a direct chat conversation is opened.
4. **Deal Closing**: Inside the chat, landlords can send a digital rental contract. Once both parties sign, the deal is successfully closed.

---

### ✨ Core Features & Screens

#### 1. Discovery Deck (`DiscoverScreen`)
- **Swipe Interface**: Powered by `flutter_card_swiper` for a smooth native feel.
- **Dynamic Property Cards**: View photos, price context (above/below average), area matching score, and key features (elevator, parking, balcony).
- **Interactive Mini-Map**: Built with OpenStreetMap (`flutter_map`) to visualize the exact borders of the chosen search polygon.

#### 2. Candidates Queue (`ExploreScreen`)
- Landlords swipe on renters who have liked their listings.
- Review candidate profile cards showing bios, maximum budget, desired number of rooms, move-in window, and verified reviews from previous landlords.

#### 3. Match Hub (`MatchesScreen` & `MessageScreen`)
- View active matches, chat status (Contract Sent, Owner Signed, Tenant Signed).
- Real-time simulated messaging with landlords/tenants.
- Interactive deal flow: landlords send a lease contract directly in the chat, and both parties can sign digitally.

#### 4. Smart Filtering Sheet
- **Search Polygons**: Dynamic ChoiceChips to select specific region polygons (Central Tel Aviv, Gush Dan, Sharon).
- **Advanced Sliders**: Filter by maximum budget and minimum rooms.
- **Tri-State Feature Tags**: Each amenity tag cycles through three priority levels on tap — see the [Matching Algorithm](#-matching-algorithm) section for how each level affects scoring.
- Built-in contrast logic: adapts colors dynamically for high accessibility.

---

---

## 🧠 Matching Algorithm

The Rentch matching engine assigns every property a **compatibility score from 0 to 100**, displayed as the "X% התאמה" badge on each swipe card. The algorithm is a **weighted multi-criteria scoring model** inspired by techniques used in large-scale real-estate recommendation systems (Airbnb search ranking, Zillow preference weighting, and academic hedonic pricing models).

---

### 🏷️ Tri-State Feature Tag System

Before scoring begins, the tenant marks each amenity tag with one of three priority levels by tapping it repeatedly:

| Tap | Color | Label | Effect on Algorithm |
|-----|-------|-------|---------------------|
| Not tapped | Light teal (default) | — | Tag is ignored |
| **1st tap** | 🔵 **Blue** (`#13BEC9`) | Preferred / Nice-to-have | Boosts score proportionally |
| **2nd tap** | 🔴 **Red** (`#FF5A67`) | Deal Breaker / Must-have | Hard gate — property is **excluded entirely** if missing |
| **3rd tap** | Resets to default | — | — |

The red color is intentionally identical to the X/reject button in swipes — it signals the same finality: *"without this, it's a no."*

---

### 📐 Score Breakdown

The total score is the **sum of eight weighted criteria**, each evaluated independently and clamped to its maximum:

```
Score = budget(28) + rooms(14) + location(18) + size(8)
      + timing(8) + preferred_features(12) + deal_breaker_bonus(6) + quality(6)
                                                                    ─────────────
                                                              max = 100 points
```

> **Hard gate rule**: if the property is missing **any red (deal-breaker) tag**, the score is immediately returned as **0** — no further calculation is performed.

---

### 🔍 Criterion Deep-Dive

#### 1. Budget Fit — 28 points

The old algorithm had a hard cliff: full score under budget, half score up to +15%, zero beyond. This creates a jarring discontinuity and misses real-world nuance (a tenant might still love a property that costs 5% more).

The new approach uses a **logistic (sigmoid) decay curve**:

```
ratio = property_price / max_budget

if ratio ≤ 1.0:
    score = 28 + value_bonus         # under budget → full 28 + up to +5 cheapness bonus
    value_bonus = (1 - ratio) × 5   # cheaper = slightly better fit

if ratio > 1.0:
    overage = ratio - 1.0
    decay   = 1 / (1 + e^(overage × 10))   # logistic — steep past 15%
    score   = min(28 × decay × 2, 14)       # max 14 pts when slightly over budget
```

**Behaviour:**
- Exactly at budget → 28 pts
- 10% cheaper than budget → ~33 pts (value bonus)
- 5% over budget → ~10 pts (still scores well)
- 20% over budget → ~2 pts
- 35%+ over budget → ~0 pts

This smooth decay means a 5% budget overshoot doesn't catastrophically drop a great property to the bottom of the stack.

---

#### 2. Rooms Fit — 14 points

```
diff = property_rooms - min_rooms

diff ≥  0.0  →  14 pts  (meets or exceeds requirement)
diff ≥ -0.5  →  14 × (1 + diff × 2)  pts  (e.g. 7 pts at -0.5 rooms)
diff <  -0.5 →   0 pts
```

A ±0.5 room tolerance (e.g. searching for 3 rooms, finding a 2.5-room) gives half score rather than an outright miss. Israeli listings frequently use half-room increments.

---

#### 3. Location Fit — 18 points

The tenant selects a **geographic polygon** (drawn on the map). The algorithm checks whether the property's GPS coordinates fall inside that polygon using a **ray-casting point-in-polygon test**.

```
areaId == 'all_israel'     →  18 pts  (no restriction set)
property inside polygon    →  18 pts
property outside polygon   →   0 pts  (hard boundary)
```

Location carries the second-highest weight because geography is largely non-negotiable in real estate.

---

#### 4. Size Fit — 8 points

The tenant may set a minimum and/or maximum size in m². The scoring is **proportional to how well the property fits the desired range**:

```
property inside [minM2, maxM2]  →  8 pts
property smaller than minM2     →  8 × (1 - deficit/minM2)  pts  (linear deficit)
property larger than maxM2      →  4 pts  (size grace — bigger is usually acceptable)
no size preference set          →  8 pts
```

Oversized properties (larger than the maximum) receive a grace score of 4 because tenants rarely reject a property purely for being larger than expected.

---

#### 5. Move-in Timing — 8 points

```
MoveInFilter.any           →  8 pts  (no timing requirement)
MoveInFilter.immediate     →  entry date ≤ today   ? 8 : 0
MoveInFilter.within30Days  →  entry date ≤ +30d    ? 8 : 0
MoveInFilter.within90Days  →  entry date ≤ +90d    ? 8 : 0
```

Timing is binary — either the property can be entered in time or it cannot.

---

#### 6. Preferred Features (Blue Tags) — 12 points

Blue tags represent amenities the tenant *would like* but can live without. Scoring uses a **concave reward function** that values partial matches:

```
matched = count of blue tags present in property features
ratio   = matched / total_blue_tags

f(ratio) = 1 − (1 − ratio)^1.5       # concave — partial credit valued
score    = 12 × f(ratio)
```

**Concave vs. linear reward:**

| Blue Tags Matched | Linear | Concave (ours) |
|---|---|---|
| 0 / 4 (0%) | 0 pts | 0 pts |
| 1 / 4 (25%) | 3 pts | **4.5 pts** |
| 2 / 4 (50%) | 6 pts | **7.8 pts** |
| 3 / 4 (75%) | 9 pts | **10.4 pts** |
| 4 / 4 (100%) | 12 pts | 12 pts |

The concave shape means a property matching 2 out of 3 blue tags is surfaced significantly above one that matches 0 — partial compatibility is meaningful, not binary.

If the tenant has set **no blue tags**, they receive the full 12 points (preference-neutral).

---

#### 7. Deal-Breaker Bonus (Red Tags) — 6 points

Red (deal-breaker) tags are already enforced as a **hard gate** (any missing red tag → score 0). Properties that *survive* the gate receive an additional bonus:

```
deal-breakers set and all present  →  6 pts  (bonus for being a strong match)
no deal-breakers set               →  3 pts  (neutral — no hard requirements)
```

This bonus differentiates two properties that both passed the hard gate — the one that fulfils more requirements is surfaced higher.

---

#### 8. Listing Quality — 6 points

Rewards well-maintained, information-rich listings:

```
has media (photos/video)  →  +4 pts
full address present      →  +4 pts   (but capped at quality subtotal)
owner name present        →  +2 pts
                                ──
                         max  = 6 pts
```

A property with photos and a complete address scores full quality points; a listing with no media and no owner name receives 0.

---

### 📊 Worked Example

**Tenant preferences:**
- Budget: ₪6,000/mo  |  Rooms: 3  |  Area: Tel Aviv Centre
- Blue tags: `מרפסת`, `מעלית`
- Red tags: `חניה` (deal breaker)

**Property A — ₪5,800, 3 rooms, Tel Aviv, has: `חניה`, `מרפסת`, `מעלית`, photos**

| Criterion | Calculation | Score |
|---|---|---|
| Budget | ratio=0.967, under budget + value bonus | **29** |
| Rooms | diff=0, meets requirement | **14** |
| Location | inside Tel Aviv polygon | **18** |
| Size | no preference | **8** |
| Timing | any | **8** |
| Preferred (blue) | 2/2 matched → f(1.0)=1.0 → 12×1.0 | **12** |
| Deal-breaker bonus | `חניה` present, gate passed | **6** |
| Quality | has media + address | **6** |
| **Total** | | **✅ 101 → clamped to 100** |

**Property B — ₪6,400, 3 rooms, Tel Aviv, has: `מרפסת` only (no `חניה`)**

| Criterion | Calculation | Score |
|---|---|---|
| Red gate | `חניה` missing → immediate 0 | **🚫 0** |

**Property C — ₪6,300, 3 rooms, Tel Aviv, has: `חניה`, `מעלית` (no `מרפסת`)**

| Criterion | Calculation | Score |
|---|---|---|
| Budget | ratio=1.05, over budget → decay | **~11** |
| Rooms | 14 | **14** |
| Location | 18 | **18** |
| Size | 8 | **8** |
| Timing | 8 | **8** |
| Preferred (blue) | 1/2 matched → f(0.5)≈0.65 → 12×0.65 | **~8** |
| Deal-breaker bonus | `חניה` present | **6** |
| Quality | has photos | **6** |
| **Total** | | **~79** |

Property A (100%) ranks above Property C (79%). Property B is excluded entirely.

---

### 🔄 Algorithm Flow Summary

```
START
  │
  ▼
Red tag gate: any deal-breaker missing?
  ├─ YES → return score = 0  (property excluded from deck)
  └─ NO  → continue
           │
           ▼
       Calculate 8 criteria in parallel:
       ┌──────────────────────────────────────────────┐
       │  1. Budget sigmoid        (0–28 pts)          │
       │  2. Rooms linear          (0–14 pts)          │
       │  3. Location polygon      (0–18 pts)          │
       │  4. Size proportional     (0–8  pts)          │
       │  5. Timing binary         (0–8  pts)          │
       │  6. Blue tags concave     (0–12 pts)          │
       │  7. Red tag bonus         (3–6  pts)          │
       │  8. Listing quality       (0–6  pts)          │
       └──────────────────────────────────────────────┘
           │
           ▼
       Sum all criteria → clamp(0, 100)
           │
           ▼
       Return final score → displayed as "X% התאמה"
END
```

---

## 🛠️ Tech Stack & Architecture

### Frontend Architecture
The project follows a **Feature-First / Clean Architecture** folder structure:
* `lib/core/`: Contains constants, shared utilities, themes, and global styles.
* `lib/data/`: Data models (JSON parsing, serialization) and state providers.
* `lib/presentation/`: UI feature folders, screens, and shared widgets.

### State Management & Persistence
* **Provider**: Utilizes `DatingProvider` for unidirectional data flow and state management.
* **Local Storage**: Persists swipes, matches, chat messages, and search settings across sessions using `shared_preferences`.
* **Mock Data Generator**: Generates realistic listings, reviews, and chat dialogs locally via `RentalDataService`.

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (`v3.13.0+`)
* Dart SDK (`v3.1.0+`)
* Xcode (for iOS simulator) / Android Studio (for Android emulator)

### Setup & Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/EyalWorkNow/Rentch.git
   cd Rentch
   ```
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run on a simulator or physical device:
   ```bash
   flutter run
   ```

## 🚢 Production

Production-only integrations are disabled by default and must be enabled with
`--dart-define` flags. See [docs/PRODUCTION_READINESS.md](docs/PRODUCTION_READINESS.md)
for the release checklist, Firebase/Appwrite configuration, and verification
commands.

---

## 🎨 Asset Configuration

### App Icon Customization
The application uses the custom vector brand logo `Rentch logo.svg`. A square, centered version [app_icon_square.svg](assets/images/app_icon_square.svg) has been created to generate launcher icons for both iOS and Android.

To refresh the app icons on the simulator:
1. Delete the existing app from the device/simulator.
2. Re-run `flutter run` to recompile the asset catalog with the new icons.

---

## 📜 License
This project is licensed under the MIT License - see the LICENSE file for details.
