import 'dart:async';
import 'dart:io';

// Cloud Firestore stores extra profile information after Auth creates the user.
import 'package:cloud_firestore/cloud_firestore.dart';

// FirebaseAuth creates the email/password account and keeps the user signed in.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libretrack/pages/Student/home_page.dart';
import 'package:libretrack/services/storage_service.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _schoolIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _acceptedTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  double _passwordStrength = 0.0;
  File? _selectedImage;
  final ImagePicker _imagePicker = ImagePicker();
  final StorageService _storageService = StorageService();
  String? _profileImageUrl;
  final bool _isUploadingImage = false;

  @override
  void dispose() {
    _nameController.dispose();
    _schoolIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  double _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0.0;

    double strength = 0.0;

    // Length scoring
    if (password.length >= 8) strength += 0.25;
    if (password.length >= 12) strength += 0.1;

    // Character type scoring
    if (password.contains(RegExp(r'[a-z]'))) strength += 0.2;
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2;
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.15;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.1;

    return strength.clamp(0.0, 1.0);
  }

  String _getStrengthLabel(double strength) {
    if (strength < 0.3) return 'Weak';
    if (strength < 0.6) return 'Fair';
    if (strength < 0.8) return 'Good';
    return 'Strong';
  }

  Color _getStrengthColor(double strength) {
    if (strength < 0.3) return const Color(0xFFD32F2F);
    if (strength < 0.6) return const Color(0xFFF57C00);
    if (strength < 0.8) return const Color(0xFFFBC02D);
    return const Color(0xFF388E3C);
  }

  Future<void> _pickProfileImage() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                await _pickFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        setState(() => _selectedImage = File(photo.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final photo = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (photo != null) {
        setState(() => _selectedImage = File(photo.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the terms first.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final schoolId = _schoolIdController.text.trim();
      final email = _emailController.text.trim();

      // Step 1: Create the Auth account — this is the only REQUIRED step before navigating
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email,
            password: _passwordController.text,
          )
          .timeout(const Duration(seconds: 30));

      final user = credential.user;
      if (user == null) throw FirebaseAuthException(code: 'missing-user');

      if (!mounted) return;

      // Step 2: Navigate IMMEDIATELY — user feels instant registration
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const StudentPage()),
        (route) => false,
      );

      // Step 3: Do all heavy work in the background AFTER navigating
      // User is already on the home screen while these run silently
      unawaited(
        _runBackgroundTasks(
          user: user,
          name: name,
          schoolId: schoolId,
          email: email,
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(e))));
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed. Check your connection.')),
      );
      setState(() => _isLoading = false);
    }
  }

  // Runs silently after the user has already been navigated to StudentPage
  Future<void> _runBackgroundTasks({
    required User user,
    required String name,
    required String schoolId,
    required String email,
  }) async {
    // Run image upload + display name update IN PARALLEL (same time, not sequential)
    final results = await Future.wait([
      // Upload profile image to Cloudinary (if selected)
      _selectedImage != null
          ? _storageService
                .uploadProfilePicture(_selectedImage!)
                .then((url) {
                  _profileImageUrl = url;
                  return url;
                })
                .catchError((_) => '')
          : Future.value(''),

      // Update Firebase Auth display name
      user
          .updateDisplayName(name)
          .timeout(const Duration(seconds: 15))
          .then((_) => '')
          .catchError((_) => ''),
    ]);

    debugPrint('[Register] Background tasks done. Image URL: ${results[0]}');

    // Save full profile to Firestore (after parallel tasks so image URL is ready)
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        await _saveStudentProfile(
          user: user,
          name: name,
          schoolId: schoolId,
          email: email,
        ).timeout(const Duration(seconds: 30));
        debugPrint('[Register] Profile saved to Firestore successfully.');
        return;
      } on TimeoutException {
        if (attempt < 2) await Future.delayed(const Duration(seconds: 3));
      } on FirebaseException catch (e) {
        debugPrint('[Register] Firestore error: ${e.code} - ${e.message}');
        if (e.code == 'permission-denied' || e.code == 'not-found') return;
        if (attempt < 2) await Future.delayed(const Duration(seconds: 3));
      } catch (e) {
        debugPrint('[Register] Unexpected error saving profile: $e');
        return;
      }
    }
    debugPrint('[Register] Profile save failed after 3 attempts.');
  }

  Future<void> _saveStudentProfile({
    required User user,
    required String name,
    required String schoolId,
    required String email,
  }) {
    return FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      // Same id as the Firebase Auth user.
      'uid': user.uid,

      // Student profile fields entered in this register form.
      'name': name,
      'schoolId': schoolId,
      'email': email,

      // Role can be used later for student/librarian/admin access checks.
      'role': 'student',

      // Store the profile picture URL from Cloudinary
      'photoUrl': _profileImageUrl,

      // serverTimestamp lets Firebase write the official server time.
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Converts Firebase error codes into friendlier messages for the SnackBar.
  String _firebaseAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Please sign in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'network-request-failed':
        return 'Please check your internet connection and try again.';
      default:
        return e.message ?? 'Registration failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: const Color(0xFF3C13C5),
                          tooltip: 'Back',
                        ),
                      ),
                      const SizedBox(height: 8),
                      _ProfilePhotoPlaceholder(
                        selectedImage: _selectedImage,
                        onTap: _pickProfileImage,
                        isUploading: _isUploadingImage,
                      ),
                      const SizedBox(height: 22),
                      _RegisterInputField(
                        controller: _nameController,
                        label: 'Name',
                        icon: Icons.person_outline_rounded,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your name.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _RegisterInputField(
                        controller: _schoolIdController,
                        label: 'School ID',
                        icon: Icons.badge_outlined,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your school ID.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _RegisterInputField(
                        controller: _emailController,
                        label: 'Email',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) {
                            return 'Please enter your email.';
                          }
                          if (!email.contains('@')) {
                            return 'Please enter a valid email.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      _RegisterInputField(
                        controller: _passwordController,
                        label: 'Password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFFA9A7A7),
                            size: 22,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a password.';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters.';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          setState(() {
                            _passwordStrength = _calculatePasswordStrength(
                              value,
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (_passwordController.text.isNotEmpty)
                        _PasswordStrengthIndicator(
                          strength: _passwordStrength,
                          label: _getStrengthLabel(_passwordStrength),
                          color: _getStrengthColor(_passwordStrength),
                        ),
                      const SizedBox(height: 8),
                      _RegisterInputField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        icon: Icons.lock_reset_rounded,
                        obscureText: _obscureConfirmPassword,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFFA9A7A7),
                            size: 22,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password.';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      CheckboxListTile(
                        value: _acceptedTerms,
                        onChanged: _isLoading
                            ? null
                            : (value) {
                                setState(() {
                                  _acceptedTerms = value ?? false;
                                });
                              },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: const Color(0xFF3C13C5),
                        title: const Text(
                          'I agree with LibraTrack Terms of Service and Privacy Policy.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFF4B4B4B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3C13C5),
                            foregroundColor: const Color(0xF2F2F2F2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xF2F2F2F2),
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Register',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Already have account? ',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.black,
                            ),
                          ),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF3C13C5),
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFF3C13C5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePhotoPlaceholder extends StatelessWidget {
  final File? selectedImage;
  final VoidCallback onTap;
  final bool isUploading;

  const _ProfilePhotoPlaceholder({
    this.selectedImage,
    required this.onTap,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEBF1F1),
                border: Border.all(
                  color: const Color(0xFFA5B4FC),
                  width: 2,
                  style: BorderStyle.solid,
                ),
              ),
              child: selectedImage != null
                  ? ClipOval(
                      child: Image.file(selectedImage!, fit: BoxFit.cover),
                    )
                  : const Icon(
                      Icons.person_outline_rounded,
                      color: Color(0xFF818CF8),
                      size: 42,
                    ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: GestureDetector(
                onTap: isUploading ? null : onTap,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3C13C5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: isUploading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          selectedImage != null
              ? 'Profile picture selected'
              : 'Profile picture can be added later',
          style: const TextStyle(fontSize: 12, color: Color(0xFF606060)),
        ),
      ],
    );
  }
}

class _RegisterInputField extends StatelessWidget {
  const _RegisterInputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
          child: Container(
            width: 40,
            height: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFCBCED1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: const Color(0xFF1E1E1E)),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 61,
          minHeight: 56,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFEBF1F1),
        labelStyle: const TextStyle(fontSize: 16, color: Color(0xFF8C8C8C)),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF3C13C5),
          fontWeight: FontWeight.w500,
        ),
        errorMaxLines: 2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 20,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF3C13C5), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
        ),
      ),
    );
  }
}

class _PasswordStrengthIndicator extends StatelessWidget {
  const _PasswordStrengthIndicator({
    required this.strength,
    required this.label,
    required this.color,
  });

  final double strength;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Password strength:',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF606060),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: strength,
            minHeight: 6,
            backgroundColor: const Color(0xFFE0E0E0),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
