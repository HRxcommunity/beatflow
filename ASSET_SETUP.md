# BeatFlow — Splash Image Setup

## Step 1: Copy image to assets
The file `assets/images/splash_bg.png` is already included in this zip.
Make sure it's placed at:
```
your_project/assets/images/splash_bg.png
```

## Step 2: Add to pubspec.yaml
In your `pubspec.yaml`, under `flutter:` section, add:

```yaml
flutter:
  assets:
    - assets/images/
    - assets/images/splash_bg.png
  fonts:
    - family: Poppins
      fonts:
        - asset: assets/fonts/Poppins-Regular.ttf
        - asset: assets/fonts/Poppins-Medium.ttf
          weight: 500
        - asset: assets/fonts/Poppins-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Poppins-Bold.ttf
          weight: 700
```

## Step 3: Build
```bash
flutter pub get
flutter build apk --release
```
