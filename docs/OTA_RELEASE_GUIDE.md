# 🚀 BeatFlow OTA Release Guide

> **Ek baar setup karo, phir sirf ek command se release karo:**
> `git tag v1.1.0 && git push origin v1.1.0`

---

## Part 1 — Pehli Baar Setup (Sirf Ek Baar)

### Step 1: GitHub pe repo banao

1. GitHub.com → New repository → naam: `beatflow`
2. **Private** rakho (APK public nahi hoga)
3. `lib/firebase_options.dart` aur `google-services.json` gitignore mein already hain

```bash
git remote add origin https://github.com/YOUR_USERNAME/beatflow.git
git push -u origin main
```

### Step 2: `app_constants.dart` mein apna username daalo

```dart
// lib/core/constants/app_constants.dart
static const String githubOwner = 'YOUR_ACTUAL_USERNAME';  // ← yahan
static const String githubRepo  = 'beatflow';
```

---

### Step 3: Release Keystore banao (signed APK ke liye)

**Agar pehle se keystore nahi hai:**

```bash
keytool -genkey -v \
  -keystore beatflow-release.jks \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias beatflow-key
```

Passwords yaad rakho — woh GitHub Secrets mein jayenge.

---

### Step 4: GitHub Secrets setup karo

GitHub repo → **Settings → Secrets and variables → Actions → New secret**

Yeh 6 secrets banana hai:

| Secret Name | Kya hai | Kaise banate hain |
|-------------|---------|-------------------|
| `FIREBASE_OPTIONS_DART` | `lib/firebase_options.dart` ka content | `base64 < lib/firebase_options.dart` |
| `GOOGLE_SERVICES_JSON` | `android/app/google-services.json` ka content | `base64 < android/app/google-services.json` |
| `KEYSTORE_BASE64` | `.jks` file ka base64 | `base64 < beatflow-release.jks` |
| `KEY_ALIAS` | Keystore alias | `beatflow-key` (jo tune banate waqt diya) |
| `KEY_PASSWORD` | Key password | (jo tune keytool mein diya) |
| `STORE_PASSWORD` | Store password | (jo tune keytool mein diya) |

**Base64 encode karne ke commands (terminal mein chalao):**

```bash
# Mac/Linux:
base64 < lib/firebase_options.dart     # FIREBASE_OPTIONS_DART ke liye
base64 < android/app/google-services.json  # GOOGLE_SERVICES_JSON ke liye
base64 < beatflow-release.jks         # KEYSTORE_BASE64 ke liye

# Windows (PowerShell):
[Convert]::ToBase64String([IO.File]::ReadAllBytes("lib\firebase_options.dart"))
```

> **💡 Tip:** Output copy karo aur GitHub Secret mein paste karo.

---

### Step 5: Pehli Release Test karo

```bash
git add .
git commit -m "feat: add OTA update system"
git tag v1.0.0
git push origin main
git push origin v1.0.0
```

GitHub → Actions tab pe jao → Build chal raha hoga (~5-8 minutes)  
Release tab pe APK attached hoga ✅

---

## Part 2 — Har Naye Update Pe (30 Seconds)

### Nayi version release karna:

```bash
# 1. pubspec.yaml mein version bump karo:
#    version: 1.0.0+1  →  version: 1.1.0+2

# 2. Changes commit karo:
git add .
git commit -m "feat: naya feature add kiya"

# 3. Tag push karo — bas itna kafi hai:
git tag v1.1.0
git push origin main
git push origin v1.1.0
```

**GitHub Actions automatically:**
- Flutter setup karega
- APK build karega (signed)
- GitHub Release banayega
- APK attach karega

**Users ke phone pe:**
- App kholte hi 4 second baad dialog aayega
- "Download Update" press karenge → browser mein APK download hoga
- Install karenge → done!

---

## Part 3 — Version Numbering

Format: `MAJOR.MINOR.PATCH`

| Change Type | Example | Command |
|-------------|---------|---------|
| Bug fix | 1.0.0 → 1.0.1 | `git tag v1.0.1` |
| New feature | 1.0.1 → 1.1.0 | `git tag v1.1.0` |
| Breaking change | 1.1.0 → 2.0.0 | `git tag v2.0.0` |

---

## Part 4 — Release Notes (Changelog)

GitHub Release banate waqt description mein likho:
- Bullet points: `• Yeh fix kiya`
- `[REQUIRED]` tag lagao → users ko mandatory update aayega (dismiss nahi kar sakte)

**Example:**
```
• Together session crash fix
• YouTube video load fast ab
• Dark mode improvement
[REQUIRED]
```

---

## Part 5 — Troubleshooting

**Q: GitHub Actions fail ho raha hai?**
→ Actions tab pe click karo → red X pe click karo → logs dekho
→ Most common: Secret missing ya wrong format

**Q: APK build hua but signature mismatch?**
→ Purana APK uninstall karo phir nayi version install karo
→ Same keystore use karo hamesha

**Q: App mein update dialog nahi aa raha?**
→ `AppConstants.githubOwner` check karo — apna actual username hona chahiye
→ GitHub repo **Public** hai ya Private? (Private ke liye API token chahiye — Public recommended)
→ Release "draft" to nahi hai? Draft releases skip hoti hain

**Q: "required" update force karna hai?**
→ Release description mein `[REQUIRED]` likho
→ Users "Maybe Later" button nahi dekh payenge

---

## Quick Reference

```bash
# Nayi release (sirf yeh 3 commands):
git tag v1.x.x
git push origin main  
git push origin v1.x.x
```

```
Workflow file:  .github/workflows/build-release.yml
Update service: lib/services/update_service.dart
Update dialog:  lib/features/update/update_dialog.dart
Constants:      lib/core/constants/app_constants.dart
```
