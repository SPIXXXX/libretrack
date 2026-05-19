import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRoleProfile {
  const UserRoleProfile({required this.data});

  final Map<String, dynamic> data;

  bool get disabled {
    final status = (data['accountStatus'] ?? '').toString().toLowerCase();
    return data['disabled'] == true || status == 'disabled';
  }

  String get role {
    return (data['role'] ?? data['accountType'] ?? 'student')
        .toString()
        .trim()
        .toLowerCase();
  }
}

class UserRoleService {
  static const String defaultAdminEmail = 'admin@gamil.com';

  const UserRoleService._();

  static Future<UserRoleProfile> profileFor(User user) async {
    final users = FirebaseFirestore.instance.collection('users');
    final directDoc = await users.doc(user.uid).get();
    final email = user.email?.trim().toLowerCase() ?? '';

    if (directDoc.exists) {
      final data = directDoc.data() ?? <String, dynamic>{};
      if (email == defaultAdminEmail && _roleFrom(data) != 'admin') {
        await users.doc(user.uid).set({
          'uid': user.uid,
          'email': email,
          'role': 'admin',
          'accountType': 'admin',
          'disabled': false,
          'accountStatus': 'active',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return UserRoleProfile(
          data: {
            ...data,
            'uid': user.uid,
            'email': email,
            'role': 'admin',
            'accountType': 'admin',
            'disabled': false,
            'accountStatus': 'active',
          },
        );
      }
      return UserRoleProfile(data: data);
    }

    final emailDoc = email.isEmpty
        ? null
        : await users.where('email', isEqualTo: email).limit(1).get();

    if (emailDoc != null && emailDoc.docs.isNotEmpty) {
      final data = Map<String, dynamic>.from(emailDoc.docs.first.data());
      await users.doc(user.uid).set({
        ...data,
        'uid': user.uid,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return UserRoleProfile(data: data);
    }

    if (email == defaultAdminEmail) {
      final data = <String, dynamic>{
        'uid': user.uid,
        'name': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Admin',
        'email': email,
        'role': 'admin',
        'accountType': 'admin',
        'disabled': false,
        'accountStatus': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await users.doc(user.uid).set(data, SetOptions(merge: true));
      return UserRoleProfile(data: data);
    }

    return const UserRoleProfile(data: <String, dynamic>{});
  }

  static String _roleFrom(Map<String, dynamic> data) {
    return (data['role'] ?? data['accountType'] ?? 'student')
        .toString()
        .trim()
        .toLowerCase();
  }
}
