import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Student/book_details_page.dart';
import 'package:libretrack/pages/Student/book_list_page.dart';
import 'package:libretrack/pages/Student/explore_page.dart';
import 'package:libretrack/pages/Student/profile_page.dart';
import 'package:libretrack/services/notification_service.dart';
import 'package:libretrack/services/student_library_service.dart';

// ---------------------------------------------------------------------------
// STUDENT PAGE (TAB MANAGER)
// ---------------------------------------------------------------------------

class StudentPage extends StatefulWidget {
  const StudentPage({super.key});

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(NotificationService.registerCurrentDevice(role: 'student'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _navIndex,
                children: const [
                  HomePage(),
                  ExplorePage(),
                  BookListPage(),
                  ProfilePage(),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _NavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home',
        onTap: () => setState(() => _navIndex = 0),
      ),
      _NavItem(
        icon: Icons.explore_outlined,
        activeIcon: Icons.explore_rounded,
        label: 'Explore',
        onTap: () => setState(() => _navIndex = 1),
      ),
      _NavItem(
        icon: Icons.library_books_outlined,
        activeIcon: Icons.library_books_rounded,
        label: 'Book list',
        onTap: () => setState(() => _navIndex = 2),
      ),
      _NavItem(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        label: 'Profile',
        onTap: () => setState(() => _navIndex = 3),
      ),
    ];

    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.09),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isActive = _navIndex == i;
          return _AniyomiTapResponse(
            onTap: item.onTap,
            child: SizedBox(
              width: 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: isActive ? 1 : 0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, -2 * value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: 48 + (18 * value),
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              Colors.transparent,
                              const Color(0xFFDAD0FF),
                              value,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, animation) {
                              return ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.82,
                                  end: 1,
                                ).animate(animation),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: Icon(
                              isActive ? item.activeIcon : item.icon,
                              key: ValueKey('${item.label}-$isActive'),
                              size: 23 + (2 * value),
                              color: Color.lerp(
                                const Color(0xFF36343C),
                                const Color(0xFF4B23C6),
                                value,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF4B23C6)
                          : const Color(0xFF5A5862),
                    ),
                    child: Text(item.label),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _AniyomiTapResponse extends StatefulWidget {
  const _AniyomiTapResponse({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_AniyomiTapResponse> createState() => _AniyomiTapResponseState();
}

class _AniyomiTapResponseState extends State<_AniyomiTapResponse> {
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
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;
}

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------

class HomeBook {
  final String id;
  final String title;
  final String author;
  final String description;
  final String coverUrl;
  final int createdAtMillis;
  final List<Color> gradient;
  final StudentBookDetailsData details;

  const HomeBook({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.coverUrl,
    required this.createdAtMillis,
    required this.gradient,
    required this.details,
  });

  factory HomeBook.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final details = StudentBookDetailsData.fromMap(id: doc.id, data: data);

    return HomeBook(
      id: doc.id,
      title: details.title,
      author: details.author,
      description: details.summary,
      coverUrl: details.coverUrl,
      createdAtMillis: _timestampMillis(
        data['created_at'] ?? data['createdAt'],
      ),
      gradient: _gradientFor(details.title),
      details: details,
    );
  }

  String get subtitle => '$author · Recently added';

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }

  static List<Color> _gradientFor(String seed) {
    const palettes = [
      [Color(0xFF1A237E), Color(0xFF2BA6A3)],
      [Color(0xFF31473A), Color(0xFFE2A346)],
      [Color(0xFF69353F), Color(0xFF4B8E8D)],
      [Color(0xFF243B53), Color(0xFF9C6644)],
      [Color(0xFF245953), Color(0xFFB85C38)],
    ];
    final index =
        seed.codeUnits.fold<int>(0, (total, unit) => total + unit) %
        palettes.length;
    return palettes[index];
  }
}

class _StudentBorrowStats {
  const _StudentBorrowStats({this.currentlyBorrowed = 0, this.returned = 0});

  final int currentlyBorrowed;
  final int returned;
}

class _StudentBorrowRecord {
  const _StudentBorrowRecord({
    required this.recordId,
    required this.bookId,
    required this.bookTitle,
    required this.author,
    required this.coverUrl,
    required this.status,
    required this.borrowedAtMillis,
    required this.dueDateMillis,
    required this.returnedAtMillis,
  });

  final String recordId;
  final String bookId;
  final String bookTitle;
  final String author;
  final String coverUrl;
  final String status;
  final int borrowedAtMillis;
  final int dueDateMillis;
  final int returnedAtMillis;

  bool get isReturned => status == 'returned' || status == 'return';

  bool get isCurrentlyBorrowed => status == 'active' || status == 'borrowed';

  bool get isOverdue {
    if (isReturned || dueDateMillis == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > dueDateMillis;
  }

  String get statusLabel => isReturned ? 'Returned' : 'Borrowed';

  Color get statusColor =>
      isReturned ? const Color(0xFF4B23C6) : const Color(0xFF19A7A1);

  factory _StudentBorrowRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final borrowedAtMillis = _timestampMillis(
      data['borrowed_at'] ??
          data['borrowedAt'] ??
          data['scanned_at'] ??
          data['scannedAt'] ??
          data['created_at'] ??
          data['createdAt'],
    );
    final explicitDueMillis = _timestampMillis(
      data['dueDate'] ?? data['due_date'],
    );

    return _StudentBorrowRecord(
      recordId: doc.id,
      bookId: _stringValue(data['bookId'] ?? data['book_id'], fallback: ''),
      bookTitle: _stringValue(
        data['bookTitle'] ?? data['title'],
        fallback: 'Untitled Book',
      ),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
      coverUrl: _stringValue(
        data['cover_url'] ?? data['coverUrl'],
        fallback: '',
      ),
      status: _stringValue(data['status'], fallback: 'borrowed').toLowerCase(),
      borrowedAtMillis: borrowedAtMillis,
      dueDateMillis: explicitDueMillis != 0
          ? explicitDueMillis
          : borrowedAtMillis == 0
          ? 0
          : borrowedAtMillis + const Duration(days: 7).inMilliseconds,
      returnedAtMillis: _timestampMillis(
        data['returned_at'] ?? data['returnedAt'] ?? data['returnDate'],
      ),
    );
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

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }
}

// ---------------------------------------------------------------------------
// HOME PAGE
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentBanner = 0;
  late final PageController _pageController = PageController(
    viewportFraction: 0.88,
  );
  late final Stream<List<HomeBook>> _booksStream = _bookStream();
  late final Stream<Map<String, StudentBookLibraryEntry>>
  _libraryEntriesStream = _libraryStream();
  late final Stream<_StudentBorrowStats> _studentBorrowStatsStream =
      _borrowStatsStream();
  late final Stream<List<AppNotification>> _notificationsStream =
      NotificationService.notificationsStream(role: 'student');
  Timer? _bannerAutoScrollTimer;
  Timer? _dueNotificationTimer;
  List<AppNotification> _notifications = [];
  int _unreadNotificationCount = 0;
  StreamSubscription<List<AppNotification>>? _notificationSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _overdueSubscription;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      StudentLibraryService.ensureDefaultCategory(user.uid);
      _listenForStudentNotifications();
      _listenForStudentDueNotifications(user.uid);
      _scheduleStudentDueNotificationChecks(user.uid);
    }
  }

  Stream<List<HomeBook>> _bookStream() {
    return FirebaseFirestore.instance.collection('books').snapshots().map((
      snapshot,
    ) {
      final books = snapshot.docs.map(HomeBook.fromDoc).toList();
      books.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return books;
    });
  }

  Stream<Map<String, StudentBookLibraryEntry>> _libraryStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream<Map<String, StudentBookLibraryEntry>>.value({});
    }
    return StudentLibraryService.libraryEntriesStream(user.uid);
  }

  Stream<_StudentBorrowStats> _borrowStatsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream<_StudentBorrowStats>.value(const _StudentBorrowStats());
    }

    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('studentUid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          var currentlyBorrowed = 0;
          var returned = 0;
          for (final doc in snapshot.docs) {
            final status = _profileValue(
              doc.data()['status'],
              fallback: '',
            ).toLowerCase();
            if (status == 'active' || status == 'borrowed') {
              currentlyBorrowed++;
            } else if (status == 'returned' || status == 'return') {
              returned++;
            }
          }

          return _StudentBorrowStats(
            currentlyBorrowed: currentlyBorrowed,
            returned: returned,
          );
        });
  }

  Stream<List<_StudentBorrowRecord>> _studentBorrowRecordsStream({
    required bool returned,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream<List<_StudentBorrowRecord>>.value(
        const <_StudentBorrowRecord>[],
      );
    }

    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('studentUid', isEqualTo: user.uid)
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .map(_StudentBorrowRecord.fromDoc)
              .where(
                (record) =>
                    returned ? record.isReturned : record.isCurrentlyBorrowed,
              )
              .toList();
          records.sort((a, b) {
            final aTime = returned && a.returnedAtMillis != 0
                ? a.returnedAtMillis
                : a.borrowedAtMillis;
            final bTime = returned && b.returnedAtMillis != 0
                ? b.returnedAtMillis
                : b.borrowedAtMillis;
            return bTime.compareTo(aTime);
          });
          return records;
        });
  }

  /// Fetch categories from student's borrowed books to personalize recommendations
  Future<Set<String>> _getBorrowedCategories() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return {};

    try {
      final borrowRecords = await FirebaseFirestore.instance
          .collection('borrow_records')
          .where('studentUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .limit(20) // Get recent active borrows
          .get();

      final categories = <String>{};
      for (final record in borrowRecords.docs) {
        final data = record.data();
        final category = data['category'] as String?;
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }
      return categories;
    } catch (e) {
      debugPrint('[Recommendations] Error fetching borrowed categories: $e');
      return {};
    }
  }

  /// Generate personalized recommendations based on borrowed book categories
  List<HomeBook> _getPersonalizedRecommendations(
    List<HomeBook> allBooks,
    Set<String> borrowedCategories,
  ) {
    if (borrowedCategories.isEmpty) {
      // Fallback: return books 6-10 if no borrow history
      return allBooks.length > 5
          ? allBooks.skip(5).take(5).toList()
          : <HomeBook>[];
    }

    // Filter books by matching categories, exclude recently added
    final recentlyAddedIds = allBooks.take(5).map((b) => b.id).toSet();
    final recommendations = allBooks
        .where(
          (book) =>
              !recentlyAddedIds.contains(book.id) &&
              borrowedCategories.contains(book.details.category),
        )
        .take(5)
        .toList();

    // If not enough similar books, fill with other available books
    if (recommendations.length < 5) {
      final additionalBooks = allBooks
          .where(
            (book) =>
                !recentlyAddedIds.contains(book.id) &&
                !recommendations.any((r) => r.id == book.id),
          )
          .take(5 - recommendations.length);
      recommendations.addAll(additionalBooks);
    }

    return recommendations;
  }

  @override
  void dispose() {
    _bannerAutoScrollTimer?.cancel();
    _dueNotificationTimer?.cancel();
    unawaited(_notificationSubscription?.cancel());
    unawaited(_overdueSubscription?.cancel());
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshHome() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshHome,
      color: const Color(0xFF2BA6A3),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 8),
            StreamBuilder<List<HomeBook>>(
              stream: _booksStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _HomeMessage(
                    icon: Icons.error_outline_rounded,
                    message: 'Could not load books: ${snapshot.error}',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final books = snapshot.data ?? [];
                final bannerBooks = books.take(5).toList();
                final recentlyAdded = books.take(5).toList();

                return FutureBuilder<Set<String>>(
                  future: _getBorrowedCategories(),
                  builder: (context, categorySnapshot) {
                    final borrowedCategories = categorySnapshot.data ?? {};
                    final recommendations = _getPersonalizedRecommendations(
                      books,
                      borrowedCategories,
                    );

                    return StreamBuilder<Map<String, StudentBookLibraryEntry>>(
                      stream: _libraryEntriesStream,
                      builder: (context, librarySnapshot) {
                        final libraryEntries = librarySnapshot.data ?? {};

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildBannerCarousel(bannerBooks),
                            if (bannerBooks.isNotEmpty)
                              _buildDots(bannerBooks.length),
                            _buildBorrowStatsCards(),
                            _buildSectionHeader(
                              'Recently Added',
                              showSeeAll: false,
                            ),
                            _buildBookRow(
                              recentlyAdded,
                              libraryEntries: libraryEntries,
                            ),
                            if (recommendations.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildSectionHeader(
                                'Recommendations For You',
                                showSeeAll: false,
                              ),
                              _buildBookRow(
                                recommendations,
                                libraryEntries: libraryEntries,
                              ),
                            ],
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildBorrowStatsCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
      child: StreamBuilder<_StudentBorrowStats>(
        stream: _studentBorrowStatsStream,
        builder: (context, snapshot) {
          final stats = snapshot.data ?? const _StudentBorrowStats();

          return Row(
            children: [
              Expanded(
                child: _StudentDashboardStatCard(
                  icon: Icons.bookmark_added_rounded,
                  title: 'Currently Borrowed Books',
                  value:
                      '${stats.currentlyBorrowed} ${stats.currentlyBorrowed == 1 ? 'Book' : 'Books'}',
                  onTap: () => _openStudentBorrowHistory(returned: false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StudentDashboardStatCard(
                  icon: Icons.assignment_return_rounded,
                  title: 'Returned Books',
                  value:
                      '${stats.returned} ${stats.returned == 1 ? 'Book' : 'Books'}',
                  onTap: () => _openStudentBorrowHistory(returned: true),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openStudentBorrowHistory({required bool returned}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StudentBorrowHistoryPage(
          title: returned ? 'Returned Books' : 'Currently Borrowed Books',
          emptyMessage: returned
              ? 'No returned books yet.'
              : 'No currently borrowed books yet.',
          stream: _studentBorrowRecordsStream(returned: returned),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _HomeHeaderContent(
        name: 'Student',
        photoUrl: '',
        onProfileTap: () {},
        unreadCount: 0,
        onNotificationTap: _openNotificationPanel,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final name = _profileValue(
            data?['name'],
            fallback: user.displayName ?? 'Student',
          );
          final photoUrl = _profileValue(
            data?['photoUrl'],
            fallback: _profileValue(
              data?['profileImageUrl'],
              fallback: user.photoURL ?? '',
            ),
          );

          return _HomeHeaderContent(
            name: name,
            photoUrl: photoUrl,
            onProfileTap: () {
              // The Profile tab already owns profile details and settings.
            },
            unreadCount: _unreadNotificationCount,
            onNotificationTap: _openNotificationPanel,
          );
        },
      ),
    );
  }

  void _listenForStudentNotifications() {
    _notificationSubscription = _notificationsStream.listen((notifications) {
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _unreadNotificationCount = notifications
            .where((notification) => !notification.isRead)
            .length;
      });
    });
  }

  void _openNotificationPanel() {
    setState(() => _unreadNotificationCount = 0);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StreamBuilder<List<AppNotification>>(
          stream: _notificationsStream,
          initialData: _notifications,
          builder: (context, snapshot) {
            return _StudentNotificationSheet(
              notifications: snapshot.data ?? _notifications,
            );
          },
        );
      },
    );
    unawaited(NotificationService.markAllRead(role: 'student'));
  }

  void _listenForStudentDueNotifications(String userUid) {
    _overdueSubscription = FirebaseFirestore.instance
        .collection('borrow_records')
        .where('studentUid', isEqualTo: userUid)
        .snapshots()
        .listen((snapshot) {
          _createDueNotificationsForDocs(userUid, snapshot.docs);
        });
  }

  void _scheduleStudentDueNotificationChecks(String userUid) {
    unawaited(_checkStudentDueNotifications(userUid));
    _dueNotificationTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_checkStudentDueNotifications(userUid));
    });
  }

  Future<void> _checkStudentDueNotifications(String userUid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('borrow_records')
          .where('studentUid', isEqualTo: userUid)
          .get();
      _createDueNotificationsForDocs(userUid, snapshot.docs);
    } catch (e) {
      debugPrint('[Notifications] Could not check student due dates: $e');
    }
  }

  void _createDueNotificationsForDocs(
    String userUid,
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    for (final doc in docs) {
      final data = doc.data();
      final status = _profileValue(data['status'], fallback: '').toLowerCase();
      if (status != 'active' && status != 'borrowed') continue;

      final explicitDue = _timestampMillis(data['dueDate'] ?? data['due_date']);
      final dueMillis = explicitDue != 0
          ? explicitDue
          : _fallbackDueMillis(data);
      if (dueMillis == 0) continue;

      final dueDate = DateTime.fromMillisecondsSinceEpoch(dueMillis);
      final daysUntilDue = _daysUntilDue(now, dueDate);

      if (daysUntilDue >= 1 && daysUntilDue <= 3) {
        unawaited(
          NotificationService.ensureDueSoonNotification(
            recordId: doc.id,
            bookId: _profileValue(data['bookId'], fallback: ''),
            bookTitle: _profileValue(
              data['bookTitle'] ?? data['title'],
              fallback: 'a book',
            ),
            studentUid: userUid,
            dueDate: dueDate,
            daysUntilDue: daysUntilDue,
          ),
        );
        continue;
      }

      if (now.millisecondsSinceEpoch <= dueMillis) continue;

      unawaited(
        NotificationService.ensureOverdueNotification(
          recordId: doc.id,
          bookId: _profileValue(data['bookId'], fallback: ''),
          bookTitle: _profileValue(
            data['bookTitle'] ?? data['title'],
            fallback: 'a book',
          ),
          borrowerName: _profileValue(
            data['borrowerName'] ?? data['studentName'] ?? data['name'],
            fallback: 'Student',
          ),
          studentUid: userUid,
          dueDate: dueDate,
          role: 'student',
        ),
      );
    }
  }

  String _profileValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }

  int _fallbackDueMillis(Map<String, dynamic> data) {
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

  int _daysUntilDue(DateTime now, DateTime dueDate) {
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return dueDay.difference(today).inDays;
  }

  // ---------------------------------------------------------------------------
  // BANNER CAROUSEL
  // ---------------------------------------------------------------------------

  Widget _buildBannerCarousel(List<HomeBook> books) {
    if (books.isEmpty) {
      return Container(
        height: 155,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.library_books_outlined,
                size: 36,
                color: Color(0xFFA0A8B9),
              ),
              SizedBox(height: 8),
              Text(
                'Recently added books will appear here',
                style: TextStyle(fontSize: 12, color: Color(0xFFA0A8B9)),
              ),
              Text(
                'Add books from the librarian page',
                style: TextStyle(fontSize: 10, color: Color(0xFFC0C8D9)),
              ),
            ],
          ),
        ),
      );
    }

    // Start auto-scroll carousel
    _bannerAutoScrollTimer?.cancel();
    _bannerAutoScrollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _pageController.hasClients) {
        final nextPage = (_currentBanner + 1) % books.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });

    return SizedBox(
      height: 155,
      child: PageView.builder(
        controller: _pageController,
        itemCount: books.length,
        onPageChanged: (i) => setState(() => _currentBanner = i),
        itemBuilder: (_, i) {
          final book = books[i];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _BannerCard(book: book),
          );
        },
      ),
    );
  }

  Widget _buildDots(int count) {
    final activeIndex = count == 0 ? 0 : _currentBanner % count;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final isActive = i == activeIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isActive ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF3C13C5)
                  : const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION HEADER
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader(
    String title, {
    bool showSeeAll = false,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          if (showSeeAll)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3C13C5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOOK ROW
  // ---------------------------------------------------------------------------

  Widget _buildBookRow(
    List<HomeBook> books, {
    required Map<String, StudentBookLibraryEntry> libraryEntries,
  }) {
    if (books.isEmpty) {
      return Container(
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text(
            'No books yet. Add a book from the librarian page.',
            style: TextStyle(fontSize: 11, color: Color(0xFFA0A8B9)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 252,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: books.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (_, i) {
          final book = books[i];
          return _BookCard(
            book: book,
            isFavorite: libraryEntries[book.id]?.isFavorite ?? false,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUB-WIDGETS
// ---------------------------------------------------------------------------

class _BannerCard extends StatelessWidget {
  final HomeBook book;
  const _BannerCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 155,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: book.gradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: _BookCoverImage(book: book)),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.72),
                  Colors.black.withValues(alpha: 0.18),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  book.subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
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

class _BookCard extends StatelessWidget {
  final HomeBook book;
  final bool isFavorite;

  const _BookCard({required this.book, required this.isFavorite});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentBookDetailsPage(book: book.details),
          ),
        );
      },
      child: SizedBox(
        width: 132,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 0.68,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      Positioned.fill(child: _BookCoverImage(book: book)),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.44),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 9,
                        right: 9,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.50),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Icon(
                            isFavorite
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF121926),
                fontSize: 13,
                height: 1.12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF737B8C),
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCoverImage extends StatelessWidget {
  const _BookCoverImage({required this.book});

  final HomeBook book;

  @override
  Widget build(BuildContext context) {
    if (book.coverUrl.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: book.gradient,
          ),
        ),
        child: const Center(
          child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 38),
        ),
      );
    }

    return Image.network(
      book.coverUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: book.gradient,
            ),
          ),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: book.gradient,
            ),
          ),
          child: const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white),
          ),
        );
      },
    );
  }
}

