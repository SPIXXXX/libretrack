import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libretrack/pages/login_page.dart';
import 'package:libretrack/services/storage_service.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const _SignedOutProfile();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final profile = StudentProfile.fromFirebase(
          user: user,
          data: snapshot.data?.data(),
        );

        return Scaffold(
          backgroundColor: const Color(0xFFE3E7EB),
          body: RefreshIndicator(
            onRefresh: () async {
              await user.reload();
            },
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
                        label: 'Student ID',
                        value: profile.schoolId,
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
                          builder: (_) => ProfileSettingsPage(profile: profile),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _ProfileActionTile(
                    icon: Icons.history_rounded,
                    title: 'Borrow History',
                    subtitle: 'View all your borrowed books',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BorrowHistoryPage(userId: user.uid),
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

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key, required this.profile});

  final StudentProfile profile;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _schoolIdController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _storageService = StorageService();

  File? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.name;
    _schoolIdController.text = widget.profile.schoolId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _schoolIdController.dispose();
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
      final schoolId = _schoolIdController.text.trim();

      await user.updateDisplayName(name);
      if (_selectedImage != null && photoUrl.isNotEmpty) {
        await user.updatePhotoURL(photoUrl);
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'schoolId': schoolId,
        'email': widget.profile.email,
        'displayName': name,
        'role': widget.profile.role.toLowerCase(),
        'accountType': widget.profile.role.toLowerCase(),
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
                          controller: _schoolIdController,
                          label: 'Student ID',
                          icon: Icons.badge_outlined,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your student ID.';
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

class StudentProfile {
  const StudentProfile({
    required this.uid,
    required this.name,
    required this.schoolId,
    required this.email,
    required this.role,
    required this.photoUrl,
  });

  final String uid;
  final String name;
  final String schoolId;
  final String email;
  final String role;
  final String photoUrl;

  factory StudentProfile.fromFirebase({
    required User user,
    required Map<String, dynamic>? data,
  }) {
    return StudentProfile(
      uid: user.uid,
      name: _stringValue(
        data?['name'],
        fallback: user.displayName ?? 'Student',
      ),
      schoolId: _stringValue(data?['schoolId'], fallback: 'Not set'),
      email: _stringValue(data?['email'], fallback: user.email ?? 'No email'),
      role: _formatRole(_stringValue(data?['role'], fallback: 'student')),
      photoUrl: _stringValue(
        data?['photoUrl'],
        fallback: _stringValue(
          data?['profileImageUrl'],
          fallback: user.photoURL ?? '',
        ),
      ),
    );
  }

  static String _stringValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  static String _formatRole(String role) {
    if (role.isEmpty) return 'Student';
    return role[0].toUpperCase() + role.substring(1).toLowerCase();
  }
}

class _SignedOutProfile extends StatelessWidget {
  const _SignedOutProfile();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFE3E7EB),
      body: Center(child: Text('Please log in to view your profile.')),
    );
  }
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

  final StudentProfile profile;

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
            profile.schoolId,
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
    final initial = name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase();

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
    final initial = name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase();

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

// ─── Borrow History Page ──────────────────────────────────────────────────────

class BorrowHistoryPage extends StatelessWidget {
  const BorrowHistoryPage({super.key, required this.userId});

  final String userId;

