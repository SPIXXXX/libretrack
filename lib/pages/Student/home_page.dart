import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------

// TODO: Move these models to a separate models/book.dart file when
//       the librarian dashboard is built. The librarian will manage
//       books via Firestore; these will be fetched dynamically.

class BannerBook {
  final String title;
  final String subtitle;
  final String emoji;
  final List<Color> gradient;

  const BannerBook({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradient,
  });
}

class BookItem {
  final String title;
  final String author;
  final List<Color> gradient;

  const BookItem({
    required this.title,
    required this.author,
    required this.gradient,
  });
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

  // TODO: Fetch _inProgress and _completed counts from Firestore
  //       based on the student's reading list / borrow records
  final int _inProgress = 0;
  final int _completed = 0;

  // ---------------------------------------------------------------------------
  // BANNER CAROUSEL — left empty intentionally
  // TODO: Wire this up once the librarian dashboard is built.
  //       The librarian will manage featured books via their dashboard,
  //       stored in a Firestore 'featured_books' collection.
  // Example stream:
  //   Stream<List<BannerBook>> _featuredBooks() => FirebaseFirestore.instance
  //       .collection('featured_books')
  //       .snapshots()
  //       .map((s) => s.docs.map(BannerBook.fromDoc).toList());
  // ---------------------------------------------------------------------------
  final List<BannerBook> _bannerBooks = [];
  late final PageController _pageController = PageController(
    viewportFraction: 0.88,
  );

  // ---------------------------------------------------------------------------
  // TOP READS — left empty intentionally
  // TODO: Wire this up once the librarian dashboard is built.
  //       Fetch from Firestore 'books' collection filtered by a
  //       'is_top_read' flag that the librarian can toggle.
  // ---------------------------------------------------------------------------
  final List<BookItem> _topReads = [];

  // ---------------------------------------------------------------------------
  // RECOMMENDED — left empty intentionally
  // TODO: Wire this up once the librarian dashboard is built.
  //       The librarian can curate recommendations, or generate them
  //       automatically based on the student's borrow history in Firestore.
  // ---------------------------------------------------------------------------
  final List<BookItem> _recommended = [];

  late Timer _carouselTimer;

  @override
  void initState() {
    super.initState();
    _loadExampleBooks();
    _startCarouselAutoScroll();
  }

  void _loadExampleBooks() {
    // TODO: Delete this method and fetch real data from Firestore instead
    _bannerBooks.addAll([
      BannerBook(
        title: 'Big Book of Science Experiments',
        subtitle: 'Janice VanCleave · Featured',
        emoji: '📚',
        gradient: const [Color(0xFF1a237e), Color(0xFF2BA6A3)],
      ),
      BannerBook(
        title: 'Dart for Absolute Beginners',
        subtitle: 'David Kopec · New arrival',
        emoji: '🔥',
        gradient: const [Color(0xFF4a1b0c), Color(0xFFd85a30)],
      ),
      BannerBook(
        title: 'Data Structures & Algorithms',
        subtitle: 'Rudolph Russell · Popular',
        emoji: '🧠',
        gradient: const [Color(0xFF3C3489), Color(0xFF7F77DD)],
      ),
    ]);

    // TODO: Delete this and fetch from Firestore 'books' collection
    _topReads.addAll([
      BookItem(
        title: 'Dart for Absolute Beginners',
        author: 'David Kopec',
        gradient: const [Color(0xFF0d0d0d), Color(0xFF1a1a2e)],
      ),
      BookItem(
        title: 'Big Book of Science Experiments',
        author: 'Janice VanCleave',
        gradient: const [Color(0xFF003366), Color(0xFF1D9E75)],
      ),
      BookItem(
        title: 'Data Structures & Algorithms',
        author: 'Rudolph Russell',
        gradient: const [Color(0xFF185FA5), Color(0xFFE3E7EB)],
      ),
      BookItem(
        title: 'The Midnight Library',
        author: 'Matt Haig',
        gradient: const [Color(0xFF0d1b36), Color(0xFF1a3a52)],
      ),
      BookItem(
        title: 'Atomic Habits',
        author: 'James Clear',
        gradient: const [Color(0xFF2d1b0d), Color(0xFF5a3a2d)],
      ),
      BookItem(
        title: 'Educated',
        author: 'Tara Westover',
        gradient: const [Color(0xFF1a0d2d), Color(0xFF3d1a5a)],
      ),
      BookItem(
        title: 'The Silent Patient',
        author: 'Alex Michaelides',
        gradient: const [Color(0xFF001a33), Color(0xFF004d66)],
      ),
      BookItem(
        title: 'Dune',
        author: 'Frank Herbert',
        gradient: const [Color(0xFF3d2610), Color(0xFF8b5a1d)],
      ),
      BookItem(
        title: 'Project Hail Mary',
        author: 'Andy Weir',
        gradient: const [Color(0xFF1a1a3d), Color(0xFF4d4d99)],
      ),
      BookItem(
        title: 'Circe',
        author: 'Madeline Miller',
        gradient: const [Color(0xFF2d1a1a), Color(0xFF7a4d4d)],
      ),
      BookItem(
        title: 'The Subtle Art of Not Giving a F*ck',
        author: 'Mark Manson',
        gradient: const [Color(0xFF0d2d1a), Color(0xFF1a6d4d)],
      ),
      BookItem(
        title: 'Piranesi',
        author: 'Susanna Clarke',
        gradient: const [Color(0xFF1a1a2d), Color(0xFF4d4d7a)],
      ),
    ]);

    // TODO: Delete this and fetch from Firestore recommendations engine
    _recommended.addAll([
      BookItem(
        title: 'Dart for Absolute Beginners',
        author: 'David Kopec',
        gradient: const [Color(0xFF0d0d0d), Color(0xFF2c1a1a)],
      ),
      BookItem(
        title: 'Big Book of Science Experiments',
        author: 'Janice VanCleave',
        gradient: const [Color(0xFF0d2236), Color(0xFF1D9E75)],
      ),
      BookItem(
        title: 'Data Structures & Algorithms',
        author: 'Rudolph Russell',
        gradient: const [Color(0xFF1a0533), Color(0xFF3C13C5)],
      ),
      BookItem(
        title: 'Thinking, Fast and Slow',
        author: 'Daniel Kahneman',
        gradient: const [Color(0xFF1a1a0d), Color(0xFF4d4d2d)],
      ),
      BookItem(
        title: 'The Thursday Murder Club',
        author: 'Richard Osman',
        gradient: const [Color(0xFF2d1a0d), Color(0xFF6b4d2d)],
      ),
      BookItem(
        title: 'Braiding Sweetgrass',
        author: 'Robin Wall Kimmerer',
        gradient: const [Color(0xFF0d2d1a), Color(0xFF2d7a52)],
      ),
      BookItem(
        title: 'The Martian',
        author: 'Andy Weir',
        gradient: const [Color(0xFF2d1a0d), Color(0xFF8b5a1d)],
      ),
      BookItem(
        title: 'Klara and the Sun',
        author: 'Kazuo Ishiguro',
        gradient: const [Color(0xFF0d1a2d), Color(0xFF2d5a8b)],
      ),
      BookItem(
        title: 'The Midnight Bargain',
        author: 'C. L. Polk',
        gradient: const [Color(0xFF1a0d2d), Color(0xFF5a2d8b)],
      ),
      BookItem(
        title: 'Lessons in Chemistry',
        author: 'Bonnie Garmus',
        gradient: const [Color(0xFF2d0d0d), Color(0xFF8b2d2d)],
      ),
      BookItem(
        title: 'The House in the Cerulean Sea',
        author: 'TJ Klune',
        gradient: const [Color(0xFF0d1a3d), Color(0xFF1a4d99)],
      ),
      BookItem(
        title: 'Home Fire',
        author: 'Kamila Shamsie',
        gradient: const [Color(0xFF3d0d1a), Color(0xFF8b1a3d)],
      ),
    ]);
  }

