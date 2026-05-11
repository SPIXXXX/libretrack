import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:libretrack/services/borrow_service.dart';
import 'package:libretrack/services/student_library_service.dart';
import 'package:libretrack/widgets/borrow_qr_dialog.dart';

/// QR Code Generation & Flow Summary:
/// ====================================
/// Each student gets a UNIQUE QR code for each book transaction:
/// - Alice borrowing Book A = Different QR than Bob borrowing Book A
/// - Alice borrowing Book A now = Different QR than Alice borrowing Book A tomorrow
/// - QR contains: bookId + studentId + uid + timestamp + action (borrow/return)
/// - Backend validates QR when librarian scans it
///
/// Data Flow:
/// 1. StudentBookDetailsPage loads → Fetches current student info (uid, studentId, name)
/// 2. User clicks Borrow → Calls BorrowService.generateBorrowQrCode() with student+book data
/// 3. Backend generates unique QR string → Returns to UI
/// 4. UI displays QR in BorrowQrDialog
/// 5. Librarian scans QR → Backend validates student+book+action → Updates Firestore
/// 6. StreamBuilder detects state change → UI toggles button from Borrow to Return

/// StudentBookDetailsData: Model class that holds book metadata fetched from Firestore
/// This is the UI representation of a book with details like title, author, ISBN, etc.
class StudentBookDetailsData {
  const StudentBookDetailsData({
    required this.id, // Unique book ID in Firestore
    required this.title,
    required this.author,
    required this.publisher,
    required this.publicationDate,
    required this.edition,
    required this.language,
    required this.pages,
    required this.summary,
    required this.isbn,
    required this.category,
    required this.coverUrl,
    required this.pdfUrl,
    required this.totalCopies,
    required this.availableCopies,
  });

  factory StudentBookDetailsData.fromMap({
    required String id,
    required Map<String, dynamic> data,
    int? activeBorrowCount,
    // Pass the previously-known totalCopies so we never fall back to 0
    // when the field happens to be absent from a partial snapshot.
    int knownTotalCopies = 1,
  }) {
    final totalCopies = _intValue(
      data['totalCopies'] ??
          data['total_copies'] ??
          data['copies'] ??
          data['bookCount'] ??
          data['book_count'],
      fallback: knownTotalCopies,
    );
    final storedAvailableCopies = _intValue(
      data['availableCopies'] ??
          data['available_copies'] ??
          data['available'] ??
          data['availableCount'] ??
          data['available_count'],
      fallback: totalCopies,
    );
    final availableCopies = activeBorrowCount == null
        ? storedAvailableCopies
        : (totalCopies - activeBorrowCount).clamp(0, totalCopies).toInt();

    return StudentBookDetailsData(
      id: id,
      title: _stringValue(data['title'], fallback: 'Untitled Book'),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
      publisher: _stringValue(data['publisher'], fallback: 'Unknown publisher'),
      publicationDate: _stringValue(
        data['publication_date'] ??
            data['publicationDate'] ??
            data['publication_year'] ??
            data['publicationYear'],
        fallback: 'Not listed',
      ),
      edition: _stringValue(data['edition'], fallback: 'Not listed'),
      language: _stringValue(data['language'], fallback: 'Not listed'),
      pages: _stringValue(data['pages'], fallback: 'Not listed'),
      summary: _stringValue(
        data['summary'] ?? data['description'],
        fallback: 'No summary available for this book yet.',
      ),
      isbn: _stringValue(data['isbn'], fallback: ''),
      category: _stringValue(
        data['category'] ??
            data['classification_category'] ??
            data['classificationCategory'],
        fallback: 'General',
      ),
      coverUrl: _stringValue(
        data['cover_url'] ?? data['coverUrl'],
        fallback: '',
      ),
      pdfUrl: _stringValue(data['pdf_url'] ?? data['pdfUrl'], fallback: ''),
      totalCopies: totalCopies,
      availableCopies: availableCopies,
    );
  }