  static Timestamp? _ts(Map<String, dynamic> d) =>
      (d['borrowedAt'] ??
              d['borrowed_at'] ??
              d['scannedAt'] ??
              d['scanned_at'] ??
              d['createdAt'])
          as Timestamp?;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: _ProfileTopBar(
                title: 'Borrow History',
                leading: _AniyomiIconButton(
                  onTap: () => Navigator.pop(context),
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                // orderBy omitted — no composite index needed; sorted below.
                stream: FirebaseFirestore.instance
                    .collection('borrow_records')
                    .where('studentUid', isEqualTo: userId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2BA6A3),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: Color(0xFFB3261E),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Could not load borrow history',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF121926),
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFB3261E),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final rawDocs = snapshot.data?.docs ?? [];
                  final records = List.of(rawDocs)
                    ..sort((a, b) {
                      final aTs = _ts(a.data());
                      final bTs = _ts(b.data());
                      if (aTs == null && bTs == null) return 0;
                      if (aTs == null) return 1;
                      if (bTs == null) return -1;
                      return bTs.compareTo(aTs);
                    });

                  if (records.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 64,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No borrow history yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7B8190),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = _StudentBorrowRecord.fromDoc(
                        records[index],
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _StudentHistoryCard(record: record),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Data model (mirrors _BorrowerRecord from librarian_page) ────────────────

class _StudentBorrowRecord {
  const _StudentBorrowRecord({
    required this.bookTitle,
    required this.author,
    required this.coverUrl,
    required this.borrowedAtMillis,
    required this.dueDateMillis,
    required this.returnedAtMillis,
    required this.status,
  });

  final String bookTitle;
  final String author;
  final String coverUrl;
  final int borrowedAtMillis;
  final int dueDateMillis;
  final int returnedAtMillis;
  final String status;

  bool get isReturned => status == 'returned' || status == 'return';

  bool get isOverdue {
    if (isReturned || dueDateMillis == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > dueDateMillis;
  }

  String get statusLabel => isReturned
      ? 'Returned'
      : isOverdue
      ? 'Overdue'
      : 'Borrowed';

  Color get statusColor => isReturned
      ? const Color(0xFF4B23C6)
      : isOverdue
      ? const Color(0xFFE43C44)
      : const Color(0xFF19A7A1);

  factory _StudentBorrowRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();

    int millis(Object? v) {
      if (v is Timestamp) return v.millisecondsSinceEpoch;
      return 0;
    }

    String str(Object? v, String fallback) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return fallback;
    }

    final borrowedMs = millis(
      d['borrowedAt'] ??
          d['borrowed_at'] ??
          d['scannedAt'] ??
          d['scanned_at'] ??
          d['createdAt'],
    );

    // due date: scan_page writes both 'dueDate' and 'due_date'
    final dueDateMs = millis(d['dueDate'] ?? d['due_date']);

    // If no explicit due date, fall back to borrow + 7 days
    final effectiveDueMs = dueDateMs != 0
        ? dueDateMs
        : borrowedMs != 0
        ? borrowedMs + const Duration(days: 7).inMilliseconds
        : 0;

    return _StudentBorrowRecord(
      bookTitle: str(d['bookTitle'] ?? d['title'], 'Untitled Book'),
      author: str(d['author'] ?? d['bookAuthor'], 'Unknown author'),
      coverUrl: str(d['cover_url'] ?? d['coverUrl'], ''),
      borrowedAtMillis: borrowedMs,
      dueDateMillis: effectiveDueMs,
      returnedAtMillis: millis(d['returnedAt'] ?? d['returned_at']),
      status: str(d['status'], 'borrowed').toLowerCase(),
    );
  }
}

// ─── History card (book cover + info + tap for detail sheet) ─────────────────

class _StudentHistoryCard extends StatelessWidget {
  const _StudentHistoryCard({required this.record});

  final _StudentBorrowRecord record;

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StudentBorrowDetailSheet(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Book cover ────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 58,
                  height: 72,
                  child: record.coverUrl.isEmpty
                      ? _BookCoverPlaceholder(title: record.bookTitle)
                      : Image.network(
                          record.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _BookCoverPlaceholder(title: record.bookTitle),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              // ── Text info ─────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            record.bookTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF11121A),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StudentStatusPill(record: record),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF565B66),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ── Date chips row ───────────────────────────────────
                    Row(
                      children: [
                        _MiniDateChip(
                          icon: Icons.login_rounded,
                          label: _fmtShort(record.borrowedAtMillis),
                        ),
                        if (record.dueDateMillis != 0) ...[
                          const SizedBox(width: 6),
                          _MiniDateChip(
                            icon: Icons.event_rounded,
                            label: _fmtShort(record.dueDateMillis),
                            color: record.isOverdue && !record.isReturned
                                ? const Color(0xFFE43C44)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFABB6C2),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtShort(int millis) {
    if (millis == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

// ─── Status pill ─────────────────────────────────────────────────────────────

class _StudentStatusPill extends StatelessWidget {
  const _StudentStatusPill({required this.record});

  final _StudentBorrowRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: record.statusColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            record.isReturned
                ? Icons.assignment_return_rounded
                : record.isOverdue
                ? Icons.warning_amber_rounded
                : Icons.bookmark_added_rounded,
            size: 11,
            color: record.statusColor,
          ),
          const SizedBox(width: 4),
          Text(
            record.statusLabel,
            style: TextStyle(
              color: record.statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini date chip used on the card ─────────────────────────────────────────

class _MiniDateChip extends StatelessWidget {
  const _MiniDateChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF8A93A2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

// ─── Book cover gradient placeholder ─────────────────────────────────────────

class _BookCoverPlaceholder extends StatelessWidget {
  const _BookCoverPlaceholder({required this.title});

  final String title;

  static const _palettes = [
    [Color(0xFF2BA6A3), Color(0xFF1D5FA6)],
    [Color(0xFF4B23C6), Color(0xFF2BA6A3)],
    [Color(0xFF19A7A1), Color(0xFF4B23C6)],
    [Color(0xFF1D5FA6), Color(0xFF19A7A1)],
  ];

  @override
  Widget build(BuildContext context) {
    final idx = title.isNotEmpty ? title.codeUnitAt(0) % _palettes.length : 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _palettes[idx],
        ),
      ),
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

// ─── Detail bottom sheet ──────────────────────────────────────────────────────

class _StudentBorrowDetailSheet extends StatelessWidget {
  const _StudentBorrowDetailSheet({required this.record});

  final _StudentBorrowRecord record;

  String _formatDateTime(int millis) {
    if (millis == 0) return 'N/A';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Borrow Details',
                    style: TextStyle(
                      color: Color(0xFF121926),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF565B66),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // scrollable content
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  // ── Book card ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 66,
                            height: 82,
                            child: record.coverUrl.isEmpty
                                ? _BookCoverPlaceholder(title: record.bookTitle)
                                : Image.network(
                                    record.coverUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _BookCoverPlaceholder(
                                          title: record.bookTitle,
                                        ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BOOK',
                                style: TextStyle(
                                  color: Color(0xFF2BA6A3),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                record.bookTitle,
                                style: const TextStyle(
                                  color: Color(0xFF11121A),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                record.author,
                                style: const TextStyle(
                                  color: Color(0xFF565B66),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _StudentStatusPill(record: record),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Dates card ────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _DetailDateRow(
                          icon: Icons.login_rounded,
                          label: 'Borrowed On',
                          value: _formatDateTime(record.borrowedAtMillis),
                          valueColor: const Color(0xFF11121A),
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        _DetailDateRow(
                          icon: Icons.event_rounded,
                          label: 'Due Date',
                          value: _formatDateTime(record.dueDateMillis),
                          valueColor: record.isOverdue && !record.isReturned
                              ? const Color(0xFFE43C44)
                              : const Color(0xFF2BA6A3),
                          trailingBadge: record.isOverdue && !record.isReturned
                              ? 'OVERDUE'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        _DetailDateRow(
                          icon: Icons.logout_rounded,
                          label: 'Returned On',
                          value: record.isReturned
                              ? _formatDateTime(record.returnedAtMillis)
                              : 'Not yet returned',
                          valueColor: record.isReturned
                              ? const Color(0xFF4B23C6)
                              : const Color(0xFF8A93A2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Date row used inside detail sheet ───────────────────────────────────────

class _DetailDateRow extends StatelessWidget {
  const _DetailDateRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFF11121A),
    this.trailingBadge,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF2BA6A3).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF2BA6A3)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8A93A2),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (trailingBadge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE43C44).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        trailingBadge!,
                        style: const TextStyle(
                          color: Color(0xFFE43C44),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
