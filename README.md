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

## 🧠 Production Matching Engine

Rentch now uses a two-stage recommendation engine instead of a simple filter-and-sort list. Every candidate property receives a deterministic **compatibility score from 0 to 100**, shown on swipe cards as `"X% התאמה"`. The model is intentionally explainable: every point comes from a product decision that protects tenant trust, landlord lead quality, and marketplace liquidity.

The engine lives in `DatingProvider`:

- `filteredProperties` builds the candidate deck.
- `matchScore(property)` computes the score used by the card badge.
- `priceContext(property)` uses the same market baseline as the ranker, so "above/below average" labels are consistent with ranking.
- `SearchFilters.toJson/fromJson` remains the persistence boundary; no saved-state migration is required for this algorithm upgrade.

---

### 1. Candidate Eligibility: Hard Gates vs Soft Preferences

The first stage separates **true deal-breakers** from **rankable preferences**. This matters because a rental marketplace should not hide a great apartment just because it is 4% over budget, but it also must never show a property missing a must-have such as parking if the tenant marked parking as red.

#### Always-hard gates

These remove a property before scoring:

| Gate | Reason |
|---|---|
| Already liked/passed | Do not recycle cards the user has already acted on |
| Text query mismatch | Explicit search intent |
| City mismatch | City is treated as an explicit location commitment |
| Wrong transaction type | Rent and sale are different jobs-to-be-done |
| Property type / condition mismatch | User selected a concrete category |
| Listing source mismatch | Private-only / agency-only is an explicit trust or workflow choice |
| Red feature missing | Deal-breaker semantics: without this, the property is not viable |
| Outside selected polygon | Geography is mostly non-negotiable in rental search |

#### Best Match soft-expansion gates

When sorting by `SearchSortOption.bestMatch`, the engine allows controlled near-misses into the candidate pool, then penalizes them in scoring:

| Constraint | Best Match candidate limit | Why |
|---|---:|---|
| Budget | up to **22%** above max budget | Allows valuable near-budget properties without flooding the deck |
| Rooms | down to **0.5 rooms** below requested rooms | Handles Israeli half-room listings and flexible layouts |
| Minimum size | down to **78%** of requested min m² | Small but efficient layouts can still be relevant |
| Maximum size | up to **140%** of requested max m² | Bigger is often acceptable if price/value is strong |
| Minimum floor | one floor below requested floor | Avoids losing near matches because of noisy floor data |
| Move-in date | grace of **14 / 21 / 30 days** for immediate / 30d / 90d filters | Real rental timelines are negotiable within small windows |

When the user selects an explicit non-recommendation sort such as **price low-to-high**, those same numeric filters become strict again. This preserves user control: Best Match explores intelligently; explicit sorting obeys exact filters.

---

### 2. Compatibility Score

The score is a weighted sum capped at 100:

```text
score =
  affordability_budget_fit      (22)
  + local_market_value          (12)
  + location_fit                (14)
  + space_fit                   (14)
  + move_in_timing              (8)
  + feature_preference_fit      (14)
  + listing_confidence          (12)
  + business_readiness          (4)
  -----------------------------------
  max                           100
```

The weights reflect observed rental-market priorities:

- Tenants care most about affordability, location, and whether the home actually matches their lifestyle.
- Landlords need qualified leads, not vanity likes from users who cannot move in or cannot afford the unit.
- The business needs a healthy marketplace: high-quality, complete, actionable listings should outrank thin or stale listings even when both technically match.

---

### 3. Scoring Components

#### Affordability Budget Fit — 22 points

Budget is scored with an asymmetric exponential decay:

```text
ratio = property_price / max_budget

if no budget:
  score = 22

if ratio <= 1:
  score = 22 * (0.94 + comfort_discount * 0.06)

if ratio > 1:
  score = 22 * exp(-((ratio - 1) / 0.18)^1.45)
```

Under-budget homes receive almost full credit, with a small comfort bonus for meaningful savings. Over-budget homes decay smoothly: a small overage remains viable, while large overages quickly lose rank. This removes the old hard cliff where a property 1 shekel above budget could disappear despite being otherwise excellent.

#### Local Market Value — 12 points

The engine builds a robust market index from the current catalog:

1. Compute each listing's `pricePerSquareMeter`.
2. Bucket comparable listings by `city + transactionType + propertyType`.
3. Fall back to broader buckets when there are too few samples:
   `city + transaction`, then `transaction + propertyType`, then transaction-wide, then catalog-wide.
4. Use **median price/m²** instead of average.
5. Use **median absolute deviation (MAD)** to understand how volatile that market bucket is.

Properties below the local median receive high value scores. Properties above the median decay according to the volatility of their comparable market. That means a 10% premium in a noisy luxury segment is treated differently from a 10% premium in a stable commodity segment.

#### Location Fit — 14 points

Location remains explicit:

- If a city is selected, only that city passes and gets full location credit.
- If `all_israel` is selected, every location receives full location credit.
- If a map area is selected, the property's GPS point must be inside the polygon and then receives full location credit.

The point-in-polygon test lives in `SearchArea.contains`, keeping location logic deterministic and easy to test.