  void _startCarouselAutoScroll() {
    if (_bannerBooks.isEmpty) return;

    _carouselTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (_pageController.hasClients) {
        final nextPage = (_currentBanner + 1) % _bannerBooks.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshHome() async {
    // TODO: Fetch latest featured books, stats, top reads, and recommendations.
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
            _buildBannerCarousel(),
            if (_bannerBooks.isNotEmpty) _buildDots(),
            _buildStatsRow(),
            _buildSectionHeader(
              'Your Top Reads',
              showSeeAll: _topReads.isNotEmpty,
              onSeeAll: () {
                // TODO: Navigate to full book list page
              },
            ),
            _buildBookRow(_topReads),
            const SizedBox(height: 10),
            _buildSectionHeader(
              'Recommended for you',
              showSeeAll: _recommended.isNotEmpty,
              onSeeAll: () {
                // TODO: Navigate to full book list page
              },
            ),
            _buildBookRow(_recommended),
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

  Widget _buildBannerCarousel() {
    if (_bannerBooks.isEmpty) {
      // Placeholder shown until the librarian adds featured books
      // TODO: Remove this placeholder once librarian dashboard is connected
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
                'Featured books will appear here',
                style: TextStyle(fontSize: 12, color: Color(0xFFA0A8B9)),
              ),
              Text(
                'Managed by the librarian dashboard',
                style: TextStyle(fontSize: 10, color: Color(0xFFC0C8D9)),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 155,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _bannerBooks.length,
        onPageChanged: (i) => setState(() => _currentBanner = i),
        itemBuilder: (_, i) {
          final book = _bannerBooks[i];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _BannerCard(book: book),
          );
        },
      ),
    );
  }

  Widget _buildDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_bannerBooks.length, (i) {
          final isActive = i == _currentBanner;
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
  // STATS
  // ---------------------------------------------------------------------------

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.menu_book_rounded,
              value: _inProgress.toString(),
              label: 'In progress',
              sub: 'Books',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.check_box_rounded,
              value: _completed.toString(),
              label: 'Completed',
              sub: 'Books',
            ),
          ),
        ],
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

  Widget _buildBookRow(List<BookItem> books) {
    if (books.isEmpty) {
      // Placeholder shown until the librarian adds books
      // TODO: Remove this placeholder once librarian dashboard is connected
      return Container(
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFD9D9D9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text(
            'No books yet — librarian will add them',
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
        itemBuilder: (_, i) => _BookCard(book: books[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUB-WIDGETS
// ---------------------------------------------------------------------------

class _BannerCard extends StatelessWidget {
  final BannerBook book;
  const _BannerCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 155,
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
          Positioned(
            right: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: 0.3,
                child: Text(book.emoji, style: const TextStyle(fontSize: 48)),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.indigo.withValues(alpha: 0.35),
                  const Color(0xFF2BA6A3).withValues(alpha: 0.35),
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String sub;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF2BA6A3), size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121926),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF121926)),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFFA0A8B9),
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final BookItem book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: () {},
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
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: book.gradient,
                            ),
                          ),
                        ),
                      ),
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
                        left: 10,
                        right: 10,
                        bottom: 11,
                        child: Text(
                          book.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.12,
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
                          child: const Icon(
                            Icons.bookmark_border_rounded,
                            color: Colors.white,
                            size: 16,
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
        IconButton(
          onPressed: () {
            // TODO: Show notifications panel.
          },
          icon: const Icon(
            Icons.notifications_outlined,
            color: Color(0xFF121926),
            size: 22,
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
