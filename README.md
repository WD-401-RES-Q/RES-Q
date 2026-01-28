# RES-Q: Community Disaster Incident Reporting and Emergency Alert System

A mobile-based platform designed to enhance disaster preparedness and real-time emergency coordination in Angeles City.

**Team Members**

- Member 1: Dungca, Rakishi Duelle T.
- Member 2: Macapagal, Paul Justine M.
- Member 3: Mirasol, Karlo Martin Q.
- Member 4: Reyes, John Benedict P.

---

## 📌 Project Overview

RES-Q is a mobile community reporting and alert system that enables citizens to post geotagged disaster incidents, upload media, receive real-time alerts, and directly contact the Angeles City Disaster Risk Reduction and Management Office (ACDRRMO).

Its goal is to improve situational awareness, accelerate response time, and strengthen community involvement during emergencies.

---

## 🚀 What the App Does

### For Citizens

- Submit geotagged incident reports with photos/videos
- View real-time community feed of disaster incidents
- Access live interactive disaster map
- Upvote/downvote reports for crowdsourced verification
- Emergency call feature (VoIP/Hotline)
- Receive real-time alerts from ACDRRMO
- PIN-based login for quick and secure access

### For ACDRRMO Staff

- Verify and validate incident reports
- View live responder locations on map
- Trigger city-wide or barangay-specific alerts
- Manage and log incident data
- Access semi-admin dashboard

### For Admins

- Review and approve user registrations
- Manage user roles (Citizen/Staff/Admin)
- Monitor system activity and logs
- Access administrator web dashboard

---

## 💻 Installation

### Mobile App Installation (Flutter)

#### Prerequisites

- Flutter SDK (3.0 or higher)
- Dart SDK
- Android Studio or VS Code
- Firebase CLI
- Android device/emulator or iOS device/simulator

#### Steps

1. **Clone the repository**

   ```bash
   git clone <repository-url>
   cd RES-Q
   ```

2. **Navigate to the mobile app directory**

   ```bash
   cd res_q
   ```

3. **Install dependencies**

   ```bash
   flutter pub get
   ```

4. **Configure Firebase**
   - Create a new Firebase project at [Firebase Console](https://console.firebase.google.com)
   - Add Android/iOS apps to your Firebase project
   - Download `google-services.json` (Android) and place it in `android/app/`
   - Download `GoogleService-Info.plist` (iOS) and place it in `ios/Runner/`
   - Run Firebase configuration:
     ```bash
     flutterfire configure
     ```

5. **Run the app**

   ```bash
   flutter run
   ```

6. **Build for production**
   - For Android APK:
     ```bash
     flutter build apk --release
     ```
   - For Android App Bundle:
     ```bash
     flutter build appbundle --release
     ```
   - For iOS:
     ```bash
     flutter build ios --release
     ```

---

### Web App Installation (Angular Admin Dashboard)

#### Prerequisites

- Node.js (18.x or higher)
- npm or yarn
- Firebase CLI
- Modern web browser

#### Steps

1. **Navigate to the web app directory**

   ```bash
   cd res_qwebapp
   ```

2. **Install dependencies**

   ```bash
   npm install
   ```

3. **Configure Firebase**
   - Update Firebase configuration in `src/environments/environment.ts`
   - Add your Firebase project credentials:
     ```typescript
     export const environment = {
       production: false,
       firebase: {
         apiKey: "YOUR_API_KEY",
         authDomain: "YOUR_AUTH_DOMAIN",
         projectId: "YOUR_PROJECT_ID",
         storageBucket: "YOUR_STORAGE_BUCKET",
         messagingSenderId: "YOUR_MESSAGING_SENDER_ID",
         appId: "YOUR_APP_ID",
       },
     };
     ```

4. **Run development server**

   ```bash
   npm start
   ```

   Or

   ```bash
   ng serve
   ```

   Access the app at `http://localhost:4200`

5. **Build for production**

   ```bash
   npm run build
   ```

   Or

   ```bash
   ng build --configuration production
   ```

6. **Deploy to Firebase Hosting (Optional)**
   ```bash
   firebase deploy --only hosting
   ```

---

## 📚 Additional Documentation

For detailed information about specific features and workflows, please refer to:

- **ADMIN_APPROVAL_FLOW.md** - Complete user registration and approval workflow
- **IMPLEMENTATION_SUMMARY.md** - Technical implementation details
- **QUICK_START_GUIDE.md** - User and admin quick reference guide

---

## 🔐 Security Features

- PIN-based authentication with Firebase Auth
- Multi-Factor Authentication (MFA)
- Role-Based Access Control (RBAC)
- Encrypted data transmission (HTTPS/SSL)
- Compliance with the Data Privacy Act of 2012

---

## 🛠️ Technology Stack

- **Mobile:** Flutter & Dart
- **Web Dashboard:** Angular & TypeScript
- **Backend:** Firebase (Firestore, Authentication, Storage, Hosting)
- **Maps:** Google Maps API
- **SMS Notifications:** Semaphore/Twilio API

---

## 📄 License

This project is developed for educational purposes as part of a university capstone project.
