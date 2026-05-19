import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

enum AppNotificationType {
  newBorrow,
  borrowConfirmed,
  returnConfirmed,
  dueSoon,
  overdue,
  general,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.type,
    required this.readBy,
    this.recordId,
    this.bookId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final AppNotificationType type;
  final List<String> readBy;
  final String? recordId;
  final String? bookId;

  bool get isRead {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && readBy.contains(uid);
  }

  factory AppNotification.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return AppNotification(
      id: doc.id,
      title: _stringValue(data['title'], fallback: 'Notification'),
      body: _stringValue(data['body'], fallback: ''),
      createdAt: _dateValue(data['createdAt'] ?? data['created_at']),
      type: _typeValue(data['type']),
      readBy: _stringList(data['readBy']),
      recordId: _nullableString(data['recordId']),
      bookId: _nullableString(data['bookId']),
    );
  }
}

class NotificationService {
  NotificationService._();

  static final _firestore = FirebaseFirestore.instance;
  static StreamSubscription<String>? _tokenRefreshSubscription;

  static Future<void> registerCurrentDevice({required String role}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.subscribeToTopic('libretrack_$role');

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _saveToken(user.uid, role, token);
      }

      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((newToken) {
        unawaited(_saveToken(user.uid, role, newToken));
      });
    } catch (e) {
      debugPrint('[Notifications] Could not register device token: $e');
    }
  }

  static Stream<List<AppNotification>> notificationsStream({
    required String role,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream<List<AppNotification>>.value(const []);
    }

    final query = role == 'librarian'
        ? _firestore
              .collection('notifications')
              .where('recipientRole', isEqualTo: 'librarian')
        : _firestore
              .collection('notifications')
              .where('recipientUid', isEqualTo: user.uid);

    return query.snapshots().map((snapshot) {
      final notifications = snapshot.docs.map(AppNotification.fromDoc).toList();
      notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return notifications;
    });
  }

  static Future<void> markAllRead({required String role}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = role == 'librarian'
        ? await _firestore
              .collection('notifications')
              .where('recipientRole', isEqualTo: 'librarian')
              .get()
        : await _firestore
              .collection('notifications')
              .where('recipientUid', isEqualTo: user.uid)
              .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      final readBy = _stringList(doc.data()['readBy']);
      if (readBy.contains(user.uid)) continue;
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  static Future<void> createBorrowNotifications({
    required String recordId,
    required String bookId,
    required String bookTitle,
    required String borrowerName,
    required String studentUid,
    required DateTime dueDate,
  }) async {
    await Future.wait([
      _createNotificationIfMissing(
        id: 'new_borrow_$recordId',
        recipientRole: 'librarian',
        type: AppNotificationType.newBorrow,
        title: 'New Borrow',
        body:
            '$borrowerName borrowed "$bookTitle". Due ${_formatDate(dueDate)}.',
        recordId: recordId,
        bookId: bookId,
      ),
      if (studentUid.isNotEmpty)
        _createNotificationIfMissing(
          id: 'borrow_confirmed_$recordId',
          recipientUid: studentUid,
          recipientRole: 'student',
          type: AppNotificationType.borrowConfirmed,
          title: 'Borrow Confirmed',
          body: '"$bookTitle" is due on ${_formatDate(dueDate)}.',
          recordId: recordId,
          bookId: bookId,
        ),
    ]);
  }

  static Future<void> createReturnNotification({
    required String recordId,
    required String bookId,
    required String bookTitle,
    required String studentUid,
  }) async {
    if (studentUid.isEmpty) return;

    await _createNotificationIfMissing(
      id: 'return_confirmed_$recordId',
      recipientUid: studentUid,
      recipientRole: 'student',
      type: AppNotificationType.returnConfirmed,
      title: 'Return Confirmed',
      body: '"$bookTitle" was marked as returned.',
      recordId: recordId,
      bookId: bookId,
    );
  }

  static Future<void> ensureOverdueNotification({
    required String recordId,
    required String bookId,
    required String bookTitle,
    required String borrowerName,
    required String studentUid,
    required DateTime dueDate,
    required String role,
  }) async {
    if (role == 'student' && studentUid.isEmpty) return;

    await _createNotificationIfMissing(
      id: 'overdue_${role}_$recordId',
      recipientUid: role == 'student' ? studentUid : null,
      recipientRole: role,
      type: AppNotificationType.overdue,
      title: 'Overdue Book',
      body: role == 'librarian'
          ? '$borrowerName has not returned "$bookTitle".'
          : '"$bookTitle" was due on ${_formatDate(dueDate)}.',
      recordId: recordId,
      bookId: bookId,
    );
  }

  static Future<void> ensureDueSoonNotification({
    required String recordId,
    required String bookId,
    required String bookTitle,
    required String studentUid,
    required DateTime dueDate,
    required int daysUntilDue,
  }) async {
    if (studentUid.isEmpty) return;
    if (daysUntilDue < 1 || daysUntilDue > 3) return;

    final dayText = daysUntilDue == 1 ? '1 day' : '$daysUntilDue days';

    await _createNotificationIfMissing(
      id: 'due_soon_${daysUntilDue}_student_$recordId',
      recipientUid: studentUid,
      recipientRole: 'student',
      type: AppNotificationType.dueSoon,
      title: 'Book Due Soon',
      body: '"$bookTitle" is due in $dayText, on ${_formatDate(dueDate)}.',
      recordId: recordId,
      bookId: bookId,
    );
  }

  static Future<void> _saveToken(String uid, String role, String token) async {
    await _firestore.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmTokens': FieldValue.arrayUnion([token]),
      'notificationRole': role,
      'notificationsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> _createNotificationIfMissing({
    required String id,
    required String recipientRole,
    required AppNotificationType type,
    required String title,
    required String body,
    String? recipientUid,
    String? recordId,
    String? bookId,
  }) async {
    final ref = _firestore.collection('notifications').doc(id);
    final existing = await ref.get();
    if (existing.exists) return;

    await ref.set({
      'recipientUid': recipientUid ?? '',
      'recipientRole': recipientRole,
      'type': _typeName(type),
      'title': title,
      'body': body,
      'recordId': recordId ?? '',
      'bookId': bookId ?? '',
      'readBy': <String>[],
      'pushSent': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

String _typeName(AppNotificationType type) {
  switch (type) {
    case AppNotificationType.newBorrow:
      return 'new_borrow';
    case AppNotificationType.borrowConfirmed:
      return 'borrow_confirmed';
    case AppNotificationType.returnConfirmed:
      return 'return_confirmed';
    case AppNotificationType.dueSoon:
      return 'due_soon';
    case AppNotificationType.overdue:
      return 'overdue';
    case AppNotificationType.general:
      return 'general';
  }
}

AppNotificationType _typeValue(Object? value) {
  final raw = _stringValue(value, fallback: 'general');
  switch (raw) {
    case 'new_borrow':
      return AppNotificationType.newBorrow;
    case 'borrow_confirmed':
      return AppNotificationType.borrowConfirmed;
    case 'return_confirmed':
      return AppNotificationType.returnConfirmed;
    case 'due_soon':
      return AppNotificationType.dueSoon;
    case 'overdue':
      return AppNotificationType.overdue;
    default:
      return AppNotificationType.general;
  }
}

String _formatDate(DateTime dt) {
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
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _stringValue(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return fallback;
}

String? _nullableString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value.whereType<String>().toList();
  }
  return const [];
}

DateTime _dateValue(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return DateTime.now();
}
