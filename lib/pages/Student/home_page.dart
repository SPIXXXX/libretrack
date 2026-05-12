import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Student/book_details_page.dart';
import 'package:libretrack/pages/Student/book_list_page.dart';
import 'package:libretrack/pages/Student/explore_page.dart';
import 'package:libretrack/pages/Student/profile_page.dart';
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
  Timer? _bannerAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      StudentLibraryService.ensureDefaultCategory(user.uid);
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

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _HomeHeaderContent(
        name: 'Student',
        photoUrl: '',
        onProfileTap: () {},
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
          );
        },
      ),
    );
  }

  String _profileValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
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

class _HomeHeaderContent extends StatelessWidget {
  const _HomeHeaderContent({
    required this.name,
    required this.photoUrl,
    required this.onProfileTap,
  });

  final String name;
  final String photoUrl;
  final VoidCallback onProfileTap;

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
      ],
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
