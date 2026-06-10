# 🏔️ HillRaabta

<div align="center">

### Signal Gaya, Raabta Nahi.

**Offline Communication & Safety Platform for Mountain Travelers**

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)
![Dart](https://img.shields.io/badge/Dart-3.x-blue)
![Android](https://img.shields.io/badge/Android-Supported-green)
![iOS](https://img.shields.io/badge/iOS-In%20Progress-lightgrey)
![Status](https://img.shields.io/badge/Status-Active%20Development-orange)

</div>

---

## 📖 Overview

HillRaabta is an offline-first communication and safety platform designed for travelers, trekkers, and adventure groups exploring remote mountain regions where mobile networks are unreliable or completely unavailable.

The project aims to help people remain connected even when cellular connectivity is lost, improving coordination, safety, and emergency communication during outdoor adventures.

**Signal na ho, Raabta toh rahega.**

---

## ❗ Problem Statement

Travelers visiting remote mountain regions often face:

* No mobile network coverage
* Inability to communicate with group members
* Difficulty sharing locations
* Delayed emergency response
* Lack of connectivity during trekking and expeditions

Popular destinations such as Sikkim, Himachal Pradesh, Ladakh, Spiti Valley, and other mountainous regions frequently experience low or no network availability. HillRaabta aims to bridge this communication gap through offline-first technologies.

---

## ✨ Features

### Current Features

* User onboarding and trip joining
* Trip-based group creation
* Flutter cross-platform architecture
* Offline-first application structure
* Android support
* Modern travel-focused UI

### Planned Features

* Offline peer-to-peer messaging
* Nearby traveler discovery
* Mesh communication between devices
* Emergency SOS alerts
* Offline location sharing
* Offline maps and routes
* Saved travel routes
* Group coordination tools
* Offline media sharing
* Travel safety toolkit

---

## 📱 Platform Support

| Platform | Status            |
| -------- | ----------------- |
| Android  | ✅ Available       |
| iOS      | 🚧 In Development |

---

## 🛠️ Tech Stack

### Frontend

* Flutter
* Dart

### Mobile Platforms

* Android
* iOS

### Connectivity

* Nearby Connections
* Bluetooth Communication
* Wi-Fi Direct
* Mesh Networking (Planned)

### Maps & Navigation

* OpenStreetMap
* Offline Map Storage

### Storage

* Local Device Storage
* Offline Data Persistence

---

## 🚀 Use Cases

### Trekking Groups

Stay connected with fellow trekkers even when there is no mobile network.

### Adventure Travel

Coordinate routes, locations, and updates during remote travel.

### Mountain Tourism

Enable safer communication among travelers in low-connectivity areas.

### Emergency Situations

Broadcast SOS alerts and important information to nearby users.

---

## 🏗️ Project Structure

```text
lib/
├── core/
│   ├── transport/
│   ├── storage/
│   └── mesh/
│
├── features/
│   ├── chat/
│   ├── map/
│   ├── sos/
│   ├── music/
│   └── mvp/
│
└── main.dart
```

---

## ⚙️ Installation & Setup

### Prerequisites

Make sure you have installed:

* Flutter SDK
* Dart SDK
* Android Studio / VS Code / Cursor
* Android Emulator or Physical Android Device

Verify Flutter installation:

```bash
flutter doctor
```

---

### Clone Repository

```bash
git clone https://github.com/adrijakarmakar33/HillRaabta.git
cd HillRaabta
```

---

### Install Dependencies

```bash
flutter pub get
```

---

### Run Application

```bash
flutter run
```

If multiple devices are connected:

```bash
flutter devices
```

Run on a specific device:

```bash
flutter run -d DEVICE_ID
```

---

## 📦 Build Release APK

Generate production APK:

```bash
flutter build apk --release
```

APK Location:

```text
build/app/outputs/flutter-apk/app-release.apk
```

---

## 📦 Build Android App Bundle

For Play Store deployment:

```bash
flutter build appbundle --release
```

---

## 🍎 iOS Build

Requirements:

* macOS
* Xcode
* Apple Developer Account

Build command:

```bash
flutter build ios --release
```

---

## 🎯 Vision

To create a reliable offline communication platform that keeps travelers connected beyond traditional mobile networks.

A future where:

* Groups stay connected during remote travel
* Emergencies are reported faster
* Outdoor adventures become safer
* Communication continues even when signals disappear

---

## 🗺️ Future Roadmap

### Phase 1

* User onboarding
* Trip groups
* Offline architecture

### Phase 2

* Nearby device discovery
* Offline messaging
* Emergency SOS

### Phase 3

* Offline maps
* Location sharing
* Saved routes

### Phase 4

* Mesh networking
* Group coordination
* Offline media transfer

---

## 👩‍💻 Developer

**Adrija Karmakar**

Computer Science Undergraduate

---

## 📌 Project Status

🚧 Active Development

HillRaabta is currently under active development and new features are being added continuously.

Feedback, suggestions, and contributions are welcome.

---

## 📜 License

This project is currently maintained by the author for educational, research, and innovation purposes.

---

<div align="center">

### 🏔️ Signal Gaya, Raabta Nahi. 📡

Building safer journeys beyond network coverage.

</div>
