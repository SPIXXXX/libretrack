import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/login_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isCreating = false;
  bool _showCreateForm = false;
  String? _selectedRole;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Stream<List<_AccountRecord>> _accountsStream() {
    return FirebaseFirestore.instance.collection('users').snapshots().map((
      snapshot,
    ) {
      final accounts = snapshot.docs.map(_AccountRecord.fromDoc).toList();
      accounts.sort((a, b) {
        final roleCompare = _roleSort(a.role).compareTo(_roleSort(b.role));
        if (roleCompare != 0) return roleCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return accounts;
    });
  }

  Future<FirebaseAuth> _secondaryAuth() async {
    const appName = 'libretrack-admin-account-creator';
    try {
      final app = Firebase.app(appName);
      return FirebaseAuth.instanceFor(app: app);
    } on FirebaseException {
      final app = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      return FirebaseAuth.instanceFor(app: app);
    }
  }

  Future<void> _createLibrarianAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);
    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final auth = await _secondaryAuth();
      final credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(code: 'missing-user');
      }

      await user.updateDisplayName(name);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': name,
        'email': email,
        'role': 'librarian',
        'accountType': 'librarian',
        'accountStatus': 'active',
        'disabled': false,
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await auth.signOut();

      if (!mounted) return;
      _formKey.currentState!.reset();
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      setState(() => _showCreateForm = false);
      _showMessage('Librarian account created.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showMessage(_authErrorMessage(e), isError: true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not create librarian account.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _updateRole(_AccountRecord account, String role) async {
    if (account.uid == FirebaseAuth.instance.currentUser?.uid) {
      _showMessage('You cannot change your own admin role.', isError: true);
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(account.uid).set({
      'role': role,
      'accountType': role,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _showMessage('${account.name} is now ${_formatRole(role)}.');
  }

  Future<void> _setDisabled(_AccountRecord account, bool disabled) async {
    if (account.uid == FirebaseAuth.instance.currentUser?.uid) {
      _showMessage('You cannot disable your own account.', isError: true);
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(account.uid).set({
      'disabled': disabled,
      'accountStatus': disabled ? 'disabled' : 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _showMessage(disabled ? 'Account disabled.' : 'Account enabled.');
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF2BA6A3),
      ),
    );
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      default:
        return e.message ?? 'Could not create librarian account.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2BA6A3),
          onRefresh: () async => setState(() {}),
          child: StreamBuilder<List<_AccountRecord>>(
            stream: _accountsStream(),
            builder: (context, snapshot) {
              final accounts = snapshot.data ?? const <_AccountRecord>[];
              final filteredAccounts = _selectedRole == null
                  ? accounts
                  : accounts
                        .where((account) => account.role == _selectedRole)
                        .toList();
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  _AdminTopBar(onSignOut: _signOut),
                  const SizedBox(height: 18),
                  _StatsRow(
                    accounts: accounts,
                    selectedRole: _selectedRole,
                    onRoleSelected: (role) {
                      setState(() {
                        _selectedRole = _selectedRole == role ? null : role;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _CreateLibrarianPanel(
                    formKey: _formKey,
                    nameController: _nameController,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    isExpanded: _showCreateForm,
                    isCreating: _isCreating,
                    onToggle: () {
                      setState(() => _showCreateForm = !_showCreateForm);
                    },
                    onCreate: _createLibrarianAccount,
                  ),
                  const SizedBox(height: 18),
                  _AccountListHeader(
                    title: _accountsTitle(_selectedRole),
                    count: filteredAccounts.length,
                    showClear: _selectedRole != null,
                    onClear: () => setState(() => _selectedRole = null),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 42),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2BA6A3),
                        ),
                      ),
                    )
                  else if (filteredAccounts.isEmpty)
                    _EmptyAccounts(role: _selectedRole)
                  else
                    ...filteredAccounts.map(
                      (account) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AccountTile(
                          account: account,
                          onRoleChanged: (role) => _updateRole(account, role),
                          onDisabledChanged: (disabled) =>
                              _setDisabled(account, disabled),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AdminTopBar extends StatelessWidget {
  const _AdminTopBar({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF4B23C6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.admin_panel_settings_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin',
                style: TextStyle(
                  color: Color(0xFF121926),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manage LibraTrack accounts',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded, color: Color(0xFFE43C44)),
          tooltip: 'Sign out',
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.accounts,
    required this.selectedRole,
    required this.onRoleSelected,
  });

  final List<_AccountRecord> accounts;
  final String? selectedRole;
  final ValueChanged<String> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final students = accounts.where((a) => a.role == 'student').length;
    final librarians = accounts.where((a) => a.role == 'librarian').length;
    final admins = accounts.where((a) => a.role == 'admin').length;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: 'Students',
            value: '$students',
            isSelected: selectedRole == 'student',
            icon: Icons.school_rounded,
            color: const Color(0xFF2BA6A3),
            onTap: () => onRoleSelected('student'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Librarians',
            value: '$librarians',
            isSelected: selectedRole == 'librarian',
            icon: Icons.local_library_rounded,
            color: const Color(0xFF4B23C6),
            onTap: () => onRoleSelected('librarian'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Admins',
            value: '$admins',
            isSelected: selectedRole == 'admin',
            icon: Icons.verified_user_rounded,
            color: const Color(0xFFE2A346),
            onTap: () => onRoleSelected('admin'),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool isSelected;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.11) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFD9DEE8),
              width: isSelected ? 1.6 : 1,
            ),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: color.withValues(alpha: 0.16),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const Spacer(),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.chevron_right_rounded,
                    color: isSelected ? color : const Color(0xFF9CA3AF),
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF121926),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? color : const Color(0xFF6B7280),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountListHeader extends StatelessWidget {
  const _AccountListHeader({
    required this.title,
    required this.count,
    required this.showClear,
    required this.onClear,
  });

  final String title;
  final int count;
  final bool showClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF121926),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFD9DEE8)),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF4B5563),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (showClear) ...[
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
            label: const Text('All'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4B23C6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ],
    );
  }
}

class _CreateLibrarianPanel extends StatelessWidget {
  const _CreateLibrarianPanel({
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.isExpanded,
    required this.isCreating,
    required this.onToggle,
    required this.onCreate,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isExpanded;
  final bool isCreating;
  final VoidCallback onToggle;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9DEE8)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: Color(0xFF4B23C6),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Create Librarian Account',
                      style: TextStyle(
                        color: Color(0xFF121926),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF6B7280),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 14),
            Form(
              key: formKey,
              child: Column(
                children: [
                  _AdminInputField(
                    controller: nameController,
                    label: 'Full name',
                    icon: Icons.person_outline_rounded,
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 10),
                  _AdminInputField(
                    controller: emailController,
                    label: 'Email',
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 10),
                  _AdminInputField(
                    controller: passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: isCreating ? null : onCreate,
                      icon: isCreating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        isCreating ? 'Creating...' : 'Create account',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4B23C6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  static String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required.';
    if (!text.contains('@') || !text.contains('.')) {
      return 'Enter a valid email.';
    }
    return null;
  }

  static String? _passwordValidator(String? value) {
    final text = value ?? '';
    if (text.length < 6) {
      return 'Use at least 6 characters.';
    }
    return null;
  }
}

class _AdminInputField extends StatelessWidget {
  const _AdminInputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFF4B23C6), size: 20),
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9DEE8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD9DEE8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4B23C6), width: 1.5),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.onRoleChanged,
    required this.onDisabledChanged,
  });

  final _AccountRecord account;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<bool> onDisabledChanged;

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(account.role);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: account.disabled
              ? const Color(0xFFF3B4B8)
              : const Color(0xFFD9DEE8),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: roleColor.withValues(alpha: 0.14),
                child: Text(
                  account.initial,
                  style: TextStyle(
                    color: roleColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF121926),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _RoleChip(role: account.role, color: roleColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _validRole(account.role),
                  decoration: InputDecoration(
                    labelText: 'Role',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text('Student')),
                    DropdownMenuItem(
                      value: 'librarian',
                      child: Text('Librarian'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value != null && value != account.role) {
                      onRoleChanged(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Disabled',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Switch(
                    value: account.disabled,
                    activeThumbColor: const Color(0xFFE43C44),
                    onChanged: onDisabledChanged,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.color});

  final String role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _formatRole(role),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({this.role});

  final String? role;

  @override
  Widget build(BuildContext context) {
    final message = role == null
        ? 'No account documents found.'
        : 'No ${_formatRole(role!).toLowerCase()} accounts found.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_outline_rounded, color: Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _accountsTitle(String? role) {
  if (role == null) return 'All Accounts';
  return '${_formatRole(role)} Accounts';
}

class _AccountRecord {
  const _AccountRecord({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.disabled,
  });

  final String uid;
  final String name;
  final String email;
  final String role;
  final bool disabled;

  String get initial {
    final source = name.trim().isNotEmpty ? name : email;
    return source.trim().isEmpty ? '?' : source.trim()[0].toUpperCase();
  }

  factory _AccountRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final email = _stringValue(data['email'], fallback: 'No email');
    final accountStatus = _stringValue(
      data['accountStatus'],
      fallback: '',
    ).toLowerCase();
    return _AccountRecord(
      uid: doc.id,
      name: _stringValue(
        data['name'] ?? data['fullName'] ?? data['displayName'],
        fallback: email,
      ),
      email: email,
      role: _validRole(
        _stringValue(
          data['role'] ?? data['accountType'],
          fallback: 'student',
        ).toLowerCase(),
      ),
      disabled: data['disabled'] == true || accountStatus == 'disabled',
    );
  }
}

String _stringValue(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return fallback;
}

String _validRole(String role) {
  switch (role) {
    case 'admin':
    case 'librarian':
    case 'student':
      return role;
    default:
      return 'student';
  }
}

String _formatRole(String role) {
  final safeRole = _validRole(role);
  return safeRole[0].toUpperCase() + safeRole.substring(1);
}

Color _roleColor(String role) {
  switch (_validRole(role)) {
    case 'admin':
      return const Color(0xFFE2A346);
    case 'librarian':
      return const Color(0xFF4B23C6);
    default:
      return const Color(0xFF2BA6A3);
  }
}

int _roleSort(String role) {
  switch (_validRole(role)) {
    case 'admin':
      return 0;
    case 'librarian':
      return 1;
    default:
      return 2;
  }
}