  final String id;
  final String title;
  final String author;
  final String publisher;
  final String publicationDate;
  final String edition;
  final String language;
  final String pages;
  final String summary;
  final String isbn;
  final String category;
  final String coverUrl;
  final String pdfUrl;
  final int totalCopies;
  final int availableCopies;

  bool get hasAvailableCopies => availableCopies > 0;

  String get availabilityLabel =>
      '${availableCopies.clamp(0, totalCopies)}/$totalCopies available';

  String get displayPages {
    if (pages == 'Not listed') {
      return pages;
    }
    final lower = pages.toLowerCase();
    return lower.contains('page') ? pages : '~$pages pages';
  }

  static String _stringValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) {
      return value.toString();
    }
    return fallback;
  }

  static int _intValue(Object? value, {required int fallback}) {
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
}

/// StudentBookDetailsPage: Displays detailed info about a book and handles borrow/return flow
/// Flow: User views book details → Clicks Borrow/Return → Generates unique QR code → Shows to librarian
class StudentBookDetailsPage extends StatefulWidget {
  const StudentBookDetailsPage({super.key, required this.book, this.onBorrow});

  final StudentBookDetailsData book; // Book metadata passed from parent
  final VoidCallback? onBorrow; // Callback when borrow action completes

  @override
  State<StudentBookDetailsPage> createState() => _StudentBookDetailsPageState();
}

class _StudentBookDetailsPageState extends State<StudentBookDetailsPage> {
  int _tabIndex = 0;
  late final Future<_StudentInfo> _studentInfoFuture;
  late final Stream<StudentBookDetailsData> _bookStreamCached;

  @override
  void initState() {
    super.initState();
    _studentInfoFuture = _loadStudentInfo();
    // Cache stream so it is never recreated on rebuild. If created inline in
    // build(), every rebuild makes a new stream that starts with no data,
    // causing the stale widget.book fallback to flash with wrong values.
    _bookStreamCached = _bookStream().asBroadcastStream();
  }

