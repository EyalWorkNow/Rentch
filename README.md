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
- **Feature Chips**: Filter by balcony, parking, elevator, pets, and more.
- Built-in contrast logic: adapts colors dynamically for high accessibility.

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
