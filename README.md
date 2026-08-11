# Portal GPhotos

A native Android app that allows you to pick photos and videos from your Google Photos library and display them as a slideshow on your Facebook Portal.

[![Get it on OpenPortal](https://andronedev.github.io/openportal/openportal-badge.svg)](https://andronedev.github.io/openportal/apps/com.ramnat.portalgphotos)

---

## 1. Prerequisites
- A Facebook Portal with Developer Mode (ADB) enabled.
- A computer with `adb` installed.
- [Download the latest release APK](https://github.com/ram-nat/portal-gphotos/releases/latest) and place it in the project directory, or clone this repo to build from source.

---

## 2. Google Cloud Platform Setup

Because this app connects to your personal Google Photos library, you need to create your own Google Cloud project and generate OAuth credentials.

1. **Create a project** at <https://console.cloud.google.com>.
2. **Enable the Photos Picker API**: APIs & Services → Library → search "Photos Picker
   API" → Enable. (Not the Library API, not the Ambient API.)
3. **OAuth consent screen**:
   - User type: **External**.
   - Add the scope `https://www.googleapis.com/auth/photospicker.mediaitems.readonly`.
   - Add your own Google account as a **Test user**.
4. **Create the OAuth client**: Credentials → Create credentials → OAuth client ID →
   Application type **Desktop app** → download the JSON (`client_secret.json`).

---

## 3. Deployment

Connect your Facebook Portal to your computer via USB (or over Wi-Fi ADB). Make sure to authorize the connection on the Portal screen.

Run the provided deployment script. It installs the APK, pushes your credentials, and launches the app. The app is launched manually and does not replace Portal's stock screensaver. Ensure you have downloaded the APK to your current directory, or explicitly specify its path using `--apk`:

```bash
./scripts/deploy.sh --apk app-release.apk --client client_secret.json
```

**Windows (PowerShell):**

```powershell
.\scripts\deploy.ps1 -Apk app-release.apk -Client client_secret.json
```

*(Note: If you have multiple devices connected, you can specify the target device with `-s <serial>` for Mac/Linux, or `-Serial <serial>` for Windows)*

The old OpenPortal **Set up screensaver** action should not be used with this manual-launch build because it registers the retired Dream service. Use the deployment script until OpenPortal offers a configuration-only action.

---

## 4. Usage
- Long press on screen to bring up the menu.
- Swipe left/right to navigate between photos.
- Settings screen to control slideshow settings, weather, etc.
- Swipe down from top to get the top bar while the slideshow is open.
- Tap to dismiss the slideshow (configurable).
- To keep adding photos easily, create a dedicated album in Google Photos and add the photos you want to use on your Portal slideshow to that album. In the picker, search for the album name (it can take up to 24 hours after album creation to show up in picker search) and select all to add photos. As you keep adding more photos over time, simply keep selecting all and adding them - only the new photos will be downloaded.

---

## 5. Bugs and Updates

- If you installed before 2026-06-13 (Builds v0.1.5 and before), there's a bug where when oauth refresh token expires, there is no way to refresh it from the device. To fix this, please use `deploy.sh` to re-deploy a later build. After this, you should be able to sign-in and grant access again from the device.

- Switch from Debug to Release APKs - if you are not building your own, this is a breaking change from release v0.1.3 - `deploy.sh` will handle retaining any downloaded media + client credentials automatically. However, you may lose your settings in the app and set them again.

---

## Screenshots

![Setup](docs/setup_screen.png)
![Picker](docs/add_photos_screen.png)
![Slideshow](docs/showing_screen.png)