#### Space Fit — 14 points

Space is split into three signals:

| Signal | Weight | Behavior |
|---|---:|---|
| Rooms | 8 | Full credit at or above requested rooms; smooth penalty down to half-room shortage |
| Size | 5 | Full credit inside range; exponential penalty for undersized homes; gentler penalty for oversized homes |
| Floor | 1 | Full credit at/above requested floor; partial credit for unknown or one-floor near miss |

This mirrors real tenant behavior: rooms carry more meaning than exact square meters, and a bigger home is usually less harmful than a smaller one.

#### Move-In Timing — 8 points

Move-in fit uses the selected deadline:

```text
any          -> 8
immediate    -> full if entryDate <= today, then soft decay during grace
within30Days -> full if entryDate <= today + 30, then soft decay during grace
within90Days -> full if entryDate <= today + 90, then soft decay during grace
```

Unknown dates receive partial confidence only when the timing filter is otherwise open. When the user asks for a timing window, missing or far-late dates are filtered or heavily penalized.

#### Feature Preference Fit — 14 points

Rentch's tri-state feature tags map directly into ranking:

| Tap state | Meaning | Algorithm effect |
|---|---|---|
| Default | Ignored | No scoring effect |
| Blue | Preferred | Weighted soft boost |
| Red | Deal breaker | Hard gate; missing property score is 0 |

Blue tags are weighted by rarity using an IDF-style weight:

```text
feature_weight = log((catalog_size + 1) / (feature_frequency + 1)) + 1
```

Rare preferred features such as parking, shelter room, or roof balcony can therefore matter more than commodity features that nearly every listing has. The matched weighted ratio is then passed through a concave reward:

```text
ratio = matched_preferred_weight / total_preferred_weight
reward = 1 - (1 - ratio)^1.5
score = required_feature_score(4) + preferred_feature_score(10 * reward)
```

The concave curve rewards partial matches without making every blue feature binary. A property matching 2 out of 3 meaningful preferences should outrank one matching none, but a perfect feature match still wins.

#### Listing Confidence — 12 points

The ranker rewards listings that are more likely to convert into a real viewing or signed lease:

- Media richness: at least one photo/video, multiple assets, and video tours.
- Address completeness: city, street, street number, neighborhood.
- Property metadata: condition and property type.
- Owner traceability: owner name, source URL, valid coordinates.
- Social proof: review count and review average.
- Source friction: private/direct listings receive a small conversion advantage while agency listings still remain viable.

This is both a customer-quality and business-quality signal. Thin listings waste swipes and create low-intent conversations; complete listings produce better matches.

#### Business Readiness — 4 points

This small score prevents the algorithm from being purely tenant-centric. It gives extra credit to properties that are ready to create marketplace value:

- Clear transaction intent.
- Valid price and size data.
- Lower-friction direct ownership path.
- Entry date that is not too far in the future.
- Enough media, owner, and address data to support an immediate tour request.

The weight is intentionally small. It nudges tie-breaks toward liquid inventory without overpowering user needs.

---

### 4. Final Ranking and Tie-Breaks

For `bestMatch`, properties are sorted by:

1. Compatibility score, descending.
2. Local market value score, descending.
3. Listing confidence score, descending.
4. Price, ascending.
5. Property id, ascending for deterministic output.

This keeps the deck stable across renders while still preferring better value and higher-confidence listings when two properties have the same visible score.

---

### 5. Worked Example

Tenant filters:

- Max budget: ₪6,000
- Minimum rooms: 3
- City: Tel Aviv
- Red tag: `parking`
- Blue tags: `balcony`, `elevator`
- Move-in: within 30 days

| Property | Price | Signals | Outcome |
|---|---:|---|---|
| A | ₪6,250 | 3 rooms, parking, balcony, elevator, strong media, good owner data | Included by Best Match despite being 4.2% over budget; high feature and confidence scores push it up |
| B | ₪5,600 | 3 rooms, parking only, weak media, incomplete owner/address data | Included, but ranks below A because price alone is not enough |
| C | ₪5,200 | 3 rooms, balcony, elevator, **no parking** | Excluded and `matchScore == 0` because it fails the red-tag gate |

If the same user switches from **Best Match** to **price low-to-high**, Property A is filtered out because explicit price sorting uses strict budget semantics.

---

### 6. Why This Is Better

The old approach mixed filtering and scoring, which made the algorithm less intelligent than the UI claimed. A property above budget or slightly below room count could be removed before the matching engine evaluated quality, market value, or feature fit.

The current engine fixes that by making the decision architecture explicit:

- **Hard gates** protect trust and user intent.
- **Soft scoring** captures real-world tradeoffs.
- **Robust market baselines** prevent misleading value judgments.
- **Feature rarity** reflects what actually differentiates apartments.
- **Listing confidence** improves tenant experience and landlord lead quality.
- **Business readiness** keeps the marketplace focused on inventory that can convert.

The behavior is covered by `test/dating_provider_algorithm_test.dart`, including soft budget inclusion, deal-breaker exclusion, ranking order, and strict-budget behavior for explicit price sorting.

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
