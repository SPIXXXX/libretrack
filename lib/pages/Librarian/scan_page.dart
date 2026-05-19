import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/services/borrow_penalty_service.dart';
import 'package:libretrack/services/notification_service.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class LibrarianScanPage extends StatefulWidget {
  const LibrarianScanPage({super.key});

  @override
  State<LibrarianScanPage> createState() => _LibrarianScanPageState();
}

class _LibrarianScanPageState extends State<LibrarianScanPage> {
  bool _isSavingScan = false;
  bool _isClearingScans = false;

  Future<void> _confirmClearScans() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Clear Scan History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Are you sure you want to clear all recent scan records? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _clearScans();
  }

  Future<void> _clearScans() async {
    setState(() => _isClearingScans = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('borrow_records')
          .get();
      // Filter client-side: only update docs not already hidden.
      // Firestore's isNotEqualTo excludes docs where the field is absent,
      // so we fetch all and filter here instead.
      final toHide = snapshot.docs
          .where((doc) => doc.data()['hiddenInRecentScans'] != true)
          .toList();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in toHide) {
        batch.update(doc.reference, {'hiddenInRecentScans': true});
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan history cleared.'),
            backgroundColor: Color(0xFF2BA6A3),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearingScans = false);
    }
  }

  Stream<List<_ScanRecord>> _recentScanStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .where((doc) => doc.data()['hiddenInRecentScans'] != true)
              .map(_ScanRecord.fromDoc)
              .toList();
          records.sort(
            (a, b) => b.scannedAtMillis.compareTo(a.scannedAtMillis),
          );
          return records;
        });
  }

  Future<void> _startScan(_ScanMode mode) async {
    if (_isSavingScan) {
      return;
    }

    final rawCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _ScannerView(mode: mode),
        fullscreenDialog: true,
      ),
    );

    if (!mounted || rawCode == null || rawCode.trim().isEmpty) {
      return;
    }

    await _saveScan(mode, rawCode.trim());
  }

  Future<void> _saveScan(_ScanMode mode, String rawCode) async {
    setState(() => _isSavingScan = true);

    try {
      final payload = _ScanPayload.fromRaw(rawCode);
      final book = await _findBook(payload);
      final borrowerName = await _borrowerNameFor(payload);
      final user = FirebaseAuth.instance.currentUser;
      final records = FirebaseFirestore.instance.collection('borrow_records');

      if (mode == _ScanMode.borrow) {
        final activeRecord = await _findActiveBorrowRecord(book, payload);
        if (activeRecord != null) {
          throw Exception('This student already borrowed this book.');
        }

        final penalty = await BorrowPenaltyService.activePenaltyFor(
          studentUid: payload.studentUid ?? '',
          studentId: payload.studentId ?? '',
        );
        if (penalty.hasActiveOverdue) {
          throw Exception('Borrow blocked. ${penalty.blockedBorrowMessage}');
        }

        // Show confirm dialog — lets librarian review details and set due date.
        if (!mounted) return;
        final confirmed = await _showBorrowConfirmDialog(
          book: book,
          borrowerName: borrowerName,
        );
        if (confirmed == null) {
          // Librarian cancelled — abort silently (no error snackbar).
          setState(() => _isSavingScan = false);
          return;
        }

        final dueDate = confirmed;

        final bookRef = FirebaseFirestore.instance
            .collection('books')
            .doc(book.id);
        final recordRef = records.doc();
        final activeBorrowCount = await _activeBorrowCountFor(book.id);
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final bookSnapshot = await transaction.get(bookRef);
          if (!bookSnapshot.exists) {
            throw Exception('No book found for that scanned code.');
          }

          final bookData = bookSnapshot.data() ?? {};
          final totalCopies = _intValue(
            bookData['totalCopies'] ??
                bookData['total_copies'] ??
                bookData['copies'],
            fallback: 1,
          );
          final availableCopies = (totalCopies - activeBorrowCount)
              .clamp(0, totalCopies)
              .toInt();
          if (availableCopies <= 0) {
            throw Exception('No available copies left for this book.');
          }

          final nextAvailable = availableCopies - 1;
          transaction.update(bookRef, {
            'availableCopies': nextAvailable,
            'available_copies': nextAvailable,
            'available': nextAvailable,
            'updated_at': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(recordRef, {
            'bookId': book.id,
            'isbn': book.isbn,
            'bookTitle': book.title,
            'title': book.title,
            'author': book.author,
            'cover_url': book.coverUrl,
            'coverUrl': book.coverUrl,
            'studentId': payload.studentId ?? '',
            'studentUid': payload.studentUid ?? '',
            'borrowerName': borrowerName,
            'status': 'borrowed',
            'penaltyStatus': 'none',
            'scanMode': 'borrow',
            'rawScan': rawCode,
            'librarianId': user?.uid ?? '',
            'due_date': Timestamp.fromDate(dueDate),
            'dueDate': Timestamp.fromDate(dueDate),
            'borrowed_at': FieldValue.serverTimestamp(),
            'borrowedAt': FieldValue.serverTimestamp(),
            'scanned_at': FieldValue.serverTimestamp(),
            'scannedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
        unawaited(
          NotificationService.createBorrowNotifications(
            recordId: recordRef.id,
            bookId: book.id,
            bookTitle: book.title,
            borrowerName: borrowerName,
            studentUid: payload.studentUid ?? '',
            dueDate: dueDate,
          ),
        );
        _showSnackBar('Borrow confirmed. Due ${_formatDate(dueDate)}.');
      } else {
        final activeRecord = await _findActiveBorrowRecord(book, payload);
        if (activeRecord == null) {
          final returnRecord = await records.add({
            'bookId': book.id,
            'isbn': book.isbn,
            'bookTitle': book.title,
            'title': book.title,
            'author': book.author,
            'cover_url': book.coverUrl,
            'coverUrl': book.coverUrl,
            'studentId': payload.studentId ?? '',
            'studentUid': payload.studentUid ?? '',
            'borrowerName': borrowerName,
            'status': 'returned',
            'penaltyStatus': 'cleared',
            'scanMode': 'return',
            'rawScan': rawCode,
            'librarianId': user?.uid ?? '',
            'returned_at': FieldValue.serverTimestamp(),
            'returnedAt': FieldValue.serverTimestamp(),
            'scanned_at': FieldValue.serverTimestamp(),
            'scannedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          unawaited(
            NotificationService.createReturnNotification(
              recordId: returnRecord.id,
              bookId: book.id,
              bookTitle: book.title,
              studentUid: payload.studentUid ?? '',
            ),
          );
        } else {
          final bookRef = FirebaseFirestore.instance
              .collection('books')
              .doc(book.id);
          final activeBorrowCount = await _activeBorrowCountFor(book.id);
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            final activeSnapshot = await transaction.get(
              activeRecord.reference,
            );
            final activeData = activeSnapshot.data();
            final status = _stringValue(activeData?['status'])?.toLowerCase();
            if (status != 'active' && status != 'borrowed') {
              throw Exception('This borrow record was already returned.');
            }

            final bookSnapshot = await transaction.get(bookRef);
            final bookData = bookSnapshot.data() ?? {};
            final totalCopies = _intValue(
              bookData['totalCopies'] ??
                  bookData['total_copies'] ??
                  bookData['copies'],
              fallback: 1,
            );
            final activeAfterReturn = (activeBorrowCount - 1)
                .clamp(0, totalCopies)
                .toInt();
            final nextAvailable = (totalCopies - activeAfterReturn)
                .clamp(0, totalCopies)
                .toInt();

            transaction.update(bookRef, {
              'availableCopies': nextAvailable,
              'available_copies': nextAvailable,
              'available': nextAvailable,
              'updated_at': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            transaction.update(activeRecord.reference, {
              'status': 'returned',
              'penaltyStatus': 'cleared',
              'scanMode': 'return',
              'returnRawScan': rawCode,
              'returnedBy': user?.uid ?? '',
              'overdueClearedAt': FieldValue.serverTimestamp(),
              'returned_at': FieldValue.serverTimestamp(),
              'returnedAt': FieldValue.serverTimestamp(),
              'scanned_at': FieldValue.serverTimestamp(),
              'scannedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          });
          unawaited(
            NotificationService.createReturnNotification(
              recordId: activeRecord.id,
              bookId: book.id,
              bookTitle: book.title,
              studentUid: payload.studentUid ?? '',
            ),
          );
        }
        _showSnackBar('Return QR scanned successfully.');
      }
    } catch (e) {
      _showSnackBar(
        e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingScan = false);
      }
    }
  }

  Future<_ScannedBook> _findBook(_ScanPayload payload) async {
    final books = FirebaseFirestore.instance.collection('books');

    final directIds = <String>{
      if (payload.bookId != null) payload.bookId!,
      payload.raw,
    }.where((value) => value.trim().isNotEmpty);

    for (final id in directIds) {
      final snapshot = await books.doc(id).get();
      if (snapshot.exists && snapshot.data() != null) {
        return _ScannedBook.fromDoc(snapshot);
      }
    }

    final lookupValues = <String>{
      if (payload.isbn != null) payload.isbn!,
      payload.raw,
    }.where((value) => value.trim().isNotEmpty).toList();

    for (final value in lookupValues) {
      final byIsbn = await books.where('isbn', isEqualTo: value).limit(1).get();
      if (byIsbn.docs.isNotEmpty) {
        return _ScannedBook.fromDoc(byIsbn.docs.first);
      }

      final byBarcode = await books
          .where('barcode', isEqualTo: value)
          .limit(1)
          .get();
      if (byBarcode.docs.isNotEmpty) {
        return _ScannedBook.fromDoc(byBarcode.docs.first);
      }

      final byQrCode = await books
          .where('qrCode', isEqualTo: value)
          .limit(1)
          .get();
      if (byQrCode.docs.isNotEmpty) {
        return _ScannedBook.fromDoc(byQrCode.docs.first);
      }
    }

    throw Exception('No book found for that scanned code.');
  }

  Future<String> _borrowerNameFor(_ScanPayload payload) async {
    if (payload.borrowerName != null && payload.borrowerName!.isNotEmpty) {
      return payload.borrowerName!;
    }

    final studentUid = payload.studentUid;
    if (studentUid != null && studentUid.trim().isNotEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(studentUid)
          .get();
      final docName = _stringValue(userDoc.data()?['name']);
      if (docName != null) {
        return docName;
      }
    }

    final studentId = payload.studentId;
    if (studentId == null || studentId.trim().isEmpty) {
      return 'Scanned borrower';
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(studentId)
        .get();
    final docName = _stringValue(userDoc.data()?['name']);
    if (docName != null) {
      return docName;
    }

    final bySchoolId = await FirebaseFirestore.instance
        .collection('users')
        .where('schoolId', isEqualTo: studentId)
        .limit(1)
        .get();
    if (bySchoolId.docs.isNotEmpty) {
      final name = _stringValue(bySchoolId.docs.first.data()['name']);
      if (name != null) {
        return name;
      }
    }

    return studentId;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findActiveBorrowRecord(
    _ScannedBook book,
    _ScanPayload payload,
  ) async {
    final byBook = await FirebaseFirestore.instance
        .collection('borrow_records')
        .where('bookId', isEqualTo: book.id)
        .get();

    final activeByBook = _latestActiveRecord(byBook.docs, payload);
    if (activeByBook != null) {
      return activeByBook;
    }

    if (book.isbn.isEmpty) {
      return null;
    }

    final byIsbn = await FirebaseFirestore.instance
        .collection('borrow_records')
        .where('isbn', isEqualTo: book.isbn)
        .get();
    return _latestActiveRecord(byIsbn.docs, payload);
  }

  Future<int> _activeBorrowCountFor(String bookId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('borrow_records')
        .where('bookId', isEqualTo: bookId)
        .where('status', whereIn: ['active', 'borrowed'])
        .get();
    return snapshot.docs.length;
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _latestActiveRecord(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    _ScanPayload payload,
  ) {
    final active = docs.where((doc) {
      final data = doc.data();
      final status = _stringValue(data['status'])?.toLowerCase();
      final isActive = status == 'active' || status == 'borrowed';
      if (!isActive) {
        return false;
      }

      final payloadUid = payload.studentUid;
      final payloadStudentId = payload.studentId;
      if (payloadUid == null && payloadStudentId == null) {
        return true;
      }

      final recordUid = _stringValue(data['studentUid']);
      final recordStudentId = _stringValue(data['studentId']);
      return (payloadUid != null && payloadUid == recordUid) ||
          (payloadStudentId != null && payloadStudentId == recordStudentId);
    }).toList();

    if (active.isEmpty) {
      return null;
    }

    active.sort((a, b) {
      final aTime = _timestampMillis(
        a.data()['scanned_at'] ??
            a.data()['scannedAt'] ??
            a.data()['borrowed_at'] ??
            a.data()['borrowedAt'] ??
            a.data()['createdAt'],
      );
      final bTime = _timestampMillis(
        b.data()['scanned_at'] ??
            b.data()['scannedAt'] ??
            b.data()['borrowed_at'] ??
            b.data()['borrowedAt'] ??
            b.data()['createdAt'],
      );
      return bTime.compareTo(aTime);
    });

    return active.first;
  }

  /// Shows a confirmation dialog before recording a borrow.
  /// The librarian sees book + student details and can adjust the due date.
  /// Returns the chosen [DateTime] on confirm, or null if cancelled.
  Future<DateTime?> _showBorrowConfirmDialog({
    required _ScannedBook book,
    required String borrowerName,
  }) async {
    DateTime selectedDue = _endOfDay(
      DateTime.now().add(const Duration(days: 14)),
    );

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
              contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              title: const Row(
                children: [
                  Icon(
                    Icons.add_task_rounded,
                    color: Color(0xFF4B23C6),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Confirm Borrow',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF11121A),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  // Book info row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: SizedBox(
                          width: 46,
                          height: 62,
                          child: book.coverUrl.isNotEmpty
                              ? Image.network(
                                  book.coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _ConfirmCoverFallback(title: book.title),
                                )
                              : _ConfirmCoverFallback(title: book.title),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF11121A),
                                height: 1.2,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              book.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Borrower row
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EDFF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF4B23C6),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Borrower',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6B7280),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              borrowerName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF11121A),
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Due date row — tappable
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDue,
                        firstDate: _startOfDay(DateTime.now()),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: Color(0xFF4B23C6),
                              onPrimary: Colors.white,
                              surface: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDue = _endOfDay(picked));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD7F4EF),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFF17817F),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Due Date',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _formatDate(selectedDue),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF11121A),
                                    letterSpacing: 0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.edit_calendar_rounded,
                            color: Color(0xFF6B7280),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selectedDue),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4B23C6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Confirm Borrow',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : const Color(0xFF2BA6A3),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refreshScans() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF2BA6A3),
      onRefresh: _refreshScans,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 44, 14, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Expanded(
                      child: _ScanActionCard(
                        icon: Icons.add_task_rounded,
                        accentColor: const Color(0xFF4B23C6),
                        label: 'Scan Borrow',
                        subtitle: 'Create loan',
                        isBusy: _isSavingScan,
                        onTap: () => _startScan(_ScanMode.borrow),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _ScanActionCard(
                        icon: Icons.assignment_return_rounded,
                        accentColor: const Color(0xFF19A7A1),
                        label: 'Scan Return',
                        subtitle: 'Close loan',
                        isBusy: _isSavingScan,
                        onTap: () => _startScan(_ScanMode.returnBook),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 34),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent Scans',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (_isClearingScans)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFE53935),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: _confirmClearScans,
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFE53935),
                          size: 28,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 40),
                _buildRecentScanList(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentScanList() {
    return StreamBuilder<List<_ScanRecord>>(
      stream: _recentScanStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _ScanMessage(
            icon: Icons.error_outline_rounded,
            message: 'Could not load recent scans.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF2BA6A3)),
            ),
          );
        }

        final scans = snapshot.data ?? [];
        if (scans.isEmpty) {
          return const _ScanMessage(
            icon: Icons.qr_code_scanner_rounded,
            message: 'No recent scans yet.',
          );
        }

        return Column(
          children: scans
              .take(8)
              .map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _RecentScanCard(record: record),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ScannerView extends StatefulWidget {
  const _ScannerView({required this.mode});

  final _ScanMode mode;

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }

    final code = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;

    if (code == null) {
      return;
    }

    _handled = true;
    await _controller.stop();

    if (!mounted) {
      return;
    }

    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.mode == _ScanMode.borrow
        ? const Color(0xFF4B23C6)
        : const Color(0xFF19A7A1);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _handleDetect),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ScannerOverlayPainter(accent)),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: 14,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Close scanner',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.mode == _ScanMode.borrow
                          ? 'Scan Borrow Code'
                          : 'Scan Return Code',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _controller.toggleTorch,
                    icon: const Icon(
                      Icons.flash_on_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Toggle flashlight',
                  ),
                  IconButton(
                    onPressed: _controller.switchCamera,
                    icon: const Icon(
                      Icons.cameraswitch_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Switch camera',
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 34,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Place the QR code, ISBN, or barcode inside the frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.3,
                    letterSpacing: 0,
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

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final frameSize = size.width * 0.72;
    final frameRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: frameSize,
      height: frameSize,
    );
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.48);
    final clearPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(24)));

    canvas.drawPath(clearPath, overlayPaint);

    final cornerPaint = Paint()
      ..color = accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const cornerLength = 34.0;

    for (final corner in [
      frameRect.topLeft,
      frameRect.topRight,
      frameRect.bottomLeft,
      frameRect.bottomRight,
    ]) {
      final horizontalDirection = corner.dx == frameRect.left
          ? cornerLength
          : -cornerLength;
      final verticalDirection = corner.dy == frameRect.top
          ? cornerLength
          : -cornerLength;
      canvas.drawLine(
        corner,
        Offset(corner.dx + horizontalDirection, corner.dy),
        cornerPaint,
      );
      canvas.drawLine(
        corner,
        Offset(corner.dx, corner.dy + verticalDirection),
        cornerPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

class _ScanActionCard extends StatelessWidget {
  const _ScanActionCard({
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.subtitle,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String label;
  final String subtitle;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      child: InkWell(
        onTap: isBusy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 150,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 29),
              ),
              const SizedBox(height: 17),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF11121A),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentScanCard extends StatelessWidget {
  const _RecentScanCard({required this.record});

  final _ScanRecord record;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Container(
        height: 92,
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 70,
                height: 78,
                child: record.coverUrl.isEmpty
                    ? Container(
                        color: Colors.black,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      )
                    : Image.network(
                        record.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.menu_book_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.bookTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF11121A),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    record.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF11121A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    record.borrowerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF565B66),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              constraints: const BoxConstraints(minWidth: 74),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                record.statusLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: record.statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmCoverFallback extends StatelessWidget {
  const _ConfirmCoverFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    const palettes = [
      [Color(0xFF1A237E), Color(0xFF2BA6A3)],
      [Color(0xFF31473A), Color(0xFFE2A346)],
      [Color(0xFF69353F), Color(0xFF4B8E8D)],
      [Color(0xFF243B53), Color(0xFF9C6644)],
    ];
    final idx = title.codeUnits.fold<int>(0, (a, b) => a + b) % palettes.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palettes[idx],
        ),
      ),
      child: const Center(
        child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}

class _ScanMessage extends StatelessWidget {
  const _ScanMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2BA6A3), size: 32),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF565B66),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanPayload {
  const _ScanPayload({
    required this.raw,
    this.bookId,
    this.isbn,
    this.studentId,
    this.studentUid,
    this.borrowerName,
  });

  final String raw;
  final String? bookId;
  final String? isbn;
  final String? studentId;
  final String? studentUid;
  final String? borrowerName;

  factory _ScanPayload.fromRaw(String raw) {
    final value = raw.trim();
    final jsonPayload = _jsonMap(value);
    if (jsonPayload != null) {
      return _ScanPayload(
        raw: value,
        bookId: _firstString(jsonPayload, ['bookId', 'book_id', 'id']),
        isbn: _firstString(jsonPayload, ['isbn', 'barcode']),
        studentId: _firstString(jsonPayload, [
          'studentId',
          'student_id',
          'schoolId',
          'borrowerId',
        ]),
        studentUid: _firstString(jsonPayload, [
          'studentUid',
          'student_uid',
          'uid',
          'borrowerUid',
        ]),
        borrowerName: _firstString(jsonPayload, [
          'studentName',
          'borrowerName',
          'name',
        ]),
      );
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      final params = uri.queryParameters;
      return _ScanPayload(
        raw: value,
        bookId:
            params['bookId'] ??
            params['book_id'] ??
            params['id'] ??
            params['b'],
        isbn: params['isbn'] ?? params['barcode'],
        studentId:
            params['studentId'] ??
            params['student_id'] ??
            params['schoolId'] ??
            params['borrowerId'],
        studentUid:
            params['studentUid'] ??
            params['student_uid'] ??
            params['uid'] ??
            params['borrowerUid'],
        borrowerName:
            params['studentName'] ?? params['borrowerName'] ?? params['name'],
      );
    }

    return _ScanPayload(raw: value);
  }

  static Map<String, dynamic>? _jsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _firstString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }
}

class _ScannedBook {
  const _ScannedBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.isbn,
  });

  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String isbn;

  factory _ScannedBook.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return _ScannedBook(
      id: doc.id,
      title: _stringValue(data['title']) ?? 'Untitled Book',
      author: _stringValue(data['author']) ?? 'Unknown author',
      coverUrl:
          _stringValue(data['cover_url']) ??
          _stringValue(data['coverUrl']) ??
          '',
      isbn: _stringValue(data['isbn']) ?? '',
    );
  }
}

class _ScanRecord {
  const _ScanRecord({
    required this.bookTitle,
    required this.author,
    required this.borrowerName,
    required this.coverUrl,
    required this.scannedAtMillis,
    required this.status,
  });

  final String bookTitle;
  final String author;
  final String borrowerName;
  final String coverUrl;
  final int scannedAtMillis;
  final String status;

  String get statusLabel {
    if (status == 'returned' || status == 'return') {
      return 'Returned';
    }
    return 'Borrowed';
  }

  Color get statusColor {
    if (status == 'returned' || status == 'return') {
      return const Color(0xFF4B23C6);
    }
    return const Color(0xFF19A7A1);
  }

  factory _ScanRecord.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _ScanRecord(
      bookTitle:
          _stringValue(data['bookTitle'] ?? data['title']) ?? 'Untitled Book',
      author: _stringValue(data['author']) ?? 'Unknown author',
      borrowerName:
          _stringValue(
            data['borrowerName'] ?? data['studentName'] ?? data['name'],
          ) ??
          'Student borrower',
      coverUrl: _stringValue(data['cover_url'] ?? data['coverUrl']) ?? '',
      scannedAtMillis: _timestampMillis(
        data['scanned_at'] ??
            data['scannedAt'] ??
            data['returned_at'] ??
            data['returnedAt'] ??
            data['borrowed_at'] ??
            data['borrowedAt'] ??
            data['created_at'] ??
            data['createdAt'],
      ),
      status: (_stringValue(data['status']) ?? 'borrowed').toLowerCase(),
    );
  }
}

enum _ScanMode { borrow, returnBook }

String? _stringValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

int _timestampMillis(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }
  return 0;
}

int _intValue(Object? value, {required int fallback}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}