class _HomeMessage extends StatelessWidget {
  const _HomeMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB3261E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF121926),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentDashboardStatCard extends StatelessWidget {
  const _StudentDashboardStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 82,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(icon, size: 30, color: const Color(0xFF2BA6A3)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFF242631),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        alignment: Alignment.centerLeft,
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          maxLines: 1,
                          style: const TextStyle(
                            color: Color(0xFF11121A),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentBorrowHistoryPage extends StatelessWidget {
  const _StudentBorrowHistoryPage({
    required this.title,
    required this.emptyMessage,
    required this.stream,
  });

  final String title;
  final String emptyMessage;
  final Stream<List<_StudentBorrowRecord>> stream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2BA6A3),
          onRefresh: () async {},
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _StudentBorrowHistoryTopBar(title: title),
                    const SizedBox(height: 18),
                    StreamBuilder<List<_StudentBorrowRecord>>(
                      stream: stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const _HomeMessage(
                            icon: Icons.error_outline_rounded,
                            message: 'Could not load books.',
                          );
                        }

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 42),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF2BA6A3),
                              ),
                            ),
                          );
                        }

                        final records = snapshot.data ?? [];
                        if (records.isEmpty) {
                          return _HomeMessage(
                            icon: Icons.library_books_outlined,
                            message: emptyMessage,
                          );
                        }

                        return Column(
                          children: records
                              .map(
                                (record) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _StudentBorrowRecordCard(
                                    record: record,
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentBorrowHistoryTopBar extends StatelessWidget {
  const _StudentBorrowHistoryTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          _AniyomiTapResponse(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF121926),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF121926),
                fontSize: 21,
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

class _StudentBorrowRecordCard extends StatelessWidget {
  const _StudentBorrowRecordCard({required this.record});

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
    return _AniyomiTapResponse(
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
              _StudentBorrowCover(coverUrl: record.coverUrl),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        const SizedBox(width: 8),
                        _StudentBorrowStatusPill(record: record),
                      ],
                    ),
                    const SizedBox(height: 6),
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
                    const SizedBox(height: 6),
                    Text(
                      record.isReturned
                          ? 'Returned ${_studentDateLabel(record.returnedAtMillis)}'
                          : 'Borrowed ${_studentDateLabel(record.borrowedAtMillis)}',
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
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentBorrowCover extends StatelessWidget {
  const _StudentBorrowCover({required this.coverUrl});

  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 58,
        height: 72,
        child: coverUrl.isEmpty
            ? const _StudentBorrowCoverFallback()
            : Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const _StudentBorrowCoverFallback();
                },
              ),
      ),
    );
  }
}