  /// Fetch current logged-in student's info from Firebase
  /// Returns: uid (Firebase auth ID), studentId (school ID), name
  /// This info is used to generate unique QR codes for this specific student
  Future<_StudentInfo> _loadStudentInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Not logged in');
    }

    // Query Firestore 'users' collection to get student's profile data (name, schoolId, etc)
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() ?? {};

    // Return student info object containing uid, studentId, and name
    // These fields are used in QR code generation to make it unique per student+book
    return _StudentInfo(
      uid: user.uid,
      studentId: StudentBookDetailsData._stringValue(
        userData['schoolId'] ?? user.uid,
        fallback: user.uid,
      ),
      name: StudentBookDetailsData._stringValue(
        userData['name'],
        fallback: 'Student',
      ),
    );
  }

  /// Real-time stream that checks if current student has already borrowed this book
  /// Backend logic: Query borrow_records where bookId matches AND status is 'active'/'borrowed'
  /// Returns: true if student has active borrow record, false otherwise
  /// Used to toggle 'Borrow' button to 'Return' if book is already borrowed
  Stream<bool> _borrowedStateStream(_StudentInfo student) {
    // Listen to Firestore borrow_records collection for changes (real-time updates)
    try {
      return FirebaseFirestore.instance
          .collection('borrow_records')
          .where('bookId', isEqualTo: widget.book.id)
          .where('status', whereIn: ['active', 'borrowed'])
          .snapshots() // Real-time stream
          .map((snapshot) {
            // Check if ANY active borrow record belongs to THIS specific student
            // Match by UID first (most reliable), then by studentId
            final hasBorrowed = snapshot.docs.any((doc) {
              final data = doc.data();
              final recordUid = data['studentUid'] as String?;
              final recordStudentId = data['studentId'] as String?;

              // Check UID match - student must have borrowed with their Firebase UID
              final uidMatches =
                  recordUid != null &&
                  recordUid.isNotEmpty &&
                  recordUid == student.uid;

              return uidMatches;
            });

            return hasBorrowed;
          })
          .handleError((_) => false); // Default to false on error
    } catch (e) {
      // If stream creation fails, return false (book not borrowed)
      return Stream<bool>.value(false);
    }
  }

  // Listens to both the book document and active borrow_records.
  // Emits as soon as the book document arrives, then stays live.
  Stream<StudentBookDetailsData> _bookStream() {
    try {
      // Create a stream that emits when borrow_records change
      final borrowStream = FirebaseFirestore.instance
          .collection('borrow_records')
          .where('bookId', isEqualTo: widget.book.id)
          .where('status', whereIn: ['active', 'borrowed'])
          .snapshots()
          .map((s) => s.docs.length)
          .handleError(
            (_) => 0,
          ); // If error reading borrow_records, assume 0 active borrows

      // For each borrow count, get the latest book data
      return borrowStream.asyncExpand((activeBorrowCount) {
        return FirebaseFirestore.instance
            .collection('books')
            .doc(widget.book.id)
            .snapshots()
            .map((bookSnap) {
              final data = bookSnap.data();
              if (data == null) return widget.book;
              return StudentBookDetailsData.fromMap(
                id: bookSnap.id,
                data: data,
                activeBorrowCount: activeBorrowCount,
                knownTotalCopies: widget.book.totalCopies > 0
                    ? widget.book.totalCopies
                    : 1,
              );
            })
            .handleError(
              (_) => widget.book,
            ); // If error reading book, use fallback book data
      });
    } catch (e) {
      // If creating the stream itself fails, return a stream that emits the current book
      return Stream<StudentBookDetailsData>.value(widget.book);
    }
  }

  /// QR Code Generation Flow:
  /// 1. User clicks Borrow/Return button
  /// 2. This method calls BorrowService backend to generate unique QR code
  /// 3. QR code is unique per: student (uid/studentId) + book (bookId) + action (borrow/return)
  /// 4. Each QR is different for each user-book combination (not shared between students)
  /// 5. QR contains encrypted transaction data that backend verifies when scanned
  Future<void> _showBorrowQr({
    required _StudentInfo student,
    required bool isReturn,
  }) async {
    try {
      if (!isReturn) {
        final bookSnap = await FirebaseFirestore.instance
            .collection('books')
            .doc(widget.book.id)
            .get();
        final borrowSnap = await FirebaseFirestore.instance
            .collection('borrow_records')
            .where('bookId', isEqualTo: widget.book.id)
            .where('status', whereIn: ['active', 'borrowed'])
            .get();
        final latestData = bookSnap.data();
        if (latestData != null) {
          final latestAvailability = StudentBookDetailsData.fromMap(
            id: bookSnap.id,
            data: latestData,
            activeBorrowCount: borrowSnap.docs.length,
          );
          if (!latestAvailability.hasAvailableCopies) {
            _showError('No available copies left.');
            return;
          }
        }
      }

      // Call backend service to generate unique QR code
      // IMPORTANT: QR code is unique per student+book+action combination
      // Each user gets their own QR for the same book (not shared)
      final qrData = isReturn
          ? await BorrowService.generateReturnQrCode(
              bookId: widget.book.id, // Specific book ID
              bookTitle: widget.book.title,
              studentId: student
                  .studentId, // Specific student ID - makes QR unique per student
              studentName: student.name,
              studentUid: student
                  .uid, // Firebase UID - another identifier for this student
            )
          : await BorrowService.generateBorrowQrCode(
              bookId: widget.book.id, // Specific book ID
              bookTitle: widget.book.title,
              studentId: student
                  .studentId, // Specific student ID - makes QR unique per student
              studentName: student.name,
              studentUid: student
                  .uid, // Firebase UID - another identifier for this student
            );

      if (!mounted) return;

      // Display the generated QR code to user in a bottom sheet modal
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible:
            false, // User must close dialog (can't dismiss by tapping outside)
        enableDrag: false, // Can't drag to close
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => BorrowQrDialog(
          qrData:
              qrData, // Unique QR string from backend (contains student+book+action data)
          bookTitle: widget.book.title,
          studentName: student.name,
          title: isReturn ? 'Return QR code' : 'Borrow QR code',
          instruction: isReturn
              ? 'Show this code to the librarian. The return is saved only after the QR scan is successful.'
              : 'Show this code to the librarian. The borrow record is saved only after the QR scan is successful.',
        ),
      );
    } catch (e) {
      _showError('Error: ${e.toString()}');
    }
  }

  /// Save/remove book from student's favorite list in Firestore
  /// Updates user's personal library with book categories
  Future<void> _toggleFavorite(StudentBookLibraryEntry? entry) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Not logged in');
      return;
    }

    try {
      // If book is already favorited, remove it
      if (entry?.isFavorite == true) {
        // Call backend to remove from user's library
        await StudentLibraryService.removeBook(
          uid: user.uid,
          bookId: widget.book.id,
        );
        return;
      }

      // Fetch available categories from backend, let user pick which to add book to
      final categories = await StudentLibraryService.fetchCategories(user.uid);
      final selectedCategories = categories.length > 1
          ? await _showCategoryPicker(
              categories,
            ) // Show category picker if multiple exist
          : [StudentLibraryService.favorites]; // Otherwise default to Favorites

      if (selectedCategories == null || selectedCategories.isEmpty) {
        return; // User canceled category selection
      }

      // Save book to user's library under selected categories
      await StudentLibraryService.saveBookCategories(
        uid: user.uid,
        bookId: widget.book.id,
        categories: selectedCategories,
      );
    } catch (e) {
      _showError('Could not update favorites: ${e.toString()}');
    }
  }

  Future<List<String>?> _showCategoryPicker(List<String> categories) {
    final selected = <String>{StudentLibraryService.favorites};

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add to category',
                            style: TextStyle(
                              color: Color(0xFF121926),
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _CategoryPickerButton(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: categories.map((category) {
                        final isFavorites =
                            category == StudentLibraryService.favorites;
                        final isSelected = selected.contains(category);
                        return _CategoryChoiceChip(
                          label: category,
                          selected: isSelected,
                          onTap: () {
                            if (isFavorites) {
                              return;
                            }

                            setSheetState(() {
                              if (isSelected) {
                                selected.remove(category);
                              } else {
                                selected.add(category);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context, selected.toList());
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2BA6A3),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get current logged-in user
    final user = FirebaseAuth.instance.currentUser;
    // Stream book's favorite/library status (updates in real-time when user adds/removes from favorites)
    final entryStream = user == null
        ? Stream<StudentBookLibraryEntry?>.value(null) // No user logged in
        : StudentLibraryService.bookEntryStream(
            uid: user.uid, // Query this user's library entries
            bookId: widget.book.id, // For this specific book
          );

    // Listen to real-time updates of book's favorite status
    return StreamBuilder<StudentBookLibraryEntry?>(
      stream: entryStream,
      builder: (context, librarySnapshot) {
        // libraryEntry contains favorite status and categories for this book+user
        final libraryEntry = librarySnapshot.data;

        return Scaffold(
          backgroundColor: const Color(0xFFE3E7EB),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(
                          context,
                          isFavorite: libraryEntry?.isFavorite ?? false,
                          onFavoriteTap: () => _toggleFavorite(libraryEntry),
                        ),
                        const SizedBox(height: 58),
                        _buildBookOverview(context),
                        const SizedBox(height: 30),
                        _buildTabs(),
                        const SizedBox(height: 28),
                        _buildTabContent(),
                      ],
                    ),
                  ),
                ),
                _buildBorrowAction(),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build the Borrow/Return button at bottom of page
  /// Uses FutureBuilder to wait for student info to load, then shows borrow state stream
  Widget _buildBorrowAction() {
    // Wait for student info to load (uid, studentId, name)
    return FutureBuilder<_StudentInfo>(
      future: _studentInfoFuture,
      builder: (context, studentSnapshot) {
        if (studentSnapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: _BorrowActionButton(
              label: 'Borrow',
              onPressed: () => _showError(
                studentSnapshot.error.toString().replaceFirst(
                  'Exception: ',
                  '',
                ),
              ),
            ),
          );
        }

        final student = studentSnapshot.data;
        if (student == null) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: SizedBox(
              height: 56,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF2BA6A3)),
              ),
            ),
          );
        }

        // Listen to real-time borrow state for this student+book.
        // BUG FIX: Use null as the initial value (not false) so we can
        // distinguish "still loading" from "confirmed not borrowed".
        // This prevents the button from briefly showing "Borrow" on a new
        // account while Firestore hasn't responded yet, which caused the
        // wrong state when availableCopies was already 0.
        return StreamBuilder<bool>(
          stream: _borrowedStateStream(student),
          builder: (context, borrowedSnapshot) {
            return StreamBuilder<StudentBookDetailsData>(
              stream: _bookStreamCached,
              builder: (context, bookSnapshot) {
                // Both streams MUST have emitted at least one real value
                // before we render anything interactive. While either stream
                // is still loading, show a spinner. This prevents the stale
                // widget.book (passed from the list page) from briefly
                // enabling the Borrow button when copies are already 0.
                final borrowedLoading = !borrowedSnapshot.hasData;
                final bookLoading = !bookSnapshot.hasData;
                if (borrowedLoading || bookLoading) {
                  return const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 14),
                    child: SizedBox(
                      height: 56,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2BA6A3),
                        ),
                      ),
                    ),
                  );
                }

                // Both streams have resolved — safe to use real values.
                final isBorrowed = borrowedSnapshot.data!;
                final book = bookSnapshot.data!;

                // Determine button state
                final hasNoCopies = !book.hasAvailableCopies;
                final canBorrow = !hasNoCopies || isBorrowed;

                String label;
                if (isBorrowed) {
                  label = 'Return';
                } else if (hasNoCopies) {
                  label = 'No copies available';
                } else {
                  label = 'Borrow';
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.availabilityLabel,
                        style: TextStyle(
                          color: book.hasAvailableCopies || isBorrowed
                              ? const Color(0xFF197C79)
                              : const Color(0xFFE43C44),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _BorrowActionButton(
                        label: label,
                        isDisabled: hasNoCopies && !isBorrowed,
                        onPressed: canBorrow
                            ? () => _showBorrowQr(
                                student: student,
                                isReturn: isBorrowed,
                              )
                            : null,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool isFavorite,
    required VoidCallback onFavoriteTap,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: const Color(0xFF121926),
          tooltip: 'Back',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF11121A),
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        IconButton(
          onPressed: onFavoriteTap,
          icon: Icon(
            isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 30,
          ),
          color: isFavorite ? const Color(0xFF2BA6A3) : const Color(0xFF121926),
          tooltip: 'Favorite',
        ),
      ],
    );
  }

  String? _optionalString(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  Widget _buildBookOverview(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final coverWidth = width < 370 ? 156.0 : 170.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: coverWidth,
            child: AspectRatio(
              aspectRatio: 0.82,
              child: _BookCoverImage(book: widget.book),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: StreamBuilder<StudentBookDetailsData>(
            stream: _bookStreamCached,
            builder: (context, bookSnapshot) {
              final book = bookSnapshot.data ?? widget.book;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoBlock(label: 'Author', value: book.author),
                  _InfoBlock(label: 'Publisher', value: book.publisher),
                  _InfoBlock(
                    label: 'Publication Date:',
                    value: book.publicationDate,
                  ),
                  _InfoBlock(label: 'Edition:', value: book.edition),
                  _InfoBlock(label: 'Language:', value: book.language),
                  _AvailabilityBadge(book: book),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _InfoBlock(
                          label: 'Pages',
                          value: book.displayPages,
                          bottomSpacing: 0,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 19),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: Color(0xFF697386),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _DetailTab(
          label: 'Overview',
          selected: _tabIndex == 0,
          onTap: () => setState(() => _tabIndex = 0),
        ),
        const SizedBox(width: 26),
        _DetailTab(
          label: 'Reviews',
          selected: _tabIndex == 1,
          onTap: () => setState(() => _tabIndex = 1),
        ),
      ],
    );
  }

  Widget _buildTabContent() {
    if (_tabIndex == 1) {
      return const Text(
        'No reviews yet.',
        style: TextStyle(
          color: Color(0xFF11121A),
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Summary',
          style: TextStyle(
            color: Color(0xFF11121A),
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.book.summary,
          style: const TextStyle(
            color: Color(0xFF11121A),
            fontSize: 15,
            height: 1.12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// _StudentInfo: Data model containing unique student identifiers
/// Used to generate unique QR codes and track borrow records
/// Flow: Loaded once on page init → Passed to QR generation → Each student gets unique QR per book
class _StudentInfo {
  const _StudentInfo({
    required this.uid, // Firebase auth UID - unique per user account
    required this.studentId, // School/system ID - unique per student
    required this.name, // Student's full name - displayed in QR dialog
  });

  final String uid; // Firebase auth ID
  final String studentId; // School system ID
  final String name; // Display name
}

class _BorrowActionButton extends StatelessWidget {
  const _BorrowActionButton({
    required this.label,
    required this.onPressed,
    this.isDisabled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: isDisabled
              ? const Color(0xFFD0D5DD) // Gray when disabled
              : const Color(0xFF2BA6A3),
          foregroundColor: isDisabled
              ? const Color(0xFF8A93A2) // Muted text when disabled
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _CategoryChoiceChip extends StatelessWidget {
  const _CategoryChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _CategoryPickerButton(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF2BA6A3).withValues(alpha: 0.18)
              : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF2BA6A3) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF197C79) : const Color(0xFF121926),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CategoryPickerButton extends StatefulWidget {
  const _CategoryPickerButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_CategoryPickerButton> createState() => _CategoryPickerButtonState();
}

class _CategoryPickerButtonState extends State<_CategoryPickerButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.label,
    required this.value,
    this.bottomSpacing = 10,
  });

  final String label;
  final String value;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5F6675),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF11121A),
              fontSize: 12,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        style: TextStyle(
          color: selected ? const Color(0xFF2BA6A3) : const Color(0xFF11121A),
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          letterSpacing: 0,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Displays a compact "2/3 Available" pill that changes colour based on stock:
///   • green-teal  → copies available
///   • amber       → last copy
///   • red         → no copies left
class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.book});

  final StudentBookDetailsData book;

  @override
  Widget build(BuildContext context) {
    final available = book.availableCopies.clamp(0, book.totalCopies);
    final total = book.totalCopies;

    final Color bg;
    final Color fg;
    final IconData icon;

    if (available == 0) {
      bg = const Color(0xFFFFE5E7);
      fg = const Color(0xFFE43C44);
      icon = Icons.block_rounded;
    } else if (available == 1) {
      bg = const Color(0xFFFFF3CD);
      fg = const Color(0xFFB45309);
      icon = Icons.warning_amber_rounded;
    } else {
      bg = const Color(0xFFD7F4EF);
      fg = const Color(0xFF17817F);
      icon = Icons.check_circle_outline_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Availability',
            style: TextStyle(
              color: Color(0xFF5F6675),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
                Text(
                  '$available/$total Available',
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
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

class _BookCoverImage extends StatelessWidget {
  const _BookCoverImage({required this.book});

  final StudentBookDetailsData book;

  @override
  Widget build(BuildContext context) {
    // If no cover image URL exists, show gradient placeholder with book icon
    if (book.coverUrl.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF2BA6A3)],
          ),
        ),
        child: Center(
          child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 38),
        ),
      );
    }

    // Load book cover image from network (Firestore storage URL)
    // Shows loading spinner while fetching, error icon if failed
    return Image.network(
      book.coverUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        // Show loading spinner while image downloads
        if (loadingProgress == null) {
          return child; // Image loaded successfully
        }
        return const Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2BA6A3),
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        // If image fails to load, show error icon
        return const ColoredBox(
          color: Color(0xFF111827),
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white),
          ),
        );
      },
    );
  }
}
