# Asset Management Guide

## Folder Structure

```
assets/
  ├── logo.png           (Logo utama - untuk sidebar & login)
  ├── icon_dashboard.png (Icon dashboard - optional)
  └── ...
```

## Cara Menggunakan Gambar di Flutter

### 1. **Simpan gambar di folder yang benar**
Tempat gambar: `assets/logo.png` (langsung di folder assets)

### 2. **Gunakan di Sidebar (dashboard.dart)**
```dart
Image.asset(
  'assets/logo.png',
  width: 48,
  height: 48,
  fit: BoxFit.contain,
)
```

### 3. **Gunakan di Login Screen (login_screen.dart)**
```dart
Image.asset(
  'assets/logo.png',
  width: 100,
  height: 100,
  fit: BoxFit.contain,
)
```

### 4. **Gunakan dengan Color Filter (Tint)**
```dart
Image.asset(
  'assets/logo.png',
  width: 48,
  height: 48,
  color: Colors.white,
  colorBlendMode: BlendMode.srcIn,
)
```

## Tips
- Format gambar yang disarankan: PNG (transparan background)
- Ukuran logo: 500x500px atau lebih (Flutter akan scale otomatis)
- Setelah menambah gambar baru, jalankan: `flutter pub get` atau `flutter clean && flutter pub get`

## Contoh File yang Didukung
- `logo.png` - format PNG dengan transparan
- `logo_dark.png` - versi dark untuk tema gelap
- `logo_light.png` - versi light untuk tema terang