class _StudentBorrowCoverFallback extends StatelessWidget {
  const _StudentBorrowCoverFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(child: Icon(Icons.menu_book_rounded, color: Colors.white)),
    );
  }
}

class _StudentBorrowStatusPill extends StatelessWidget {
  const _StudentBorrowStatusPill({required this.record});

  final _StudentBorrowRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: record.statusColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        record.statusLabel,
        style: TextStyle(
          color: record.statusColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _StudentBorrowDetailSheet extends StatelessWidget {
  const _StudentBorrowDetailSheet({required this.record});

  final _StudentBorrowRecord record;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.64,
      minChildSize: 0.38,
      maxChildSize: 0.88,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Book Details',
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
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _studentDetailCardDecoration(),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 66,
                            height: 82,
                            child: record.coverUrl.isEmpty
                                ? const _StudentBorrowCoverFallback()
                                : Image.network(
                                    record.coverUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const _StudentBorrowCoverFallback(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.isReturned
                                    ? 'BOOK RETURNED'
                                    : 'BOOK BORROWED',
                                style: const TextStyle(
                                  color: Color(0xFF2BA6A3),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
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
                              const SizedBox(height: 8),
                              _StudentBorrowStatusPill(record: record),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    decoration: _studentDetailCardDecoration(),
                    child: Column(
                      children: [
                        _StudentDateInfoRow(
                          icon: Icons.login_rounded,
                          label: 'Borrowed On',
                          value: _studentDateTimeLabel(record.borrowedAtMillis),
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        _StudentDateInfoRow(
                          icon: Icons.event_rounded,
                          label: 'Due Date',
                          value: _studentDateTimeLabel(record.dueDateMillis),
                          valueColor: record.isOverdue
                              ? const Color(0xFFE43C44)
                              : const Color(0xFF2BA6A3),
                          trailingBadge: record.isOverdue ? 'OVERDUE' : null,
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        _StudentDateInfoRow(
                          icon: Icons.logout_rounded,
                          label: 'Returned On',
                          value: record.isReturned
                              ? _studentDateTimeLabel(record.returnedAtMillis)
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

class _StudentDateInfoRow extends StatelessWidget {
  const _StudentDateInfoRow({
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
          child: Icon(icon, color: const Color(0xFF2BA6A3), size: 18),
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
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        if (trailingBadge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE43C44).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailingBadge!,
              style: const TextStyle(
                color: Color(0xFFE43C44),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    );
  }
}

BoxDecoration _studentDetailCardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

String _studentDateLabel(int millis) {
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
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

String _studentDateTimeLabel(int millis) {
  if (millis == 0) return 'N/A';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '${_studentDateLabel(millis)} • $hour:$minute $period';
}

class _HomeHeaderContent extends StatelessWidget {
  const _HomeHeaderContent({
    required this.name,
    required this.photoUrl,
    required this.onProfileTap,
    required this.unreadCount,
    required this.onNotificationTap,
  });

  final String name;
  final String photoUrl;
  final VoidCallback onProfileTap;
  final int unreadCount;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: onProfileTap,
          child: _HomeAvatar(name: name, photoUrl: photoUrl),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Welcome back,',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFFA0A8B9),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF121926),
                ),
              ),
            ],
          ),
        ),
        _NotificationButton(unreadCount: unreadCount, onTap: onNotificationTap),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD9DEE8)),
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: Color(0xFF4B23C6),
                  size: 22,
                ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE43C44),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE3E7EB)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1,
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

class _StudentNotificationSheet extends StatelessWidget {
  const _StudentNotificationSheet({required this.notifications});

  final List<AppNotification> notifications;

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _iconFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.borrowConfirmed:
        return Icons.check_circle_rounded;
      case AppNotificationType.returnConfirmed:
        return Icons.assignment_return_rounded;
      case AppNotificationType.dueSoon:
        return Icons.schedule_rounded;
      case AppNotificationType.overdue:
        return Icons.warning_amber_rounded;
      case AppNotificationType.newBorrow:
        return Icons.bookmark_added_rounded;
      case AppNotificationType.general:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.overdue:
        return const Color(0xFFE43C44);
      case AppNotificationType.dueSoon:
        return const Color(0xFFE2A346);
      case AppNotificationType.returnConfirmed:
        return const Color(0xFF4B23C6);
      case AppNotificationType.borrowConfirmed:
      case AppNotificationType.newBorrow:
        return const Color(0xFF2BA6A3);
      case AppNotificationType.general:
        return const Color(0xFF4B23C6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F8FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD0D5DD),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
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
            Expanded(
              child: notifications.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 48,
                            color: Color(0xFFABB6C2),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No notifications yet',
                            style: TextStyle(
                              color: Color(0xFF8A93A2),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                      itemCount: notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        final color = _colorFor(notification.type);
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.07),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _iconFor(notification.type),
                                  size: 20,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notification.title,
                                      style: const TextStyle(
                                        color: Color(0xFF11121A),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      notification.body,
                                      style: const TextStyle(
                                        color: Color(0xFF565B66),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeAgo(notification.createdAt),
                                      style: const TextStyle(
                                        color: Color(0xFFABB6C2),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

class _HomeAvatar extends StatelessWidget {
  const _HomeAvatar({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'S' : name.trim()[0].toUpperCase();

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9DEE8)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _InitialAvatar(initial: initial),
              )
            : _InitialAvatar(initial: initial),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2BA6A3),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
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
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
