import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class BorrowService {
  // ---------------------------------------------------------------------------
  // QR Code generation
  // ---------------------------------------------------------------------------

  static Future<String> generateBorrowQrCode({
    required String bookId,
    required String bookTitle,
    required String studentId,
    required String studentName,
    required String studentUid,
    String scanMode = 'borrow',
  }) async {
    final payload = {
      'bookId': bookId,
      'bookTitle': bookTitle,
      'studentId': studentId,
      'studentUid': studentUid,
      'studentName': studentName,
      'scanMode': scanMode,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    return jsonEncode(payload);
  }

  static Future<String> generateReturnQrCode({
    required String bookId,
    required String bookTitle,
    required String studentId,
    required String studentName,
    required String studentUid,
  }) {
    return generateBorrowQrCode(
      bookId: bookId,
      bookTitle: bookTitle,
      studentId: studentId,
      studentName: studentName,
      studentUid: studentUid,
      scanMode: 'return',
    );
  }

  static Future<Map<String, dynamic>?> parseQrCode(String rawCode) async {
    try {
      final payload = jsonDecode(rawCode);
      if (payload is Map<String, dynamic>) {
        return payload;
      }
    } catch (_) {
      // If JSON parsing fails, return null
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Borrow: create borrow record + decrement availableCopies atomically
  // ---------------------------------------------------------------------------

  static Future<void> recordBorrow({
    required String bookId,
    required String bookTitle,
    required String bookAuthor,
    required String bookCoverUrl,
    required String bookIsbn,
    required String studentId,
    required String studentName,
    // Optional: pass studentUid so the record can be matched against Firebase
    // auth UID (same field used by _borrowedStateStream in book_details_page).
    String studentUid = '',
  }) async {
    final firestore = FirebaseFirestore.instance;
    final bookRef = firestore.collection('books').doc(bookId);
    final borrowRef = firestore.collection('borrow_records').doc();

    // Run both writes atomically so the copy counter is always consistent.
    await firestore.runTransaction((tx) async {
      final bookSnap = await tx.get(bookRef);

      // Read current copy counts from the book document.
      final data = bookSnap.data() ?? {};
      final totalCopies = _intValue(
        data['totalCopies'] ?? data['total_copies'] ?? data['copies'],
        fallback: 1,
      );
      final storedAvailable = _intValue(
        data['availableCopies'] ??
            data['available_copies'] ??
            data['available'],
        fallback: totalCopies,
      );

      if (storedAvailable <= 0) {
        throw Exception('No available copies left for "$bookTitle".');
      }

      final newAvailable = (storedAvailable - 1).clamp(0, totalCopies);

      // Decrement available copies on the book document.
      tx.set(bookRef, {
        'availableCopies': newAvailable,
        'available_copies': newAvailable,
        'available': newAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Create the borrow record.
      tx.set(borrowRef, {
        'bookId': bookId,
        'bookTitle': bookTitle,
        'title': bookTitle,
        'author': bookAuthor,
        'cover_url': bookCoverUrl,
        'coverUrl': bookCoverUrl,
        'isbn': bookIsbn,
        'studentId': studentId,
        'studentUid': studentUid,
        'borrowerName': studentName,
        'status': 'borrowed',
        'penaltyStatus': 'none',
        'scanMode': 'borrow',
        'borrowed_at': FieldValue.serverTimestamp(),
        'borrowedAt': FieldValue.serverTimestamp(),
        'scanned_at': FieldValue.serverTimestamp(),
        'scannedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Return: mark borrow record as returned + increment availableCopies
  // ---------------------------------------------------------------------------

  /// Finds the active borrow record for [bookId] + [studentId] (or [studentUid]),
  /// marks it as returned, and increments availableCopies on the book document.
  /// Returns the borrow record ID that was updated, or null if none was found.
  static Future<String?> recordReturn({
    required String bookId,
    required String studentId,
    String studentUid = '',
  }) async {
    final firestore = FirebaseFirestore.instance;

    // Find the active borrow record that belongs to this student.
    Query<Map<String, dynamic>> query = firestore
        .collection('borrow_records')
        .where('bookId', isEqualTo: bookId)
        .where('status', whereIn: ['borrowed', 'active']);

    final snapshot = await query.get();

    // Match by studentUid first, fall back to studentId.
    QueryDocumentSnapshot<Map<String, dynamic>>? matchedDoc;
    for (final doc in snapshot.docs) {
      final d = doc.data();
      if ((studentUid.isNotEmpty && d['studentUid'] == studentUid) ||
          d['studentId'] == studentId) {
        matchedDoc = doc;
        break;
      }
    }

    if (matchedDoc == null) return null;

    final borrowRef = matchedDoc.reference;
    final bookRef = firestore.collection('books').doc(bookId);

    await firestore.runTransaction((tx) async {
      final bookSnap = await tx.get(bookRef);
      final data = bookSnap.data() ?? {};

      final totalCopies = _intValue(
        data['totalCopies'] ?? data['total_copies'] ?? data['copies'],
        fallback: 1,
      );
      final storedAvailable = _intValue(
        data['availableCopies'] ??
            data['available_copies'] ??
            data['available'],
        fallback: 0,
      );

      final newAvailable = (storedAvailable + 1).clamp(0, totalCopies);

      // Increment available copies on the book document.
      tx.set(bookRef, {
        'availableCopies': newAvailable,
        'available_copies': newAvailable,
        'available': newAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Mark the borrow record as returned.
      tx.set(borrowRef, {
        'status': 'returned',
        'penaltyStatus': 'cleared',
        'scanMode': 'return',
        'overdueClearedAt': FieldValue.serverTimestamp(),
        'returned_at': FieldValue.serverTimestamp(),
        'returnedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return matchedDoc.id;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static int _intValue(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }
}
