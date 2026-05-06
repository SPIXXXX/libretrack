import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage>
    with SingleTickerProviderStateMixin {
  // TODO: Connect this page to the real backend once the librarian workflow is ready.
  //
  // ARCHITECTURE:
  // - Librarian Page: Manages books, book info, categories, borrow records, and
  //   library stats. Librarians add/edit books and their metadata.
  // - Student Page (this page): Displays librarian-managed books in organized way.
  //   Students can search, filter, and view book details.
  // - PDF Module Reading: Students can open school module PDFs directly in the app
  //   for organized reading and learning.
  // - Review System: Students can write reviews, add comments, and share thoughts
  //   about books to help other students.
  //
  // DATA STORAGE BREAKDOWN:
  // - Firestore:
  //   * Book info (title, author, description, ISBN, etc.)
  //   * User data (profiles, reading preferences)
  //   * Borrow records (who borrowed what, when, due dates)
  //   * Statistics (most borrowed, user reading habits)
  //   * Reviews and comments (student feedback on books)
  // - Cloudinary:
  //   * Book cover images
  //   * Student profile photos
  // - Google Drive:
  //   * School module PDFs for in-app reading
  // - Firebase FCM:
  //   * Push notifications (borrow reminders, new books, return due dates)
  //
  // FEATURES TO IMPLEMENT:
  // 1. Sync books data from Firestore
  // 2. Load book cover images from Cloudinary
  // 3. Implement search and filter with Firestore queries
  // 4. Add review/comment UI and sync with Firestore
  // 5. Link to Google Drive PDFs for reading
  // 6. Setup borrow functionality
  // 7. Implement FCM for notifications
  int _selectedCategory = 0;
  bool _sortAZ = false;
  String _searchQuery = '';
  late final AnimationController _pageAnimation;
  late final TextEditingController _searchController;
  late final TextEditingController _categoryController;

  final List<String> _categories = [
    'Favorites',
    'Want to read',
    'Science',
    'History',
  ];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _categoryController = TextEditingController();
    _pageAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();

    // TODO: (2) Setup FCM for push notifications
    // - Request user permissions
    // - Listen for borrow reminders, new books, return due dates
    // - Handle notification routing
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryController.dispose();
    _pageAnimation.dispose();
    super.dispose();
  }

  Stream<List<_BookListItem>> _bookStream() {
    return FirebaseFirestore.instance
        .collection('books')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(_BookListItem.fromDoc).toList();
        });
  }

  List<_BookListItem> _visibleBooks(List<_BookListItem> books) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = books.where((book) {
      final matchesSearch =
          query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.description.toLowerCase().contains(query);
      return matchesSearch;
    }).toList();

    if (_sortAZ) {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    }

    return filtered;
  }

  Future<void> _refreshBooks() async {
    // TODO: Fetch the latest librarian-managed books from Firestore.
    // TODO: IMPLEMENT - Query Firebase for updated book list
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE3E7EB),
      child: RefreshIndicator(
        onRefresh: _refreshBooks,
        color: const Color(0xFF2BA6A3),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageEntrance(
                      animation: _pageAnimation,
                      begin: 0.00,
                      end: 0.45,
                      child: _buildHeader(),
                    ),
                    _PageEntrance(
                      animation: _pageAnimation,
                      begin: 0.10,
                      end: 0.55,
                      child: _buildSearchSection(),
                    ),
                    _PageEntrance(
                      animation: _pageAnimation,
                      begin: 0.20,
                      end: 0.68,
                      child: _buildProgressCards(),
                    ),
                    const SizedBox(height: 28),
                    _PageEntrance(
                      animation: _pageAnimation,
                      begin: 0.32,
                      end: 0.78,
                      child: _buildCategories(),
                    ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return StreamBuilder<List<_BookListItem>>(
                      stream: _bookStream(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _BookListMessage(
                            icon: Icons.error_outline_rounded,
                            message: 'Could not load books: ${snapshot.error}',
                          );
                        }

                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final books = _visibleBooks(snapshot.data ?? []);
                        if (books.isEmpty) {
                          return const _BookListMessage(
                            icon: Icons.library_books_outlined,
                            message: 'No books found yet.',
                          );
                        }

                        const minCardWidth = 132.0;
                        const maxCardWidth = 156.0;
                        const spacing = 18.0;
                        var cardsPerRow = 1;

                        for (var columns = 4; columns >= 1; columns--) {
                          final requiredWidth =
                              (minCardWidth * columns) +
                              (spacing * (columns - 1));
                          if (requiredWidth <= constraints.maxWidth) {
                            cardsPerRow = columns;
                            break;
                          }
                        }

                        final cardWidth =
                            ((constraints.maxWidth -
                                        (spacing * (cardsPerRow - 1))) /
                                    cardsPerRow)
                                .clamp(minCardWidth, maxCardWidth);
                        final rowWidth =
                            (cardWidth * cardsPerRow) +
                            (spacing * (cardsPerRow - 1));

                        return Center(
                          child: SizedBox(
                            width: rowWidth,
                            child: Wrap(
                              alignment: WrapAlignment.start,
                              spacing: spacing,
                              runSpacing: 30,
                              children: List.generate(books.length, (index) {
                                return SizedBox(
                                  width: cardWidth,
                                  child: _PageEntrance(
                                    animation: _pageAnimation,
                                    begin: (0.36 + (index * 0.035)).clamp(
                                      0.36,
                                      0.72,
                                    ),
                                    end: (0.80 + (index * 0.025)).clamp(
                                      0.80,
                                      1.00,
                                    ),
                                    offset: 18,
                                    child: _BookTile(book: books[index]),
                                  ),
                                );
                              }),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          const Text(
            'Book list',
            style: TextStyle(
              color: Color(0xFF121926),
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          _AniyomiIconButton(
            onPressed: _showCategoryManager,
            icon: const Icon(Icons.library_add_outlined),
            color: const Color(0xFF121926),
            iconSize: 32,
            size: 44,
            tooltip: 'Manage categories',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 38, bottom: 34),
      child: _buildSearchArea(),
    );
  }

  Widget _buildSearchArea() {
    return Row(
      children: [
        Expanded(child: _buildSearchBox()),
        const SizedBox(width: 28),
        _buildFilterButton(),
      ],
    );
  }

  Widget _buildSearchBox() {
    // TODO: (3) Implement search with Firestore queries
    // - Use Firestore full-text search or startAt/endAt queries
    // - Debounce search requests
    // - Show real-time suggestions
    // TODO: IMPLEMENT - Connect search input to Firebase queries
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9EDF3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: const TextStyle(
            color: Color(0xFFA0A8B9),
            fontSize: 17,
            fontWeight: FontWeight.w300,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFFA0A8B9),
            size: 28,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : _AniyomiIconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFFA0A8B9),
                  iconSize: 24,
                  size: 44,
                  tooltip: 'Clear search',
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }

  Widget _buildFilterButton() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE9EDF3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _AniyomiIconButton(
        onPressed: _showFilterSheet,
        icon: const Icon(Icons.tune_rounded),
        color: _sortAZ ? const Color(0xFF2BA6A3) : const Color(0xFFA0A8B9),
        iconSize: 28,
        size: 58,
        tooltip: 'Filter',
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateSort(bool value) {
              setSheetState(() => _sortAZ = value);
              setState(() {});
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Filter books',
                          style: TextStyle(
                            color: Color(0xFF121926),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        _AniyomiIconButton(
                          onPressed: () {
                            updateSort(false);
                          },
                          icon: const Icon(Icons.restart_alt_rounded),
                          color: const Color(0xFF121926),
                          size: 44,
                          tooltip: 'Reset filters',
                        ),
                      ],
                    ),
                    SwitchListTile(
                      value: _sortAZ,
                      onChanged: updateSort,
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: const Color(0xFF2BA6A3),
                      title: const Text(
                        'Sort A-Z',
                        style: TextStyle(
                          color: Color(0xFF121926),
                          fontWeight: FontWeight.w700,
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

  void _showCategoryManager() {
    _categoryController.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void addCategory() {
              final category = _categoryController.text.trim();
              if (category.isEmpty) {
                return;
              }

              setState(() {
                _categories.add(category);
                _selectedCategory = _categories.length - 1;
              });
              setSheetState(() {});
              _categoryController.clear();
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                18,
                24,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customize categories',
                      style: TextStyle(
                        color: Color(0xFF121926),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(_categories.length, (index) {
                        return _FilterChipButton(
                          label: _categories[index],
                          selected: index == _selectedCategory,
                          onTap: () {
                            setState(() => _selectedCategory = index);
                            setSheetState(() {});
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _categoryController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => addCategory(),
                            decoration: InputDecoration(
                              hintText: 'Add category',
                              filled: true,
                              fillColor: const Color(0xFFF5F7FA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _AniyomiTapResponse(
                          onTap: addCategory,
                          child: Container(
                            height: 54,
                            width: 54,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2BA6A3),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildProgressCards() {
    // TODO: (6) Setup borrow functionality
    // - Fetch user's borrow records from Firestore
    // - Calculate reading stats (in progress, completed)
    // - Show borrow history and due dates
    // - Add borrow/return buttons
    // TODO: IMPLEMENT - Fetch borrow records from Firebase
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final spacing = compact ? 14.0 : 22.0;
        return Row(
          children: [
            Expanded(
              child: _ProgressCard(
                icon: Icons.menu_book_rounded,
                title: 'In progress',
                count: '0 Books',
                compact: compact,
              ),
            ),
            SizedBox(width: spacing),
            Expanded(
              child: _ProgressCard(
                icon: Icons.bookmark_rounded,
                title: compact ? 'Completed\nbooks' : 'Completed books',
                count: '1 Books',
                compact: compact,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategories() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFA0A8B9), width: 1.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: List.generate(_categories.length, (index) {
            final isSelected = _selectedCategory == index;
            return Padding(
              padding: EdgeInsets.only(
                right: index == _categories.length - 1 ? 0 : 28,
              ),
              child: _AniyomiTapResponse(
                onTap: () => setState(() => _selectedCategory = index),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? const Color(0xFF2BA6A3)
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _categories[index],
                      maxLines: 1,
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xFF2BA6A3)
                            : const Color(0xFF121926),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _AniyomiTapResponse(
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
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          style: TextStyle(
            color: selected ? const Color(0xFF197C79) : const Color(0xFF121926),
            fontWeight: FontWeight.w700,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _AniyomiIconButton extends StatelessWidget {
  const _AniyomiIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.iconSize = 24,
    this.size = 44,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String tooltip;
  final Color color;
  final double iconSize;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _AniyomiTapResponse(
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: IconTheme(
              data: IconThemeData(color: color, size: iconSize),
              child: icon,
            ),
          ),
        ),
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
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.icon,
    required this.title,
    required this.count,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 34.0 : 44.0;

    return Container(
      height: compact ? 96 : 112,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 9 : 12,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2BA6A3), size: iconSize),
          SizedBox(width: compact ? 7 : 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF121926),
                    fontSize: compact ? 11 : 14,
                    height: 1.1,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF121926),
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: const Color(0xFF121926),
            size: compact ? 20 : 24,
          ),
        ],
      ),
    );
  }
}

class _PageEntrance extends StatelessWidget {
  const _PageEntrance({
    required this.animation,
    required this.child,
    required this.begin,
    required this.end,
    this.offset = 24,
  });

  final Animation<double> animation;
  final Widget child;
  final double begin;
  final double end;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        child: child,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, offset * (1 - curved.value)),
            child: child,
          );
        },
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});

  final _BookListItem book;

  @override
  Widget build(BuildContext context) {
    return _AniyomiTapResponse(
      onTap: () => _showBookDetails(context, book),
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
                    Positioned.fill(child: _BookCover(book: book)),
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
    );
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final _BookListItem book;

  @override
  Widget build(BuildContext context) {
    if (book.coverUrl.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A237E), Color(0xFF2BA6A3)],
          ),
        ),
        child: Center(
          child: Icon(Icons.menu_book_rounded, color: Colors.white, size: 36),
        ),
      );
    }

    return Image.network(
      book.coverUrl,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) {
        return const ColoredBox(
          color: Color(0xFF2BA6A3),
          child: Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.white),
          ),
        );
      },
    );
  }
}

class _BookListItem {
  const _BookListItem({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.isbn,
    required this.coverUrl,
    required this.pdfUrl,
  });

  factory _BookListItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _BookListItem(
      id: doc.id,
      title: _stringValue(data['title'], fallback: 'Untitled Book'),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
      description: _stringValue(data['description'], fallback: ''),
      isbn: _stringValue(data['isbn'], fallback: ''),
      coverUrl: _stringValue(
        data['cover_url'],
        fallback: _stringValue(data['coverUrl'], fallback: ''),
      ),
      pdfUrl: _stringValue(
        data['pdf_url'],
        fallback: _stringValue(data['pdfUrl'], fallback: ''),
      ),
    );
  }

  final String id;
  final String title;
  final String author;
  final String description;
  final String isbn;
  final String coverUrl;
  final String pdfUrl;

  static String _stringValue(Object? value, {required String fallback}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }
}

class _BookListMessage extends StatelessWidget {
  const _BookListMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 38),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 42, color: const Color(0xFFA0A8B9)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF737B8C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showBookDetails(BuildContext context, _BookListItem book) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: AspectRatio(
                      aspectRatio: 0.68,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _BookCover(book: book),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: const TextStyle(
                            color: Color(0xFF121926),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          book.author,
                          style: const TextStyle(
                            color: Color(0xFF737B8C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (book.isbn.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            'ISBN ${book.isbn}',
                            style: const TextStyle(
                              color: Color(0xFFA0A8B9),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (book.description.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  book.description,
                  style: const TextStyle(
                    color: Color(0xFF394150),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: book.pdfUrl.isEmpty
                      ? null
                      : () => _openPdf(context, book.pdfUrl),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Read PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3C13C5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _openPdf(BuildContext context, String pdfUrl) async {
  final uri = Uri.tryParse(pdfUrl);
  if (uri == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invalid PDF link.')));
    return;
  }

  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open PDF.')));
  }
}
