import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Librarian/librarian_books_tab.dart';
import 'package:libretrack/pages/Librarian/librarian_profile_page.dart';
import 'package:libretrack/pages/Librarian/scan_page.dart';

class LibrarianPage extends StatefulWidget {
  const LibrarianPage({super.key});

  @override
  State<LibrarianPage> createState() => _LibrarianPageState();
}

class _LibrarianPageState extends State<LibrarianPage> {
  int _navIndex = 0;

  // ── FCM / notification state ──────────────────────────────────────────────
  final List<_AppNotification> _notifications = [];
  bool _hasUnread = false;

  @override
  void initState() {
    super.initState();
    _initFcm();
    _listenForOverdueNotifications();
    _listenForNewBorrows();
  }

  Future<void> _initFcm() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'Notification';
      final body = message.notification?.body ?? '';
      if (mounted) {
        setState(() {
          _notifications.insert(
            0,
            _AppNotification(
              title: title,
              body: body,
              time: DateTime.now(),
              type: _NotificationType.general,
            ),
          );
          _hasUnread = true;
        });
      }
    });
  }

  /// Watch active borrow_records and fire an in-app notification when a new
  /// borrow appears (i.e. a student just borrowed a book).
  void _listenForNewBorrows() {
    FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['active', 'borrowed'])
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data()!;
              final borrower = _stringValue(
                data['borrowerName'] ?? data['studentName'] ?? data['name'],
                fallback: 'A student',
              );
              final book = _stringValue(
                data['bookTitle'] ?? data['title'],
                fallback: 'a book',
              );
              if (mounted) {
                setState(() {
                  _notifications.insert(
                    0,
                    _AppNotification(
                      title: 'New Borrow',
                      body: '$borrower borrowed "$book"',
                      time: DateTime.now(),
                      type: _NotificationType.newBorrow,
                    ),
                  );
                  _hasUnread = true;
                });
              }
            }
          }
        });
  }

  /// Watch active records and flag any that are overdue (past due date).
  void _listenForOverdueNotifications() {
    FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['active', 'borrowed'])
        .snapshots()
        .listen((snap) {
          final now = DateTime.now();
          for (final doc in snap.docs) {
            final data = doc.data();

            // Read the due date the librarian explicitly set during scan.
            // scan_page.dart writes both 'dueDate' and 'due_date'.
            // Fall back to borrowedAt + 7 days only for legacy records that
            // pre-date the due-date field (i.e. neither field is present).
            final dueDateMillis = _timestampMillis(
              data['dueDate'] ?? data['due_date'],
            );
            final effectiveDueMillis = dueDateMillis != 0
                ? dueDateMillis
                : _fallbackDueMillis(data);

            if (effectiveDueMillis == 0) continue;
            final dueDate = DateTime.fromMillisecondsSinceEpoch(
              effectiveDueMillis,
            );
            if (now.isAfter(dueDate)) {
              final borrower = _stringValue(
                data['borrowerName'] ?? data['studentName'] ?? data['name'],
                fallback: 'A student',
              );
              final book = _stringValue(
                data['bookTitle'] ?? data['title'],
                fallback: 'a book',
              );
              // Avoid duplicate overdue notifications per record
              final alreadyAdded = _notifications.any(
                (n) =>
                    n.type == _NotificationType.overdue && n.recordId == doc.id,
              );
              if (!alreadyAdded && mounted) {
                setState(() {
                  _notifications.insert(
                    0,
                    _AppNotification(
                      title: 'Overdue Book',
                      body: '$borrower has not returned "$book" — overdue!',
                      time: DateTime.now(),
                      type: _NotificationType.overdue,
                      recordId: doc.id,
                    ),
                  );
                  _hasUnread = true;
                });
              }
            }
          }
        });
  }

  void _openNotificationPanel() {
    setState(() => _hasUnread = false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationSheet(notifications: _notifications),
    );
  }

  Stream<int> _bookCountStream() {
    return FirebaseFirestore.instance
        .collection('books')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<Map<String, int>> _activeBorrowCountsStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['active', 'borrowed'])
        .snapshots()
        .map((snapshot) {
          final counts = <String, int>{};
          for (final doc in snapshot.docs) {
            final bookId = _stringValue(doc.data()['bookId'], fallback: '');
            if (bookId.isEmpty) {
              continue;
            }
            counts[bookId] = (counts[bookId] ?? 0) + 1;
          }
          return counts;
        });
  }

  Stream<List<_DashboardBookRecord>> _dashboardBooksStream(
    Map<String, int> activeBorrowCounts,
  ) {
    return FirebaseFirestore.instance.collection('books').snapshots().map((
      snapshot,
    ) {
      final books = snapshot.docs
          .map(
            (doc) => _DashboardBookRecord.fromDoc(
              doc,
              activeBorrowCount: activeBorrowCounts[doc.id] ?? 0,
            ),
          )
          .toList();
      books.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return books;
    });
  }

  Stream<List<_BorrowerRecord>> _activeBorrowerStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['active', 'borrowed'])
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs.map(_BorrowerRecord.fromDoc).toList();
          records.sort(
            (a, b) => b.borrowedAtMillis.compareTo(a.borrowedAtMillis),
          );
          return records;
        });
  }

  Stream<List<_BorrowerRecord>> _returnedBorrowerStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['returned', 'return'])
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs
              .where((doc) => doc.data()['hiddenInReturned'] != true)
              .map(_BorrowerRecord.fromDoc)
              .toList();
          records.sort(
            (a, b) => b.borrowedAtMillis.compareTo(a.borrowedAtMillis),
          );
          return records;
        });
  }

  Stream<List<_BorrowerRecord>> _transactionHistoryStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .snapshots()
        .map((snapshot) {
          final records = snapshot.docs.map(_BorrowerRecord.fromDoc).toList();
          records.sort(
            (a, b) => b.borrowedAtMillis.compareTo(a.borrowedAtMillis),
          );
          return records;
        });
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
                children: [
                  _buildHomeTab(),
                  const LibrarianScanPage(),
                  const LibrarianBooksTab(),
                  const LibrarianProfilePage(),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      color: const Color(0xFF2BA6A3),
      onRefresh: () async => setState(() {}),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildHomeHeader(),
                const SizedBox(height: 26),
                _buildStatsRow(),
                const SizedBox(height: 76),
                const Text(
                  'Active Borrowers',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 14),
                _buildBorrowerList(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeHeader() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _LibrarianHeaderContent(
        name: 'Librarian',
        photoUrl: '',
        hasUnread: _hasUnread,
        onNotificationTap: _openNotificationPanel,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name = _profileValue(
          data?['name'] ?? data?['fullName'] ?? data?['displayName'],
          fallback: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : _emailName(user.email),
        );
        final photoUrl = _profileValue(
          data?['photoUrl'],
          fallback: _profileValue(
            data?['profileImageUrl'],
            fallback: user.photoURL ?? '',
          ),
        );

        return _LibrarianHeaderContent(
          name: name,
          photoUrl: photoUrl,
          hasUnread: _hasUnread,
          onNotificationTap: _openNotificationPanel,
        );
      },
    );
  }

  String _profileValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }

  String _emailName(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Librarian';
    }
    final name = email.split('@').first.trim();
    return name.isEmpty ? 'Librarian' : name;
  }

  Widget _buildStatsRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final spacing = compact ? 10.0 : 14.0;

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<int>(
                    stream: _bookCountStream(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return _DashboardStatCard(
                        icon: Icons.menu_book_rounded,
                        title: 'Total Books',
                        value: '$count ${count == 1 ? 'Book' : 'Books'}',
                        onTap: _openTotalBooks,
                      );
                    },
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: StreamBuilder<List<_BorrowerRecord>>(
                    stream: _activeBorrowerStream(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return _DashboardStatCard(
                        icon: Icons.bookmark_added_rounded,
                        title: 'Borrow Books',
                        value: '$count ${count == 1 ? 'Book' : 'Books'}',
                        onTap: () => _openHistory(
                          title: 'Borrowed Books',
                          stream: _activeBorrowerStream(),
                          emptyMessage: 'No active borrowed books yet.',
                          statusFilter: ['active', 'borrowed'],
                          showClearButton: false,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing),
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<List<_BorrowerRecord>>(
                    stream: _returnedBorrowerStream(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return _DashboardStatCard(
                        icon: Icons.assignment_return_rounded,
                        title: 'Returned Books',
                        value: '$count ${count == 1 ? 'Book' : 'Books'}',
                        onTap: () => _openHistory(
                          title: 'Returned Books',
                          stream: _returnedBorrowerStream(),
                          emptyMessage: 'No returned books yet.',
                          statusFilter: ['returned', 'return'],
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(width: spacing),
                Expanded(
                  child: StreamBuilder<List<_BorrowerRecord>>(
                    stream: _transactionHistoryStream(),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return _DashboardStatCard(
                        icon: Icons.history_rounded,
                        title: 'History',
                        value:
                            '$count ${count == 1 ? 'Transaction' : 'Transactions'}',
                        onTap: () => _openHistory(
                          title: 'Transaction History',
                          stream: _transactionHistoryStream(),
                          emptyMessage: 'No transactions yet.',
                          statusFilter: null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _openHistory({
    required String title,
    required Stream<List<_BorrowerRecord>> stream,
    required String emptyMessage,
    List<String>? statusFilter,
    bool showClearButton = true,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TransactionHistoryPage(
          title: title,
          stream: stream,
          emptyMessage: emptyMessage,
          statusFilter: statusFilter,
          showClearButton: showClearButton,
        ),
      ),
    );
  }

  void _openTotalBooks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TotalBooksPage(
          activeBorrowCountsStream: _activeBorrowCountsStream(),
          booksForCounts: _dashboardBooksStream,
        ),
      ),
    );
  }

  Widget _buildBorrowerList() {
    return StreamBuilder<List<_BorrowerRecord>>(
      stream: _activeBorrowerStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DashboardMessage(
            icon: Icons.error_outline_rounded,
            message: 'Could not load borrowers.',
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

        final borrowers = snapshot.data ?? [];
        if (borrowers.isEmpty) {
          return const _DashboardMessage(
            icon: Icons.assignment_turned_in_outlined,
            message: 'No active borrowers yet.',
          );
        }

        return Column(
          children: borrowers
              .take(6)
              .map(
                (record) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _BorrowerCard(record: record),
                ),
              )
              .toList(),
        );
      },
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
        icon: Icons.qr_code_scanner_outlined,
        activeIcon: Icons.qr_code_scanner_rounded,
        label: 'Scan',
        onTap: () => setState(() => _navIndex = 1),
      ),
      _NavItem(
        icon: Icons.folder_open_outlined,
        activeIcon: Icons.folder_rounded,
        label: 'Books',
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

class _LibrarianHeaderContent extends StatelessWidget {
  const _LibrarianHeaderContent({
    required this.name,
    required this.photoUrl,
    required this.hasUnread,
    required this.onNotificationTap,
  });

  final String name;
  final String photoUrl;
  final bool hasUnread;
  final VoidCallback onNotificationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _LibrarianAvatar(name: name, photoUrl: photoUrl),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Librarian Dashboard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(0xFFABB6C2),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF11121A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        // ── Notification bell ──────────────────────────────────────────────
        GestureDetector(
          onTap: onNotificationTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_rounded,
                  color: Color(0xFF2BA6A3),
                  size: 22,
                ),
              ),
              if (hasUnread)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE43C44),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalBooksPage extends StatelessWidget {
  const _TotalBooksPage({
    required this.activeBorrowCountsStream,
    required this.booksForCounts,
  });

  final Stream<Map<String, int>> activeBorrowCountsStream;
  final Stream<List<_DashboardBookRecord>> Function(Map<String, int>)
  booksForCounts;

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
                    const _HistoryTopBar(title: 'Total Books'),
                    const SizedBox(height: 18),
                    StreamBuilder<Map<String, int>>(
                      stream: activeBorrowCountsStream,
                      builder: (context, countSnapshot) {
                        if (countSnapshot.hasError) {
                          return const _DashboardMessage(
                            icon: Icons.error_outline_rounded,
                            message: 'Could not load books.',
                          );
                        }

                        if (countSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            !countSnapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 42),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF2BA6A3),
                              ),
                            ),
                          );
                        }

                        return StreamBuilder<List<_DashboardBookRecord>>(
                          stream: booksForCounts(countSnapshot.data ?? {}),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const _DashboardMessage(
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

                            final books = snapshot.data ?? [];
                            if (books.isEmpty) {
                              return const _DashboardMessage(
                                icon: Icons.menu_book_outlined,
                                message: 'No books added yet.',
                              );
                            }

                            return Column(
                              children: books
                                  .map(
                                    (book) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      child: _DashboardBookCard(book: book),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
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

class _DashboardBookCard extends StatelessWidget {
  const _DashboardBookCard({required this.book});

  final _DashboardBookRecord book;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 58,
                height: 72,
                child: book.coverUrl.isEmpty
                    ? const ColoredBox(
                        color: Colors.black,
                        child: Center(
                          child: Icon(
                            Icons.menu_book_rounded,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : Image.network(
                        book.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const ColoredBox(
                            color: Colors.black,
                            child: Center(
                              child: Icon(
                                Icons.menu_book_rounded,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF11121A),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.author,
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF565B66),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _AvailabilityPill(book: book),
                    ],
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

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill({required this.book});

  final _DashboardBookRecord book;

  @override
  Widget build(BuildContext context) {
    final color = book.availableCopies > 0
        ? const Color(0xFF19A7A1)
        : const Color(0xFFE43C44);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${book.availableCopies}/${book.totalCopies}',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TransactionHistoryPage extends StatefulWidget {
  const _TransactionHistoryPage({
    required this.title,
    required this.stream,
    required this.emptyMessage,
    required this.statusFilter,
    this.showClearButton = true,
  });

  final String title;
  final Stream<List<_BorrowerRecord>> stream;
  final String emptyMessage;

  /// Statuses to delete when clearing. Pass null to delete ALL records.
  final List<String>? statusFilter;

  /// Whether to show the Clear History button.
  final bool showClearButton;

  @override
  State<_TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<_TransactionHistoryPage> {
  bool _isClearing = false;

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Clear History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to clear all ${widget.title.toLowerCase()} records? This cannot be undone.',
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
    await _clearHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _isClearing = true);
    try {
      final col = FirebaseFirestore.instance.collection('borrow_records');
      Query<Map<String, dynamic>> query = col;
      if (widget.statusFilter != null) {
        query = query.where('status', whereIn: widget.statusFilter);
      }
      final snapshot = await query.get();
      final batch = FirebaseFirestore.instance.batch();

      // Returned-only clear: soft-hide so records still appear in
      // Transaction History. Full history clear: hard-delete.
      final isReturnedOnly =
          widget.statusFilter != null &&
          widget.statusFilter!.every((s) => s == 'returned' || s == 'return');

      for (final doc in snapshot.docs) {
        if (isReturnedOnly) {
          batch.update(doc.reference, {'hiddenInReturned': true});
        } else {
          batch.delete(doc.reference);
        }
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('History cleared.'),
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
      if (mounted) setState(() => _isClearing = false);
    }
  }

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
                    _HistoryTopBar(
                      title: widget.title,
                      trailing: !widget.showClearButton
                          ? null
                          : _isClearing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFE53935),
                              ),
                            )
                          : _AniyomiTapResponse(
                              onTap: _confirmClear,
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFE53935),
                                size: 28,
                              ),
                            ),
                    ),
                    const SizedBox(height: 18),
                    StreamBuilder<List<_BorrowerRecord>>(
                      stream: widget.stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const _DashboardMessage(
                            icon: Icons.error_outline_rounded,
                            message: 'Could not load history.',
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
                          return _DashboardMessage(
                            icon: Icons.history_rounded,
                            message: widget.emptyMessage,
                          );
                        }

                        // For History (statusFilter == null) AND Returned Books,
                        // group records by (studentId + bookId) so the same student
                        // returning the same book multiple times shows as one card
                        // with past records inside the detail popup.
                        final isReturned =
                            widget.statusFilter != null &&
                            widget.statusFilter!.every(
                              (s) => s == 'returned' || s == 'return',
                            );
                        final isHistory = widget.statusFilter == null;

                        if (isHistory || isReturned) {
                          // Build a map: key → list of records (sorted newest first).
                          // We use userId (the unique account UID) as the primary
                          // account identifier so that two different accounts who
                          // borrow the same book never get merged into the same card.
                          // Falls back to recordId so an unknown-userId record always
                          // gets its own card rather than being lumped with others.
                          final grouped = <String, List<_BorrowerRecord>>{};
                          for (final r in records) {
                            // Primary account key: prefer userId (Firebase UID),
                            // then studentId only when it is a real value (not 'N/A'),
                            // then fall back to the recordId so the record is never merged.
                            final accountKey = r.userId.isNotEmpty
                                ? r.userId
                                : (r.studentId != 'N/A' &&
                                      r.studentId.isNotEmpty)
                                ? 'sid__${r.studentId}'
                                : 'rec__${r.recordId}';
                            final bookKey = r.bookId.isNotEmpty
                                ? r.bookId
                                : r.bookTitle;
                            final key = '${accountKey}__$bookKey';
                            grouped.putIfAbsent(key, () => []).add(r);
                          }

                          final groupKeys = grouped.keys.toList()
                            ..sort((a, b) {
                              final aTop = grouped[a]!.first.borrowedAtMillis;
                              final bTop = grouped[b]!.first.borrowedAtMillis;
                              return bTop.compareTo(aTop);
                            });

                          return Column(
                            children: groupKeys.map((key) {
                              final group = grouped[key]!;
                              // Most recent is the "current" card; rest are past records
                              final latest = group.first;
                              final past = group.length > 1
                                  ? group.sublist(1)
                                  : <_BorrowerRecord>[];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _HistoryTransactionCard(
                                  record: latest,
                                  pastRecords: past,
                                ),
                              );
                            }).toList(),
                          );
                        }

                        return Column(
                          children: records
                              .map(
                                (record) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: _HistoryTransactionCard(
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

class _HistoryTopBar extends StatelessWidget {
  const _HistoryTopBar({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          _AniyomiTapResponse(
            onTap: () => Navigator.pop(context),
            child: const SizedBox.square(
              dimension: 44,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Color(0xFF121926),
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _HistoryTransactionCard extends StatelessWidget {
  const _HistoryTransactionCard({
    required this.record,
    this.pastRecords = const [],
  });

  final _BorrowerRecord record;
  final List<_BorrowerRecord> pastRecords;

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _BorrowerDetailSheet(record: record, pastRecords: pastRecords),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 58,
                  height: 72,
                  child: record.coverUrl.isEmpty
                      ? const ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Icon(
                              Icons.menu_book_rounded,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : Image.network(
                          record.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Colors.black,
                              child: Center(
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
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
                        _StatusPill(record: record),
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
                    if (pastRecords.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                            Icons.history_rounded,
                            size: 12,
                            color: const Color(0xFF8A93A2),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${pastRecords.length} past record${pastRecords.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: Color(0xFF8A93A2),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ), // closes Material
    ); // closes _AniyomiTapResponse
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.record});

  final _BorrowerRecord record;

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

class _LibrarianAvatar extends StatelessWidget {
  const _LibrarianAvatar({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'L' : name.trim()[0].toUpperCase();

    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0F2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _DefaultLibrarianAvatar(initial: initial);
                },
              )
            : _DefaultLibrarianAvatar(initial: initial),
      ),
    );
  }
}

class _DefaultLibrarianAvatar extends StatelessWidget {
  const _DefaultLibrarianAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2BA6A3), Color(0xFF4B23C6)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 7,
            child: Icon(
              Icons.local_library_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStatCard extends StatelessWidget {
  const _DashboardStatCard({
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

class _BorrowerCard extends StatelessWidget {
  const _BorrowerCard({required this.record});

  final _BorrowerRecord record;

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BorrowerDetailSheet(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AniyomiTapResponse(
      onTap: () => _showDetail(context),
      child: Material(
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
            ],
          ),
        ),
      ), // closes Material
    ); // closes _AniyomiTapResponse
  }
}

// ─── Borrower Detail Bottom Sheet ───────────────────────────────────────────

class _BorrowerDetailSheet extends StatefulWidget {
  const _BorrowerDetailSheet({
    required this.record,
    this.pastRecords = const [],
  });

  final _BorrowerRecord record;
  final List<_BorrowerRecord> pastRecords;

  @override
  State<_BorrowerDetailSheet> createState() => _BorrowerDetailSheetState();
}

class _BorrowerDetailSheetState extends State<_BorrowerDetailSheet> {
  // Resolved photo URL: starts with whatever is on the borrow record,
  // then gets overwritten with the user's Firestore profile photo if found.
  String _resolvedPhotoUrl = '';
  bool _photoLoaded = false;

  @override
  void initState() {
    super.initState();
    _resolvedPhotoUrl = widget.record.studentPhotoUrl;
    _fetchProfilePhoto();
  }

  /// Looks up the `users` collection to get the student's profile photo.
  /// Tries by userId (uid) first, then falls back to querying by schoolId/name.
  Future<void> _fetchProfilePhoto() async {
    final record = widget.record;

    try {
      // 1. Fastest path — direct uid lookup
      if (record.userId.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(record.userId)
            .get();
        final url = _resolvePhotoFromData(doc.data());
        if (url.isNotEmpty && mounted) {
          setState(() {
            _resolvedPhotoUrl = url;
            _photoLoaded = true;
          });
          return;
        }
      }

      // 2. Fallback — query by schoolId
      if (record.studentId != 'N/A' && record.studentId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('schoolId', isEqualTo: record.studentId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final url = _resolvePhotoFromData(snap.docs.first.data());
          if (url.isNotEmpty && mounted) {
            setState(() {
              _resolvedPhotoUrl = url;
              _photoLoaded = true;
            });
            return;
          }
        }
      }

      // 3. Last fallback — query by name
      if (record.borrowerName.isNotEmpty &&
          record.borrowerName != 'Student borrower') {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('name', isEqualTo: record.borrowerName)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final url = _resolvePhotoFromData(snap.docs.first.data());
          if (url.isNotEmpty && mounted) {
            setState(() {
              _resolvedPhotoUrl = url;
              _photoLoaded = true;
            });
            return;
          }
        }
      }
    } catch (_) {
      // silently ignore — we already have whatever was on the borrow record
    }

    if (mounted) setState(() => _photoLoaded = true);
  }

  String _resolvePhotoFromData(Map<String, dynamic>? data) {
    if (data == null) return '';
    final url = data['photoUrl'] ?? data['profileImageUrl'] ?? '';
    if (url is String && url.trim().isNotEmpty) return url.trim();
    return '';
  }

  /// Returns "Jan 5, 2025 • 2:34 PM" or "N/A"
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
    final record = widget.record;
    final initial = record.borrowerName.trim().isEmpty
        ? 'S'
        : record.borrowerName.trim()[0].toUpperCase();

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
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
                    'Borrower Details',
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
                  // ── Student profile card ──────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
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
                        // avatar — shimmer while loading, then real photo
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF2BA6A3),
                              width: 2.5,
                            ),
                          ),
                          child: ClipOval(
                            child: !_photoLoaded
                                ? _ShimmerCircle()
                                : _resolvedPhotoUrl.isNotEmpty
                                ? Image.network(
                                    _resolvedPhotoUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        _StudentInitialAvatar(initial: initial),
                                  )
                                : _StudentInitialAvatar(initial: initial),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.borrowerName,
                                style: const TextStyle(
                                  color: Color(0xFF11121A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.badge_outlined,
                                    size: 14,
                                    color: Color(0xFF2BA6A3),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'ID: ${record.studentId}',
                                    style: const TextStyle(
                                      color: Color(0xFF565B66),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                              if (record.course.isNotEmpty ||
                                  record.section.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.school_outlined,
                                      size: 14,
                                      color: Color(0xFF2BA6A3),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        [
                                          if (record.course.isNotEmpty)
                                            record.course,
                                          if (record.section.isNotEmpty)
                                            record.section,
                                        ].join(' – '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF565B66),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              _StatusPillLarge(record: record),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Book info card ────────────────────────────────────
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
                                ? const ColoredBox(
                                    color: Colors.black,
                                    child: Center(
                                      child: Icon(
                                        Icons.menu_book_rounded,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                  )
                                : Image.network(
                                    record.coverUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(
                                          color: Colors.black,
                                          child: Center(
                                            child: Icon(
                                              Icons.menu_book_rounded,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                          ),
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
                                'Book Borrowed',
                                style: TextStyle(
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
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Borrow / Return dates card ────────────────────────
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
                        _DateInfoRow(
                          icon: Icons.login_rounded,
                          label: 'Borrowed On',
                          value: _formatDateTime(record.borrowedAtMillis),
                          valueColor: const Color(0xFF11121A),
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        // ── Due Date ──────────────────────────────────────
                        _DateInfoRow(
                          icon: Icons.event_rounded,
                          label: 'Due Date',
                          value: record.dueDateMillis == 0
                              ? 'N/A'
                              : _formatDateTime(record.dueDateMillis),
                          valueColor: record.isOverdue
                              ? const Color(0xFFE43C44)
                              : const Color(0xFF2BA6A3),
                          trailingBadge: record.isOverdue && !record.isReturned
                              ? 'OVERDUE'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        const Divider(height: 1, color: Color(0xFFE4E7EC)),
                        const SizedBox(height: 14),
                        _DateInfoRow(
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
                  // ── Past Records (shown when same student borrowed same book before) ──
                  if (widget.pastRecords.isNotEmpty) ...[
                    const SizedBox(height: 16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF4B23C6,
                                  ).withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.history_rounded,
                                  size: 18,
                                  color: Color(0xFF4B23C6),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Past Records',
                                    style: TextStyle(
                                      color: Color(0xFF11121A),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  Text(
                                    '${widget.pastRecords.length} previous borrow${widget.pastRecords.length == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                      color: Color(0xFF8A93A2),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1, color: Color(0xFFE4E7EC)),
                          ...widget.pastRecords.asMap().entries.map((entry) {
                            final i = entry.key;
                            final past = entry.value;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 14),
                                // Record number label
                                Text(
                                  'Record #${i + 1}',
                                  style: const TextStyle(
                                    color: Color(0xFF4B23C6),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _DateInfoRow(
                                  icon: Icons.login_rounded,
                                  label: 'Borrowed On',
                                  value: _formatDateTime(past.borrowedAtMillis),
                                  valueColor: const Color(0xFF11121A),
                                ),
                                const SizedBox(height: 10),
                                _DateInfoRow(
                                  icon: Icons.logout_rounded,
                                  label: 'Returned On',
                                  value: past.isReturned
                                      ? _formatDateTime(past.returnedAtMillis)
                                      : 'Not yet returned',
                                  valueColor: past.isReturned
                                      ? const Color(0xFF4B23C6)
                                      : const Color(0xFF8A93A2),
                                ),
                                if (i < widget.pastRecords.length - 1) ...[
                                  const SizedBox(height: 14),
                                  const Divider(
                                    height: 1,
                                    color: Color(0xFFE4E7EC),
                                  ),
                                ],
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsing shimmer placeholder while the profile photo is loading.
class _ShimmerCircle extends StatefulWidget {
  @override
  State<_ShimmerCircle> createState() => _ShimmerCircleState();
}

class _ShimmerCircleState extends State<_ShimmerCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => DecoratedBox(
        decoration: BoxDecoration(
          color: Color.lerp(
            const Color(0xFFE4E7EC),
            const Color(0xFFF7F8FA),
            _ctrl.value,
          )!,
        ),
      ),
    );
  }
}

class _StudentInitialAvatar extends StatelessWidget {
  const _StudentInitialAvatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2BA6A3), Color(0xFF4B23C6)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _StatusPillLarge extends StatelessWidget {
  const _StatusPillLarge({required this.record});

  final _BorrowerRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                : Icons.bookmark_added_rounded,
            size: 13,
            color: record.statusColor,
          ),
          const SizedBox(width: 5),
          Text(
            record.statusLabel,
            style: TextStyle(
              color: record.statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateInfoRow extends StatelessWidget {
  const _DateInfoRow({
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

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({required this.icon, required this.message});

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

class _BorrowerRecord {
  const _BorrowerRecord({
    required this.bookTitle,
    required this.author,
    required this.borrowerName,
    required this.coverUrl,
    required this.borrowedAtMillis,
    required this.status,
    required this.studentId,
    required this.studentPhotoUrl,
    required this.returnedAtMillis,
    required this.course,
    required this.section,
    required this.userId,
    required this.bookId,
    required this.recordId,
  });

  final String bookTitle;
  final String author;
  final String borrowerName;
  final String coverUrl;
  final int borrowedAtMillis;
  final String status;
  final String studentId;
  final String studentPhotoUrl;
  final int returnedAtMillis;
  final String course;
  final String section;
  // uid of the borrower in the 'users' collection — used to fetch profile photo
  final String userId;
  // bookId and recordId used for grouping in History
  final String bookId;
  final String recordId;

  bool get isReturned => status == 'returned' || status == 'return';

  /// Due date = borrowedAt + 7 days (default loan period).
  int get dueDateMillis => borrowedAtMillis == 0
      ? 0
      : borrowedAtMillis + const Duration(days: 7).inMilliseconds;

  bool get isOverdue {
    if (isReturned || dueDateMillis == 0) return false;
    return DateTime.now().millisecondsSinceEpoch > dueDateMillis;
  }

  String get statusLabel => isReturned ? 'Returned' : 'Borrowed';

  Color get statusColor =>
      isReturned ? const Color(0xFF4B23C6) : const Color(0xFF19A7A1);

  factory _BorrowerRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    return _BorrowerRecord(
      bookTitle: _stringValue(
        data['bookTitle'] ?? data['title'],
        fallback: 'Untitled Book',
      ),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
      borrowerName: _stringValue(
        data['borrowerName'] ?? data['studentName'] ?? data['name'],
        fallback: 'Student borrower',
      ),
      coverUrl: _stringValue(
        data['cover_url'] ?? data['coverUrl'],
        fallback: '',
      ),
      // borrowedAtMillis: prefer the actual borrow timestamp fields only
      borrowedAtMillis: _timestampMillis(
        data['borrowed_at'] ??
            data['borrowedAt'] ??
            data['scanned_at'] ??
            data['scannedAt'] ??
            data['created_at'] ??
            data['createdAt'],
      ),
      status: _stringValue(data['status'], fallback: 'borrowed').toLowerCase(),
      studentId: _stringValue(
        data['studentId'] ?? data['student_id'] ?? data['idNumber'],
        fallback: 'N/A',
      ),
      // photo stored directly on the borrow record (if any)
      studentPhotoUrl: _stringValue(
        data['studentPhotoUrl'] ??
            data['studentPhoto'] ??
            data['borrowerPhotoUrl'],
        fallback: '',
      ),
      // returned timestamp — only present when the book is actually returned
      returnedAtMillis: _timestampMillis(
        data['returned_at'] ?? data['returnedAt'] ?? data['returnDate'],
      ),
      course: _stringValue(data['course'] ?? data['program'], fallback: ''),
      section: _stringValue(
        data['section'] ?? data['year_section'],
        fallback: '',
      ),
      // uid of the borrower so we can look up their profile photo
      userId: _stringValue(
        data['userId'] ??
            data['uid'] ??
            data['borrowerId'] ??
            data['studentUid'],
        fallback: '',
      ),
      bookId: _stringValue(data['bookId'] ?? data['book_id'], fallback: ''),
      recordId: doc.id,
    );
  }

  static String _stringValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
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

class _DashboardBookRecord {
  const _DashboardBookRecord({
    required this.title,
    required this.author,
    required this.category,
    required this.coverUrl,
    required this.totalCopies,
    required this.availableCopies,
    required this.createdAtMillis,
  });

  final String title;
  final String author;
  final String category;
  final String coverUrl;
  final int totalCopies;
  final int availableCopies;
  final int createdAtMillis;

  factory _DashboardBookRecord.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required int activeBorrowCount,
  }) {
    final data = doc.data();
    final totalCopies = _intValue(
      data['totalCopies'] ?? data['total_copies'] ?? data['copies'],
      fallback: 1,
    );
    final availableCopies = (totalCopies - activeBorrowCount)
        .clamp(0, totalCopies)
        .toInt();

    return _DashboardBookRecord(
      title: _stringValue(data['title'], fallback: 'Untitled Book'),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
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
      totalCopies: totalCopies,
      availableCopies: availableCopies,
      createdAtMillis: _timestampMillis(
        data['created_at'] ?? data['createdAt'],
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

String _stringValue(Object? value, {required String fallback}) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return fallback;
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

int _timestampMillis(Object? value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  }
  return 0;
}

/// Fallback due date for legacy borrow records that were created before the
/// explicit dueDate field existed. Returns borrowedAt + 7 days, or 0 if the
/// borrow timestamp is also missing.
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

// ─── Notification Model ──────────────────────────────────────────────────────

enum _NotificationType { newBorrow, overdue, general }

class _AppNotification {
  const _AppNotification({
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    this.recordId,
  });

  final String title;
  final String body;
  final DateTime time;
  final _NotificationType type;
  final String? recordId;
}

// ─── Notification Bottom Sheet ───────────────────────────────────────────────

class _NotificationSheet extends StatelessWidget {
  const _NotificationSheet({required this.notifications});

  final List<_AppNotification> notifications;

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  IconData _iconFor(_NotificationType type) {
    switch (type) {
      case _NotificationType.overdue:
        return Icons.warning_amber_rounded;
      case _NotificationType.newBorrow:
        return Icons.bookmark_added_rounded;
      case _NotificationType.general:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(_NotificationType type) {
    switch (type) {
      case _NotificationType.overdue:
        return const Color(0xFFE43C44);
      case _NotificationType.newBorrow:
        return const Color(0xFF2BA6A3);
      case _NotificationType.general:
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
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final n = notifications[index];
                        final color = _colorFor(n.type);
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
                                  _iconFor(n.type),
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
                                      n.title,
                                      style: const TextStyle(
                                        color: Color(0xFF11121A),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      n.body,
                                      style: const TextStyle(
                                        color: Color(0xFF565B66),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeAgo(n.time),
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
