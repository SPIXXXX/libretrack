import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Student/book_details_page.dart';
import 'package:libretrack/services/student_library_service.dart';

class BookListPage extends StatefulWidget {
  const BookListPage({super.key});

  @override
  State<BookListPage> createState() => _BookListPageState();
}

class _BookListPageState extends State<BookListPage>
    with SingleTickerProviderStateMixin {
  // TODO: Connect this page to the real backend once the librarian workflow is ready.

  int _selectedCategory = 0;
  bool _sortAZ = false;
  String _searchQuery = '';
  late final AnimationController _pageAnimation;
  late final TextEditingController _searchController;
  late final TextEditingController _categoryController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _categoryController = TextEditingController();
    _pageAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..forward();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      StudentLibraryService.ensureDefaultCategory(user.uid);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryController.dispose();
    _pageAnimation.dispose();
    super.dispose();
  }

  Stream<List<_BookListItem>> _bookStream() {
    return FirebaseFirestore.instance.collection('books').snapshots().map((
      snapshot,
    ) {
      final books = snapshot.docs.map(_BookListItem.fromDoc).toList();
      books.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return books;
    });
  }

  List<_BookListItem> _visibleBooks(
    List<_BookListItem> books, {
    required Map<String, StudentBookLibraryEntry> libraryEntries,
    required String selectedCategory,
  }) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = books.where((book) {
      final entry = libraryEntries[book.id];
      final matchesCategory =
          entry != null && entry.categories.contains(selectedCategory);
      final matchesSearch =
          query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.description.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const ColoredBox(
        color: Color(0xFFE3E7EB),
        child: _BookListMessage(
          icon: Icons.person_off_outlined,
          message: 'Please log in to view your books.',
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFFE3E7EB),
      child: StreamBuilder<List<String>>(
        stream: StudentLibraryService.categoriesStream(user.uid),
        builder: (context, categorySnapshot) {
          final categories =
              categorySnapshot.data ?? [StudentLibraryService.favorites];
          final selectedIndex = _selectedCategory < categories.length
              ? _selectedCategory
              : 0;
          final selectedCategory = categories[selectedIndex];

          return StreamBuilder<Map<String, StudentBookLibraryEntry>>(
            stream: StudentLibraryService.libraryEntriesStream(user.uid),
            builder: (context, librarySnapshot) {
              final libraryEntries = librarySnapshot.data ?? {};

              return RefreshIndicator(
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
                              child: _buildHeader(categories),
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
                              child: _buildCategories(
                                categories: categories,
                                selectedIndex: selectedIndex,
                              ),
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
                                    message:
                                        'Could not load books: ${snapshot.error}',
                                  );
                                }

                                if (snapshot.connectionState ==
                                        ConnectionState.waiting &&
                                    !snapshot.hasData) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                final books = _visibleBooks(
                                  snapshot.data ?? [],
                                  libraryEntries: libraryEntries,
                                  selectedCategory: selectedCategory,
                                );
                                if (books.isEmpty) {
                                  return _BookListMessage(
                                    icon: Icons.library_books_outlined,
                                    message:
                                        'No books in $selectedCategory yet.',
                                  );
                                }

                                return _buildBookGrid(
                                  constraints: constraints,
                                  books: books,
                                  libraryEntries: libraryEntries,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBookGrid({
    required BoxConstraints constraints,
    required List<_BookListItem> books,
    required Map<String, StudentBookLibraryEntry> libraryEntries,
  }) {
    const minCardWidth = 132.0;
    const maxCardWidth = 156.0;
    const spacing = 18.0;
    var cardsPerRow = 1;

    for (var columns = 4; columns >= 1; columns--) {
      final requiredWidth =
          (minCardWidth * columns) + (spacing * (columns - 1));
      if (requiredWidth <= constraints.maxWidth) {
        cardsPerRow = columns;
        break;
      }
    }

    final cardWidth =
        ((constraints.maxWidth - (spacing * (cardsPerRow - 1))) / cardsPerRow)
            .clamp(minCardWidth, maxCardWidth);
    final rowWidth = (cardWidth * cardsPerRow) + (spacing * (cardsPerRow - 1));

    return Center(
      child: SizedBox(
        width: rowWidth,
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: spacing,
          runSpacing: 30,
          children: List.generate(books.length, (index) {
            final book = books[index];
            return SizedBox(
              width: cardWidth,
              child: _PageEntrance(
                animation: _pageAnimation,
                begin: (0.36 + (index * 0.035)).clamp(0.36, 0.72),
                end: (0.80 + (index * 0.025)).clamp(0.80, 1.00),
                offset: 18,
                child: _BookTile(
                  book: book,
                  isFavorite: libraryEntries[book.id]?.isFavorite ?? false,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHeader(List<String> categories) {
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
            onPressed: () => _showCategoryManager(categories),
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

  void _showCategoryManager(List<String> categories) {
    _categoryController.clear();
    final sheetCategories = [...categories];
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
            Future<void> addCategory() async {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) {
                return;
              }

              final category = _categoryController.text.trim();
              if (category.isEmpty) {
                return;
              }

              final alreadyExists = sheetCategories.any(
                (value) => value.toLowerCase() == category.toLowerCase(),
              );
              if (alreadyExists) {
                return;
              }

              setState(() {
                _selectedCategory = sheetCategories.length;
              });
              sheetCategories.add(category);
              _categoryController.clear();
              await StudentLibraryService.addCategory(
                uid: user.uid,
                category: category,
              );
              setSheetState(() {});
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
                      children: List.generate(sheetCategories.length, (index) {
                        return _FilterChipButton(
                          label: sheetCategories[index],
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
                          onTap: () => addCategory(),
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

  Widget _buildCategories({
    required List<String> categories,
    required int selectedIndex,
  }) {
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
          children: List.generate(categories.length, (index) {
            final isSelected = selectedIndex == index;
            return Padding(
              padding: EdgeInsets.only(
                right: index == categories.length - 1 ? 0 : 28,
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
                      categories[index],
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
  const _BookTile({required this.book, required this.isFavorite});

  final _BookListItem book;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return _AniyomiTapResponse(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentBookDetailsPage(book: book.details),
          ),
        );
      },
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
                      top: 9,
                      right: 9,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 28,
                        height: 28,
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
    required this.createdAtMillis,
    required this.details,
  });

  factory _BookListItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final details = StudentBookDetailsData.fromMap(id: doc.id, data: data);
    return _BookListItem(
      id: doc.id,
      title: details.title,
      author: details.author,
      description: details.summary,
      isbn: details.isbn,
      coverUrl: details.coverUrl,
      pdfUrl: details.pdfUrl,
      createdAtMillis: _timestampMillis(
        data['created_at'] ?? data['createdAt'],
      ),
      details: details,
    );
  }

  final String id;
  final String title;
  final String author;
  final String description;
  final String isbn;
  final String coverUrl;
  final String pdfUrl;
  final int createdAtMillis;
  final StudentBookDetailsData details;

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
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
