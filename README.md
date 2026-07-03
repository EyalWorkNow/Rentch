<div align="center">

# 🏡 Rently

### The apartment rental & sale marketplace that actually *understands* you.

*Swipe to match. Talk to find. Get places that fit — not just places that exist.*

[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.6-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Backend](https://img.shields.io/badge/Backend-AWS%20Lambda%20%C2%B7%20DynamoDB-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/lambda/)
[![AI](https://img.shields.io/badge/AI-GPT%20%C2%B7%20Gemini%20%C2%B7%20on--device-8A2BE2)](#-the-ai-assistants)
[![Platform](https://img.shields.io/badge/iOS%20%7C%20Android-000?logo=apple&logoColor=white)](https://flutter.dev)

</div>

---

## 💡 What is Rently?

Rently reimagines finding a home as a **two‑sided, opt‑in match** — tenants swipe on apartments, landlords swipe on applicants, and a mutual "yes" opens a chat that carries the deal all the way to a **tamper‑evident digital signature**.

But the heart of Rently is that it **listens**. Two AI agents — **אתי** for renters/buyers and **אריק** for landlords — hold a real, warm conversation, understand *who you are*, and a server‑side **14‑cohort personalization engine** ranks listings by how well each neighbourhood actually fits your life: schools for a religious family, transit for a car‑free single parent, quiet for someone working from home.

> Not "here are apartments in your budget." Rather — *"here are the apartments that fit **you**."*

---

## ✨ Highlights

| | |
|---|---|
| 🎙️ **אתי — the search agent** | A warm, multilingual conversation (Hebrew · Arabic · English · French · Russian) that infers your persona and surfaces *real* listings inline. Text **and** voice. |
| 🏘️ **אריק — the landlord agent** | Publishes a listing from a natural spoken description — professional, efficient, one‑to‑two‑minute flow to a live draft. |
| 🧠 **14‑cohort personalization** | Point‑level `community_fit` + `neighborhood_fit` from 19k geolocated schools, safety & socio data — ranks listings per persona, not per keyword. |
| 🔮 **Liquid‑glass voice UI** | A GPU fragment‑shader orb (refraction · dispersion · frost · depth) that *breathes with the agent's voice*. Shared by both assistants. |
| 💞 **Two‑sided matching** | Tinder‑style swipe for tenants and landlords; a double opt‑in opens a chat. |
| ✍️ **Digital contracts** | End‑to‑end **Ed25519** signing — tamper‑evident leases, keys never leave the device. |
| 🌍 **Immersive listings** | In‑app 360° street‑view capture + server stitching, and walkable 3D scans. |
| ⚡ **Token‑frugal by design** | Most turns are answered **on‑device** with zero LLM tokens; the model is spent only where it adds real value. |

---

## 🧠 The Personalization Engine

The ranker is a **cohort‑aware weighted model** running in the AWS Lambda router. A searcher is resolved into one of 14 cohorts (family, student, oleh, dati‑leumi, charedi, senior, single‑parent, new‑parents, remote, young‑professional, couple, single, investor, arab‑family), and each cohort carries its **own weights + price target**.

```
rankScore = Σ  wᵢ(cohort) · featureᵢ
            └ freshness · popularity · completeness · priceFit
              · neighborhood_fit · community_fit · semantic
```

* **`community_fit`** reads the *actual* composition within 1.5 km of a listing — e.g. charedi‑stream school density for a charedi family — from a bundled join of **19,297 geolocated schools** (`schools_geo`).
* **`neighborhood_fit`** blends schools, kindergartens, safety (per‑capita crime + socio by CBS locality) and walkability.
* Every listing is **enriched on create** and back‑filled in bulk, so ranking is genuinely personalized rather than a flat budget filter.

> Data sources are live‑verified against `data.gov.il` (education, crime, census, socio‑economic). Community signals are **soft** — never a hard demographic filter on housing.

---

## 🎙️ The AI Assistants

### אתי — for renters & buyers
* **Persona intelligence** — infers hidden needs (a family wants a shelter room & schools nearby; a student wants roommates near campus; an investor wants yield) and asks *one* smart, persona‑fit question.
* **Speaks your language** — detects the input language and replies in it, with the same warmth.
* **Location, done right** — when you say *"in my area"*, אתי **requests** GPS; you approve; the app captures it. She never grabs location silently.
* **Never dead‑ends** — if nothing matches, she progressively widens (budget → constraints → area) and says so.
* **Token‑frugal** — clear Hebrew criteria turns are answered from the on‑device parser (zero tokens); GPT is reserved for genuine ambiguity or non‑Hebrew.

### אריק — for landlords
* Turns a free spoken description into a structured listing via **function‑calling** (`create_property`), confirming details professionally before publishing.

### The liquid‑glass orb
Both agents share one presence — a `shaders/liquid_glass.frag` fragment shader: four colour balls suspended in a frosted glass dome, contained inside the circle, that **pulse in size and colour with the agent's speech**.

---

## 🏗️ Architecture

```
┌──────────────────────────── Flutter app (iOS · Android) ────────────────────────────┐
│  Swipe deck · Matches · Chat · Contracts · 360°/3D · Landlord dashboard              │
│  ┌─────────────── אתי (search) ───────────────┐   ┌────────── אריק (publish) ───────┐ │
│  │ on‑device SmartSearch parse + cohort signals│   │ voice call · liquid‑glass orb   │ │
│  │ LiquidGlassOrb (fragment shader)            │   │                                 │ │
│  └─────────────────────────────────────────────┘   └─────────────────────────────────┘ │
└───────────────────────────────────────┬──────────────────────────────────────────────┘
                                         │  Firebase‑JWT authorized HTTPS
                         ┌───────────────▼─────────────── AWS API Gateway ───────────────┐
                         │            rentch-router  (single Node 20 Lambda)             │
                         │  /assistant (אתי GPT · אריק function‑calling)                  │
                         │  /assistant/extract · /properties (cohort‑ranked)             │
                         │  cohort.mjs · ranking.mjs · neighborhood.mjs (schools/safety) │
                         └───────────────┬───────────────────────────────┬──────────────┘
                                         │                               │
                             DynamoDB (properties, matches,     data.gov.il · OpenAI · Gemini
                             messages, contracts, events)       (LLM + geo/education/crime)
```

* **Backend** — one Node ESM Lambda (`aws/lambda/router/`) behind API Gateway, DynamoDB for storage, deployed via CloudFormation (`aws/template.yaml`, `aws/deploy.sh`).
* **LLMs** — אתי runs on **GPT**; אריק on GPT function‑calling; realtime voice on the OpenAI Realtime API (distinctive `marin` voice). On‑device parsing keeps most turns token‑free.

---

## 🧩 Tech Stack

**App** · Flutter 3.44 / Dart 3.6 · Provider · fragment shaders · `speech_to_text` + `flutter_tts` · `geolocator`/`geocoding` · Firebase Auth + Messaging · `cryptography` (Ed25519) · `camera`/`sensors_plus` (360° capture)

**Backend** · AWS Lambda (Node 20, ESM) · API Gateway · DynamoDB · CloudFormation · S3

**AI / Data** · OpenAI (GPT + Realtime) · Google Gemini · `data.gov.il` (schools, crime, census, socio)

---

## 📁 Project Structure

```
lib/
├── core/
│   ├── search/            # SmartSearch parser, cohort signals, ranking engine, lifestyle
│   └── services/          # assistant, realtime voice, aws client, storage
├── data/                  # models, providers, repositories (PropertySearchRepository)
├── presentation/
│   ├── features/
│   │   ├── search/        # אתי chat + AtiVoiceScreen (liquid‑glass)
│   │   ├── assistant/     # אריק voice call + presence
│   │   └── broker/        # broker tools
│   ├── screens/           # discover · matches · chat · profile · landlord · detail
│   └── widgets/           # LiquidGlassOrb, SafeMedia, …
shaders/liquid_glass.frag  # the GPU orb (refraction · dispersion · frost · depth)
aws/
├── lambda/router/         # index.mjs + lib/ (cohort.mjs, ranking.mjs, neighborhood.mjs)
├── template.yaml          # CloudFormation
└── deploy.sh              # package + deploy
test/                      # smart_search, cohort signals, algorithm, persona tests
```

---

## 🚀 Getting Started

```bash
# 1. Prerequisites — Flutter 3.44+, JDK 21 (Android), Xcode (iOS)
flutter --version

# 2. Install
flutter pub get

# 3. Run (device / simulator)
flutter run

# 4. Test
flutter test
```

### Building a release

```bash
# Android APK  (needs JDK 21)
JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home" \
  flutter build apk --release

# iOS IPA → TestFlight
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
xcrun altool --upload-app --type ios -f build/ios/ipa/Rently.ipa \
  --apiKey <ASC_KEY_ID> --apiIssuer <ASC_ISSUER_ID>
```

### Deploying the backend

```bash
cd aws
OPENAI_API_KEY=sk-... GEMINI_API_KEY=... ./deploy.sh
# The router is one Lambda for everything — validate with `node --check` before shipping.
```

---

## 🔒 Security & Privacy

* Every API call is authorized by a **Firebase JWT**; per‑user data isolation on the server.
* Rental contracts are signed with **Ed25519** — private keys never leave the device (secure storage).
* Location is only ever read **after** an explicit user tap.
* Community‑based ranking is a **soft signal**, never a hard demographic gate on housing.

---

<div align="center">

**Rently** — built with Flutter, a lot of care, and two assistants who actually listen. 🏡

</div>
