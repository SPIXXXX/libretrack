import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Password reset flow:
/// 1. User enters their email address
/// 2. App validates the email format
/// 3. Firebase sends a password reset link to that email
/// 4. Success message shows which email received the link
/// 5. User can check their inbox/spam folder for the reset email
/// 6. Firebase handles the actual password reset via the email link

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isLoading = false;
  String? _successEmail;

  @override
  void initState() {
    super.initState();
    // Pre-fill email field from login page if provided
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// RESET PASSWORD FUNCTION
  /// This is where the password reset process happens:
  /// 1. User enters their email in the form
  /// 2. Form validates the email format (must have @ symbol and not be empty)
  /// 3. Sends request to Firebase Auth which generates a unique reset link
  /// 4. Firebase sends an email to the user with the reset link
  /// 5. User clicks the link in the email to reset their password
  /// 6. App shows a success message with the email address
  Future<void> _sendPasswordResetEmail() async {
    FocusScope.of(context).unfocus();

    // Validate form before sending
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();

      /// FIREBASE PASSWORD RESET - This is the key line that resets the password
      /// Firebase Auth generates a unique password reset link and emails it to the user
      /// The user will click the link in their email to reset their password on Firebase's secure page
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      // Show success state with email confirmation
      setState(() {
        _isLoading = false;
        _successEmail = email;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password reset link sent. Check your email inbox or spam folder.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_firebaseAuthMessage(e))));
      setState(() => _isLoading = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send reset email. Please try again.'),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  String _firebaseAuthMessage(FirebaseAuthException e) {
    // Convert Firebase error codes to user-friendly messages
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
        return 'No account was found with that email address.';
      case 'network-request-failed':
        return 'Please check your internet connection and try again.';
      case 'too-many-requests':
        return 'Too many reset attempts. Please wait a moment and try again.';
      default:
        return e.message ?? 'Could not send reset email. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: Stack(
          children: [
            // Back button - positioned at top left
            Positioned(
              top: 4,
              left: 12,
              child: IconButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
                color: const Color(0xFF3C13C5),
                tooltip: 'Back',
              ),
            ),
            // Main form content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.lock_reset_rounded,
                          size: 64,
                          color: Color(0xFF3C13C5),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Reset Password',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Enter your email and we will send a password reset link.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: Colors.black,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _ResetInputField(
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
                        if (_successEmail != null) ...[
                          const SizedBox(height: 16),
                          _ResetSentMessage(email: _successEmail!),
                        ],
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : _sendPasswordResetEmail,
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
                                    'Send Reset Link',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        if (_successEmail != null) ...[
                          const SizedBox(height: 14),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text(
                              'Back to Login',
                              style: TextStyle(
                                color: Color(0xFF3C13C5),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} // Ends _ForgotPasswordPageState.

class _ResetSentMessage extends StatelessWidget {
  const _ResetSentMessage({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    // Success message displayed after Firebase accepts the reset request
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF6EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF58A76A), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xFF2E7D32),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Reset link sent to $email. Check your inbox or spam folder.',
              style: const TextStyle(
                color: Color(0xFF255D31),
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetInputField extends StatelessWidget {
  const _ResetInputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
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
        filled: true,
        fillColor: const Color(0xFFEBF1F1),
        labelStyle: const TextStyle(fontSize: 16, color: Color(0xFF8C8C8C)),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF3C13C5),
          fontWeight: FontWeight.w500,
        ),
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
