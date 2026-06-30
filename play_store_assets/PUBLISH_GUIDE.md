# BeatFlow — Play Store Publish Guide

## Step 1: Build Release APK / AAB

```bash
cd music_player
flutter pub get

# For Play Store upload — use AAB (recommended)
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab

# For direct APK install / testing
flutter build apk --release --split-per-abi
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## Step 2: Sign Your App (Required for Play Store)

```bash
# Generate keystore (one time only — KEEP THIS FILE SAFE)
keytool -genkey -v -keystore beatflow-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias beatflow

# Create android/key.properties with:
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=beatflow
storeFile=../beatflow-release.jks
```

Add to android/app/build.gradle under `android {`:
```
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

## Step 3: Privacy Policy

Host `privacy_policy.html` for free on:
- GitHub Pages: Create repo → Settings → Pages → Enable
- URL will be: https://yourusername.github.io/beatflow-privacy/

## Step 4: Google Play Console

1. Go to https://play.google.com/console
2. Create developer account ($25 one-time fee)
3. Create new app → "BeatFlow"
4. Fill in store listing from `store_listing.md`
5. Upload `app-release.aab`
6. Set content rating: Everyone
7. Add privacy policy URL
8. Set distribution: All countries
9. Submit for review (1–3 days)

## Permissions Declaration (Play Console requires this)

When prompted about permissions:
- READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE: "Read local audio files for music playback. No data is uploaded."
- FOREGROUND_SERVICE: "Keep audio playing when app is in background."
- WAKE_LOCK: "Prevent CPU sleep during audio playback."

## Data Safety Section (Play Console)

- Data collected: None
- Data shared: None
- Security practices: Data is encrypted in transit (N/A — offline app)
- Users can request data deletion: N/A (no data collected)
