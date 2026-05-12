import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:libretrack/pages/Student/book_details_page.dart';
import 'package:libretrack/services/student_library_service.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  static const _accent = Color(0xFF2BA6A3);
  static const _text = Color(0xFF11121A);
  static const _muted = Color(0xFF6B7280);

  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortAZ = false;
  String _filterAvailability = 'all'; // all, available, borrowed
  Set<String> _selectedCategories = {};

  bool get _hasActiveFilters =>
      _sortAZ || _filterAvailability != 'all' || _selectedCategories.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<_ExploreBook>> _allBooksStream() {
    return FirebaseFirestore.instance.collection('books').snapshots().map((
      snapshot,
    ) {
      final books = snapshot.docs.map(_ExploreBook.fromDoc).toList();
      books.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return books;
    });
  }

  List<_ExploreBook> _filterBooks(List<_ExploreBook> books) {
    final query = _searchQuery.trim().toLowerCase();

    var filtered = books.where((book) {
      final matchesSearch =
          query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.category.toLowerCase().contains(query);

      final matchesAvailability =
          _filterAvailability == 'all' ||
          (_filterAvailability == 'available' && book.availableCopies > 0) ||
          (_filterAvailability == 'borrowed' && book.availableCopies == 0);

      final matchesCategory =
          _selectedCategories.isEmpty ||
          _selectedCategories.contains(book.category);

      return matchesSearch && matchesAvailability && matchesCategory;
    }).toList();

    if (_sortAZ) {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    }

    return filtered;
  }

  List<String> _getAllCategories(List<_ExploreBook> books) {
    final categories = <String>{};
    for (final book in books) {
      categories.add(book.category);
    }
    return categories.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE3E7EB),
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: StreamBuilder<List<_ExploreBook>>(
          stream: _allBooksStream(),
          builder: (context, snapshot) {
            final isLoading =
                snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;
            final books = snapshot.data ?? [];
            final filteredBooks = _filterBooks(books);
            final allCategories = _getAllCategories(books);

            return Column(
              children: [
                // Header (fixed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Explore Books',
                        style: TextStyle(
                          color: _text,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Discover ${books.length} books in the library',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),

                // Search field (fixed - keeps keyboard focus)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _buildSearchField(),
                ),

                const SizedBox(height: 16),

                // Category Filter Chips (fixed)
                if (allCategories.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      physics: const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildCategoryChip(
                            label: 'All',
                            isSelected: _selectedCategories.isEmpty,
                            onTap: () =>
                                setState(() => _selectedCategories.clear()),
                          ),
                          const SizedBox(width: 8),
                          ...allCategories.map((category) {
                            final isSelected = _selectedCategories.contains(
                              category,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _buildCategoryChip(
                                label: category,
                                isSelected: isSelected,
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedCategories.remove(category);
                                    } else {
                                      _selectedCategories.add(category);
                                    }
                                  });
                                },
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Scrollable books grid only
                Expanded(
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: _accent),
                        )
                      : filteredBooks.isEmpty
                      ? Center(child: _buildEmptyState())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            const minCardWidth = 132.0;
                            const maxCardWidth = 156.0;
                            const spacing = 18.0;
                            const runSpacing = 30.0;
                            var cardsPerRow = 1;

                            for (var columns = 4; columns >= 1; columns--) {
                              final requiredWidth =
                                  (minCardWidth * columns) +
                                  (spacing * (columns - 1));
                              if (requiredWidth <= constraints.maxWidth - 36) {
                                cardsPerRow = columns;
                                break;
                              }
                            }

                            final availableWidth = constraints.maxWidth - 36;
                            final cardWidth =
                                ((availableWidth -
                                            (spacing * (cardsPerRow - 1))) /
                                        cardsPerRow)
                                    .clamp(minCardWidth, maxCardWidth);
                            final rowWidth =
                                (cardWidth * cardsPerRow) +
                                (spacing * (cardsPerRow - 1));

                            return SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                              child: Center(
                                child: SizedBox(
                                  width: rowWidth,
                                  child: Wrap(
                                    alignment: WrapAlignment.start,
                                    spacing: spacing,
                                    runSpacing: runSpacing,
                                    children: List.generate(
                                      filteredBooks.length,
                                      (index) => SizedBox(
                                        width: cardWidth,
                                        child: _buildBookCard(
                                          context,
                                          filteredBooks[index],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _hasActiveFilters
              ? _accent.withValues(alpha: 0.45)
              : Colors.black.withValues(alpha: 0.05),
          width: _hasActiveFilters ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search title, author, or category',
          hintStyle: const TextStyle(
            color: Color(0xFFA0A8B9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFFA0A8B9),
            size: 24,
          ),
          suffixIcon: _buildSearchActions(),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 46,
            minHeight: 58,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  Widget _buildSearchActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: _searchQuery.isEmpty
              ? const SizedBox.shrink()
              : _SearchIconButton(
                  key: const ValueKey('clear-search'),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: Icons.close_rounded,
                  color: const Color(0xFFA0A8B9),
                  tooltip: 'Clear search',
                ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: _SearchIconButton(
            onPressed: _showFilterSheet,
            icon: Icons.tune_rounded,
            color: _hasActiveFilters ? _accent : const Color(0xFFA0A8B9),
            tooltip: 'Filter books',
            showBadge: _hasActiveFilters,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _accent : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected ? null : Border.all(color: Colors.grey.shade300),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : _text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildBookCard(BuildContext context, _ExploreBook book) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return _ExploreBookCard(book: book, isFavorite: false);
    }

    return StreamBuilder<StudentBookLibraryEntry?>(
      stream: StudentLibraryService.bookEntryStream(
        uid: user.uid,
        bookId: book.id,
      ),
      builder: (context, snapshot) {
        final isFavorite = snapshot.data?.isFavorite ?? false;
        return _ExploreBookCard(book: book, isFavorite: isFavorite);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 64,
            color: _muted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No books found',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filters',
                          style: TextStyle(
                            color: _text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.close,
                            color: _text,
                            size: 24,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Sort Option
                    const Text(
                      'Sort',
                      style: TextStyle(
                        color: _text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: CheckboxListTile(
                        value: _sortAZ,
                        onChanged: (value) {
                          setModalState(() => _sortAZ = value ?? false);
                          setState(() => _sortAZ = value ?? false);
                        },
                        title: const Text(
                          'Sort A-Z',
                          style: TextStyle(
                            color: _text,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        checkColor: Colors.white,
                        activeColor: _accent,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Availability Filter
                    const Text(
                      'Availability',
                      style: TextStyle(
                        color: _text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ...['all', 'available', 'borrowed'].map((value) {
                      final labels = {
                        'all': 'All Books',
                        'available': 'Available Only',
                        'borrowed': 'Not Available',
                      };

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: _filterAvailability == value
                              ? _accent.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: _filterAvailability == value
                              ? Border.all(color: _accent, width: 2)
                              : null,
                        ),
                        child: RadioListTile(
                          value: value,
                          groupValue: _filterAvailability,
                          onChanged: (newValue) {
                            setModalState(
                              () => _filterAvailability = newValue ?? 'all',
                            );
                            setState(
                              () => _filterAvailability = newValue ?? 'all',
                            );
                          },
                          title: Text(
                            labels[value] ?? value,
                            style: const TextStyle(
                              color: _text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          activeColor: _accent,
                        ),
                      );
                    }),

                    const SizedBox(height: 24),

                    // Apply Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Apply Filters',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
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
      },
    );
  }
}

class _ExploreBook {
  const _ExploreBook({
    required this.id,
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
    required this.createdAtMillis,
  });

  factory _ExploreBook.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final details = StudentBookDetailsData.fromMap(id: doc.id, data: data);

    return _ExploreBook(
      id: doc.id,
      title: details.title,
      author: details.author,
      publisher: details.publisher,
      publicationDate: details.publicationDate,
      edition: details.edition,
      language: details.language,
      pages: int.tryParse(details.pages.toString()) ?? 0,
      summary: details.summary,
      isbn: details.isbn,
      category: details.category,
      coverUrl: details.coverUrl,
      pdfUrl: details.pdfUrl,
      totalCopies: details.totalCopies,
      availableCopies: details.availableCopies,
      createdAtMillis: _timestampMillis(
        data['created_at'] ?? data['createdAt'],
      ),
    );
  }

  final String id;
  final String title;
  final String author;
  final String publisher;
  final String publicationDate;
  final String edition;
  final String language;
  final int pages;
  final String summary;
  final String isbn;
  final String category;
  final String coverUrl;
  final String pdfUrl;
  final int totalCopies;
  final int availableCopies;
  final int createdAtMillis;

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }
}

/// Book card for explore page - uses homepage style design
class _ExploreBookCard extends StatelessWidget {
  const _ExploreBookCard({required this.book, required this.isFavorite});

  final _ExploreBook book;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return _ExplorePressScale(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentBookDetailsPage(
              book: StudentBookDetailsData.fromMap(
                id: book.id,
                data: {
                  'title': book.title,
                  'author': book.author,
                  'publisher': book.publisher,
                  'publicationDate': book.publicationDate,
                  'edition': book.edition,
                  'language': book.language,
                  'pages': book.pages,
                  'summary': book.summary,
                  'isbn': book.isbn,
                  'category': book.category,
                  'cover_url': book.coverUrl,
                  'pdfUrl': book.pdfUrl,
                  'totalCopies': book.totalCopies,
                  'availableCopies': book.availableCopies,
                },
              ),
            ),
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
                    Positioned.fill(
                      child: book.coverUrl.isNotEmpty
                          ? Image.network(
                              book.coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const _ExploreCoverFallback(),
                            )
                          : const _ExploreCoverFallback(),
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
    );
  }
}

class _ExploreCoverFallback extends StatelessWidget {
  const _ExploreCoverFallback();

  @override
  Widget build(BuildContext context) {
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
}

/// Press scale animation widget for book cards
class _ExplorePressScale extends StatefulWidget {
  const _ExplorePressScale({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ExplorePressScale> createState() => _ExplorePressScaleState();
}

class _ExplorePressScaleState extends State<_ExplorePressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
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

/// Aniyomi-style press response used by the catalog search icon buttons.
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
    if (_pressed == value) return;
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

/// Icon button used inside the catalog-style search field.
class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.tooltip,
    this.showBadge = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final Color color;
  final String tooltip;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _AniyomiTapResponse(
        onTap: onPressed,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: color, size: 23),
              AnimatedScale(
                scale: showBadge ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: Align(
                  alignment: const Alignment(0.48, -0.48),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
