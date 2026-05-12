// lib/services/fcm_navigation_service.dart
//
// Handles notification TAPS in two states:
//   • Terminated  → getInitialMessage()   (app cold-starts from a tap)
//   • Background  → onMessageOpenedApp    (app resumes from a tap)
//
// Foreground messages are already handled inside librarian_page.dart (_initFcm).
//
// CALL: FcmNavigationService.init(navigatorKey) in main.dart after initializeApp().

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Student/book_details_page.dart';

class FcmNavigationService {
  FcmNavigationService._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// Register once in main.dart before runApp().
  static void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;

    // App was TERMINATED — user tapped the notification to open the app
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        // Delay so the widget tree is fully built before we push any routes
        Future.delayed(const Duration(milliseconds: 600), () {
          _handleTap(message);
        });
      }
    });

    // App was in BACKGROUND — user tapped the notification to resume
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
  }

  // ---------------------------------------------------------------------------
  // Route based on notification type
  // ---------------------------------------------------------------------------

  static Future<void> _handleTap(RemoteMessage message) async {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return;

    final data = message.data;
    final type = data['type'] as String? ?? '';
    final role = data['role'] as String? ?? '';
    final bookId = data['bookId'] as String?;

    switch (type) {
      // Librarian: a student borrowed a book
      case 'new_borrow':
        if (role == 'librarian') {
          // Pop everything back to LibrarianPage (always the root for librarians)
          nav.popUntil((route) => route.isFirst);
        }

      // Student: their borrow was confirmed by the librarian
      case 'borrow_confirmed':
        if (role == 'student' && bookId != null) {
          await _pushBookDetails(nav, bookId);
        } else {
          nav.popUntil((route) => route.isFirst);
        }

      // Student or librarian: a book is overdue
      case 'overdue':
        if (role == 'student' && bookId != null) {
          await _pushBookDetails(nav, bookId);
        } else {
          // Librarian: just surface the app root (LibrarianPage)
          nav.popUntil((route) => route.isFirst);
        }

      // Student: their return was confirmed
      case 'return_confirmed':
        if (role == 'student') {
          nav.popUntil((route) => route.isFirst);
        }

      // Unknown type: just surface the app
      default:
        nav.popUntil((route) => route.isFirst);
    }
  }

  // ---------------------------------------------------------------------------
  // Helper: fetch book from Firestore then push StudentBookDetailsPage
  // ---------------------------------------------------------------------------

  static Future<void> _pushBookDetails(
    NavigatorState nav,
    String bookId,
  ) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('books')
          .doc(bookId)
          .get();

      if (!doc.exists) return;

      final data = doc.data();

      if (data == null) return;

      final book = StudentBookDetailsData.fromMap(id: doc.id, data: data);
      nav.push(
        MaterialPageRoute(builder: (_) => StudentBookDetailsPage(book: book)),
      );
    } catch (e) {
      debugPrint('[FCM] Failed to push book details: $e');
    }
  }
}
