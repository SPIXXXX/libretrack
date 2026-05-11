import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libretrack/pages/login_page.dart';
import 'package:libretrack/services/storage_service.dart';

class LibrarianProfilePage extends StatelessWidget {
  const LibrarianProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFE3E7EB),
        body: Center(child: Text('Please log in to view your profile.')),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = LibrarianProfile.fromFirebase(
          user: user,
          data: snapshot.data?.data(),
        );

        return Scaffold(
          backgroundColor: const Color(0xFFE3E7EB),
          body: RefreshIndicator(
            onRefresh: () async => user.reload(),
            child: SafeArea(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  const _ProfileTopBar(title: 'Profile'),
                  const SizedBox(height: 18),
                  _ProfileHeader(profile: profile),
                  const SizedBox(height: 18),
                  _InfoPanel(
                    children: [
                      _InfoRow(
                        icon: Icons.badge_outlined,
                        label: 'Librarian ID',
                        value: profile.staffId,
                      ),
                      _InfoRow(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        value: profile.email,
                      ),
                      _InfoRow(
                        icon: Icons.verified_user_outlined,
                        label: 'Role',
                        value: profile.role,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ProfileActionTile(
                    icon: Icons.manage_accounts_outlined,
                    title: 'Profile Settings',
                    subtitle: 'View and update your profile information',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              LibrarianProfileSettingsPage(profile: profile),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    subtitle: 'Return to the login page',
                    isDestructive: true,
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                        (route) => false,
                      );
                    },
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting) ...[
                    const SizedBox(height: 18),
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2BA6A3),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class LibrarianProfileSettingsPage extends StatefulWidget {
  const LibrarianProfileSettingsPage({super.key, required this.profile});

  final LibrarianProfile profile;

  @override
  State<LibrarianProfileSettingsPage> createState() =>
      _LibrarianProfileSettingsPageState();
}

class _LibrarianProfileSettingsPageState
    extends State<LibrarianProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _staffIdController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _storageService = StorageService();

  File? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.name;
    _staffIdController.text = widget.profile.staffId == 'Not set'
        ? ''
        : widget.profile.staffId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _staffIdController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (image == null || !mounted) return;
      setState(() => _selectedImage = File(image.path));
    } catch (e) {
      _showMessage('Could not pick image: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Please log in again.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      var photoUrl = widget.profile.photoUrl;
      if (_selectedImage != null) {
        photoUrl = await _storageService.uploadProfilePicture(_selectedImage!);
      }

      final name = _nameController.text.trim();
      final staffId = _staffIdController.text.trim();

      await user.updateDisplayName(name);
      if (_selectedImage != null && photoUrl.isNotEmpty) {
        await user.updatePhotoURL(photoUrl);
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'displayName': name,
        'schoolId': staffId,
        'staffId': staffId,
        'email': widget.profile.email,
        'role': 'librarian',
        'accountType': 'librarian',
        'photoUrl': photoUrl,
        'profileImageUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showMessage('Profile updated successfully.');
      Navigator.pop(context);
    } catch (e) {
      _showMessage('Could not update profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            _ProfileTopBar(
              title: 'Profile Settings',
              leading: _AniyomiIconButton(
                onTap: () => Navigator.pop(context),
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: 'Back',
              ),
            ),
            const SizedBox(height: 18),
            _SettingsPanel(
              child: Column(
                children: [
                  _EditableAvatar(
                    imageFile: _selectedImage,
                    photoUrl: profile.photoUrl,
                    name: profile.name,
                    onTap: _isSaving ? null : _pickProfileImage,
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _SettingsField(
                          controller: _nameController,
                          label: 'Profile Name',
                          icon: Icons.person_outline_rounded,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _SettingsField(
                          controller: _staffIdController,
                          label: 'Librarian ID',
                          icon: Icons.badge_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your librarian ID.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoPanel(
              children: [
                _InfoRow(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  value: profile.email,
                ),
                _InfoRow(
                  icon: Icons.verified_user_outlined,
                  label: 'Account Type',
                  value: profile.role,
                ),
                _InfoRow(
                  icon: Icons.fingerprint_rounded,
                  label: 'User ID',
                  value: profile.uid,
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2BA6A3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibrarianProfile {
  const LibrarianProfile({
    required this.uid,
    required this.name,
    required this.staffId,
    required this.email,
    required this.role,
    required this.photoUrl,
  });

  final String uid;
  final String name;
  final String staffId;
  final String email;
  final String role;
  final String photoUrl;

  factory LibrarianProfile.fromFirebase({
    required User user,
    required Map<String, dynamic>? data,
  }) {
    return LibrarianProfile(
      uid: user.uid,
      name: _stringValue(
        data?['name'],
        fallback: user.displayName ?? 'Librarian',
      ),
      staffId: _stringValue(
        data?['staffId'] ?? data?['schoolId'],
        fallback: 'Not set',
      ),
      email: _stringValue(data?['email'], fallback: user.email ?? 'No email'),
      role: _formatRole(_stringValue(data?['role'], fallback: 'librarian')),
      photoUrl: _stringValue(
        data?['photoUrl'],
        fallback: _stringValue(
          data?['profileImageUrl'],
          fallback: user.photoURL ?? '',
        ),
      ),
    );
  }
}

String _stringValue(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String _formatRole(String role) {
  if (role.isEmpty) return 'Librarian';
  return role[0].toUpperCase() + role.substring(1).toLowerCase();
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({required this.title, this.leading});

  final String title;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF121926),
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final LibrarianProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileAvatar(photoUrl: profile.photoUrl, name: profile.name),
          const SizedBox(height: 14),
          Text(
            profile.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Color(0xFF121926),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.staffId,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF5A5862),
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F7F4),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              profile.role,
              style: const TextStyle(
                color: Color(0xFF1D756D),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.name});

  final String photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'L' : name.trim()[0].toUpperCase();

    return CircleAvatar(
      radius: 48,
      backgroundColor: const Color(0xFF2BA6A3),
      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
      child: photoUrl.isEmpty
          ? Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.imageFile,
    required this.photoUrl,
    required this.name,
    required this.onTap,
  });

  final File? imageFile;
  final String photoUrl;
  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'L' : name.trim()[0].toUpperCase();

    ImageProvider? image;
    if (imageFile != null) {
      image = FileImage(imageFile!);
    } else if (photoUrl.isNotEmpty) {
      image = NetworkImage(photoUrl);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 56,
          backgroundColor: const Color(0xFF2BA6A3),
          backgroundImage: image,
          child: image == null
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 2,
          child: IconButton.filled(
            onPressed: onTap,
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Change profile picture',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF2BA6A3),
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2BA6A3), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF7B8190),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xFF121926),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? const Color(0xFFD32F2F)
        : const Color(0xFF121926);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? color : const Color(0xFF2BA6A3),
                size: 24,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF7B8190),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  const _SettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2BA6A3), width: 1.5),
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _AniyomiIconButton extends StatefulWidget {
  const _AniyomiIconButton({
    required this.onTap,
    required this.icon,
    required this.tooltip,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String tooltip;

  @override
  State<_AniyomiIconButton> createState() => _AniyomiIconButtonState();
}

class _AniyomiIconButtonState extends State<_AniyomiIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }

    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(widget.icon, color: const Color(0xFF121926), size: 22),
          ),
        ),
      ),
    );
  }
}
