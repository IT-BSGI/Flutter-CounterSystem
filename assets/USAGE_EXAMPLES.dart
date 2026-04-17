// Example: Penggunaan Logo Gambar di Dashboard dan Login

// ============ DASHBOARD (Sidebar Logo) ============
// Di dashboard.dart, ganti bagian ini:

// SEBELUM (Icon biasa):
/*
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.dashboard,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
*/

// SESUDAH (Dengan gambar):
/*
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
*/

// ============ LOGIN SCREEN ============
// Di login_screen.dart, tambahkan sebelum "LOGIN" text:

/*
                    // Logo
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Counter System",
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
*/

// ============ TIPS PENTING ============
// 1. Simpan gambar di: assets/logo.png (langsung di assets folder)
// 2. Pastikan pubspec.yaml sudah di-update dengan assets/ (sudah dilakukan)
// 3. Jalankan: flutter pub get (atau flutter clean && flutter pub get)
// 4. Format gambar: PNG dengan transparent background (disarankan)
// 5. Ukuran: 512x512px atau lebih besar (Flutter akan scale otomatis)
