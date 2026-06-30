# Cachy Mobile Connection & Deployment Guide

This document explains how the physical mobile application (Android / iOS) connects to the Cachy backend server in both **Local Development** and **Cloud Deployment (Hugging Face Spaces)** environments.

---

## 1. How Mobile Connectivity Works

Unlike desktop web browsers running on `localhost`, physical mobile devices run on separate hardware with their own IP addresses and network security policies:

1. **Cleartext HTTP Restrictions (Android 9+):** Android blocks unencrypted HTTP traffic by default. Cachy's mobile app is configured with `<base-config cleartextTrafficPermitted="true" />` in `network_security_config.xml` so you can connect to local LAN IPs (e.g., `http://192.168.x.x:8000`) during development.
2. **Wi-Fi Router Broadcast Isolation:** When testing on a local network, the app attempts UDP broadcast discovery (`Discover LAN Server`) on port `50505`. However, many routers (public Wi-Fi, dorms, office networks, or AP isolation settings) block client-to-client UDP broadcasts.
3. **Active Server Endpoint Override:** To ensure reliable connectivity across all environments, Cachy provides a persistent UI setting in the **You** (Profile) tab where you can inspect or update the active server URL at any time.

---

## 2. Connecting to a Local Development Server

1. Start your backend server locally on your computer:
   ```bash
   ./start.py
   ```
   *(Ensure your computer and mobile device are connected to the exact same Wi-Fi network).*

2. Open the Cachy app on your phone and navigate to the **You** tab.
3. Tap **Discover LAN Server**. The app will scan your network subnet and automatically connect to `http://<your-computer-ip>:8000`.
4. **Manual Override (If discovery times out):**
   If your Wi-Fi router isolates UDP broadcasts:
   - Find your computer's local LAN IP (e.g., `ifconfig` or `ipconfig`, usually `192.168.x.x`).
   - In the Cachy app under **You → Active Server endpoint**, tap the tile, enter `http://<your-computer-ip>:8000`, and tap **Save**.

---

## 3. Connecting to Hugging Face Spaces (Cloud Deployment)

When you deploy Cachy to Hugging Face Spaces using `./deploy_hf.sh`, your backend runs in the cloud over standard HTTPS (e.g., `https://vatxzz-cachy.hf.space`).

You have two ways to connect your physical phone app to your Hugging Face deployment:

### Option A: Build-Time Configuration (Recommended for Release APKs)
Compile your standalone APK passing your Hugging Face Space URL as a Dart compile-time variable:
```bash
cd app
flutter build apk --release --dart-define=CACHY_API_BASE=https://<your-username>-cachy.hf.space
```
- The built APK (`build/app/outputs/flutter-apk/app-release.apk`) will default directly to your cloud deployment at launch.

### Option B: Runtime UI Override (No Recompile Needed)
If you already have a pre-built debug or release APK installed on your device:
1. Open Cachy on your phone and go to the **You** tab.
2. Tap **Active Server endpoint**.
3. Paste your Hugging Face Space URL (`https://<your-username>-cachy.hf.space`) and save.
4. Because the URL is saved to persistent disk storage (`SharedPreferences`), the app will immediately connect to your cloud backend and remember this setting indefinitely.

---

## 4. Frequently Asked Questions

### Q: Do I need to run `./deploy_hf.sh` again after modifying mobile network settings or compiling an APK?
**No.** All mobile networking and UI adjustments live entirely inside the frontend mobile application (`app/`). The Python backend API (`backend/`) on Hugging Face remains unchanged. Once your APK is built or configured with the space URL, it communicates directly with your existing running Hugging Face Space server.

### Q: Why do we need the Active Server Endpoint option in the Profile screen?
- **Transparency:** Lets you verify at a glance whether your app is attempting to reach `10.0.2.2`, a LAN IP, or a cloud server.
- **Flexibility:** Allows switching environments (e.g., from production cloud back to local testing) instantly without connecting your phone to your laptop or recompiling code.
- **Reliability:** Acts as an immediate escape hatch if network firewalls block automatic LAN discovery.
