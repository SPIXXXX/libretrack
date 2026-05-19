import 'package:cloud_firestore/cloud_firestore.dart';

class BorrowPenaltyStatus {
  const BorrowPenaltyStatus({
    required this.hasActiveOverdue,
    this.recordId = '',
    this.bookId = '',
    this.bookTitle = '',
    this.dueDate,
  });

  final bool hasActiveOverdue;
  final String recordId;
  final String bookId;
  final String bookTitle;
  final DateTime? dueDate;

  String get blockedBorrowMessage {
    final title = bookTitle.trim().isEmpty ? 'an overdue book' : '"$bookTitle"';
    return 'Return $title before borrowing another book.';
  }
}

class BorrowPenaltyService {
  const BorrowPenaltyService._();

  static final _records = FirebaseFirestore.instance.collection(
    'borrow_records',
  );

  static Future<BorrowPenaltyStatus> activePenaltyFor({
    required String studentUid,
    required String studentId,
  }) async {
    final docs = await _activeBorrowDocs(
      studentUid: studentUid,
      studentId: studentId,
    );
    return _statusFromDocs(docs);
  }

  static Stream<BorrowPenaltyStatus> activePenaltyStream({
    required String studentUid,
    required String studentId,
  }) {
    final normalizedUid = studentUid.trim();
    final normalizedId = studentId.trim();

    if (normalizedUid.isNotEmpty) {
      return _records
          .where('studentUid', isEqualTo: normalizedUid)
          .snapshots()
          .map((snapshot) => _statusFromDocs(snapshot.docs));
    }

    if (normalizedId.isNotEmpty) {
      return _records
          .where('studentId', isEqualTo: normalizedId)
          .snapshots()
          .map((snapshot) => _statusFromDocs(snapshot.docs));
    }

    return Stream.value(const BorrowPenaltyStatus(hasActiveOverdue: false));
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _activeBorrowDocs({
    required String studentUid,
    required String studentId,
  }) async {
    final normalizedUid = studentUid.trim();
    final normalizedId = studentId.trim();

    if (normalizedUid.isNotEmpty) {
      final snapshot = await _records
          .where('studentUid', isEqualTo: normalizedUid)
          .get();
      return snapshot.docs;
    }

    if (normalizedId.isNotEmpty) {
      final snapshot = await _records
          .where('studentId', isEqualTo: normalizedId)
          .get();
      return snapshot.docs;
    }

    return const [];
  }

  static BorrowPenaltyStatus _statusFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    QueryDocumentSnapshot<Map<String, dynamic>>? oldestOverdue;
    int oldestDueMillis = 0;

    for (final doc in docs) {
      final data = doc.data();
      if (!_isActive(data['status'])) continue;

      final dueMillis = _dueMillis(data);
      if (dueMillis == 0 || now <= dueMillis) continue;

      if (oldestOverdue == null || dueMillis < oldestDueMillis) {
        oldestOverdue = doc;
        oldestDueMillis = dueMillis;
      }
    }

    if (oldestOverdue == null) {
      return const BorrowPenaltyStatus(hasActiveOverdue: false);
    }

    final data = oldestOverdue.data();
    return BorrowPenaltyStatus(
      hasActiveOverdue: true,
      recordId: oldestOverdue.id,
      bookId: _stringValue(data['bookId']),
      bookTitle: _stringValue(data['bookTitle'] ?? data['title']),
      dueDate: DateTime.fromMillisecondsSinceEpoch(oldestDueMillis),
    );
  }

  static int _dueMillis(Map<String, dynamic> data) {
    final explicit = _timestampMillis(data['dueDate'] ?? data['due_date']);
    if (explicit != 0) return explicit;

    final borrowedMillis = _timestampMillis(
      data['borrowed_at'] ??
          data['borrowedAt'] ??
          data['scanned_at'] ??
          data['scannedAt'] ??
          data['created_at'] ??
          data['createdAt'],
    );
    if (borrowedMillis == 0) return 0;
    return borrowedMillis + const Duration(days: 7).inMilliseconds;
  }

  static bool _isActive(Object? value) {
    final status = _stringValue(value).toLowerCase();
    return status == 'active' || status == 'borrowed';
  }

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static String _stringValue(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return '';
  }
}
