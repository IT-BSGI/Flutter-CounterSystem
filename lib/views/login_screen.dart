import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'dashboard.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool isLoading = false;
  bool rememberEmail = false;

  @override
  void initState() {
    super.initState();
    loadSavedEmail();
  }

  Future<void> loadSavedEmail() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedEmail = prefs.getString('saved_email');
    if (savedEmail != null) {
      setState(() {
        emailController.text = savedEmail;
        rememberEmail = true;
      });
    }
  }

  Future<void> saveEmail(String email) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (rememberEmail) {
      await prefs.setString('saved_email', email);
    } else {
      await prefs.remove('saved_email');
    }
  }

  InputDecoration buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.blue),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blue),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
      labelStyle: TextStyle(color: Colors.black26),
      floatingLabelStyle: TextStyle(color: Colors.blueAccent),
    );
  }

  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      // Simpan email jika Remember Email dicentang
      await saveEmail(emailController.text.trim());

      // Navigasi tanpa menumpuk halaman
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Login gagal, coba lagi!";
      if (e.code == 'user-not-found') {
        errorMessage = "Akun tidak ditemukan!";
      } else if (e.code == 'wrong-password') {
        errorMessage = "Password salah!";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50], // Latar belakang biru muda
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "LOGIN",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 20),

                // Email Input
                SizedBox(
                  width: 250,
                  child: TextFormField(
                    controller: emailController,
                    decoration: buildInputDecoration("Email", Icons.email),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) =>
                        value!.isEmpty ? "Masukkan email!" : null,
                  ),
                ),
                const SizedBox(height: 10),

                // Password Input
                SizedBox(
                  width: 250,
                  child: TextFormField(
                    controller: passwordController,
                    decoration: buildInputDecoration("Password", Icons.lock),
                    obscureText: true,
                    validator: (value) =>
                        value!.isEmpty ? "Masukkan password!" : null,
                    textInputAction: TextInputAction.done, // Menampilkan tombol "Done" di keyboard
                    onFieldSubmitted: (value) => login(), // Menjalankan login saat Enter ditekan
                  ),
                ),
                const SizedBox(height: 10),

                // Remember Me Checkbox
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Checkbox(
                      value: rememberEmail,
                      activeColor: Colors.blueAccent,
                      onChanged: (value) {
                        setState(() => rememberEmail = value!);
                      },
                    ),
                    const Text(
                      "Remember Email",
                      style: TextStyle(color: Colors.blueAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Login Button
                isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: 250,
                        child: ElevatedButton(
                          onPressed: login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            "Login",
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),

                // Forgot Password & Register
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    "Lupa Password?",
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    "Belum punya akun? Daftar",
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
