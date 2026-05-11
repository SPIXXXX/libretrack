import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libretrack/services/storage_service.dart';

class LibrarianBooksTab extends StatefulWidget {
  const LibrarianBooksTab({super.key});

  @override
  State<LibrarianBooksTab> createState() => _LibrarianBooksTabState();
}

class _LibrarianBooksTabState extends State<LibrarianBooksTab> {
  static const _accent = Color(0xFF2BA6A3);
  static const _purple = Color(0xFF4B23C6);
  static const _text = Color(0xFF11121A);
  static const _muted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _publisherController = TextEditingController();
  final _publicationController = TextEditingController();
  final _editionController = TextEditingController();
  final _languageController = TextEditingController();
  final _pagesController = TextEditingController();
  final _isbnController = TextEditingController();
  final _summaryController = TextEditingController();
  final _totalCopiesController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _storageService = StorageService();

  final List<String> _categories = const [
    'General',
    'Fiction',
    'Non-fiction',
    'Reference',
    'Technology',
    'Science',
    'Mathematics',
    'History',
    'Language',
    'Business',
    'Education',
    'Arts',
    'Religion',
    'Health',
  ];

  bool _showForm = false;
  bool _isSaving = false;
  bool _sortAZ = false;
  File? _selectedCover;
  String? _coverUrl;
  String? _editingBookId;
  String _selectedCategory = 'General';
  String _filterCategory = 'All';
  String _searchQuery = '';

  List<String> get _filterCategories => ['All', ..._categories];

  bool get _hasActiveFilters => _sortAZ || _filterCategory != 'All';

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _publicationController.dispose();
    _editionController.dispose();
    _languageController.dispose();
    _pagesController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    _totalCopiesController.dispose();
    super.dispose();
  }

  Stream<Map<String, int>> _activeBorrowCountsStream() {
    return FirebaseFirestore.instance
        .collection('borrow_records')
        .where('status', whereIn: ['active', 'borrowed'])
        .snapshots()
        .map((snapshot) {
          final counts = <String, int>{};
          for (final doc in snapshot.docs) {
            final bookId = _LibrarianBook._stringValue(
              doc.data()['bookId'],
              fallback: '',
            );
            if (bookId.isEmpty) {
              continue;
            }
            counts[bookId] = (counts[bookId] ?? 0) + 1;
          }
          return counts;
        });
  }

  Stream<List<_LibrarianBook>> _bookStream(
    Map<String, int> activeBorrowCounts,
  ) {
    return FirebaseFirestore.instance.collection('books').snapshots().map((
      snapshot,
    ) {
      final books = snapshot.docs.map((doc) {
        final book = _LibrarianBook.fromDoc(
          doc,
          activeBorrowCount: activeBorrowCounts[doc.id] ?? 0,
        );
        _repairStoredAvailability(book);
        return book;
      }).toList();
      books.sort((a, b) => b.createdAtMillis.compareTo(a.createdAtMillis));
      return books;
    });
  }

  void _repairStoredAvailability(_LibrarianBook book) {
    if (book.storedAvailableCopies == book.availableCopies) {
      return;
    }

    unawaited(
      FirebaseFirestore.instance.collection('books').doc(book.id).set({
        'availableCopies': book.availableCopies,
        'available_copies': book.availableCopies,
        'available': book.availableCopies,
        'updated_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)),
    );
  }

  List<_LibrarianBook> _visibleBooks(List<_LibrarianBook> books) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = books.where((book) {
      final matchesSearch =
          query.isEmpty ||
          book.title.toLowerCase().contains(query) ||
          book.author.toLowerCase().contains(query) ||
          book.category.toLowerCase().contains(query) ||
          book.publisher.toLowerCase().contains(query) ||
          book.summary.toLowerCase().contains(query) ||
          book.isbn.toLowerCase().contains(query);
      final matchesCategory =
          _filterCategory == 'All' ||
          book.category.toLowerCase() == _filterCategory.toLowerCase();

      return matchesSearch && matchesCategory;
    }).toList();

    if (_sortAZ) {
      filtered.sort((a, b) => a.title.compareTo(b.title));
    }

    return filtered;
  }

  Future<void> _pickCover() async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
      );

      if (pickedFile == null || !mounted) {
        return;
      }

      setState(() {
        _selectedCover = File(pickedFile.path);
        _coverUrl = null;
      });
    } catch (e) {
      _showSnackBar('Error picking cover: $e', isError: true);
    }
  }

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fill out the required fields.', isError: true);
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _showSnackBar('Please log in first.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? coverUrl = _coverUrl;
      if (_selectedCover != null) {
        coverUrl = await _storageService.uploadBookCover(_selectedCover!);
      }

      final pagesText = _pagesController.text.trim();
      final pages = int.tryParse(pagesText);
      final summary = _summaryController.text.trim();
      final totalCopies = int.tryParse(_totalCopiesController.text.trim()) ?? 1;
      if (totalCopies < 1) {
        _showSnackBar('Total copies must be at least 1.', isError: true);
        return;
      }
      final activeBorrowCount = _editingBookId == null
          ? 0
          : await _activeBorrowCountFor(_editingBookId!);
      if (activeBorrowCount > totalCopies) {
        _showSnackBar(
          'Total copies cannot be lower than active borrowers.',
          isError: true,
        );
        return;
      }
      final availableCopies = (totalCopies - activeBorrowCount)
          .clamp(0, totalCopies)
          .toInt();
      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'author': _authorController.text.trim(),
        'publisher': _publisherController.text.trim(),
        'publication_date': _publicationController.text.trim(),
        'publicationDate': _publicationController.text.trim(),
        'publication_year': _publicationController.text.trim(),
        'publicationYear': _publicationController.text.trim(),
        'edition': _editionController.text.trim(),
        'language': _languageController.text.trim(),
        'pages': pages ?? pagesText,
        'isbn': _isbnController.text.trim(),
        'summary': summary,
        'description': summary,
        'category': _selectedCategory,
        'classification_category': _selectedCategory,
        'classificationCategory': _selectedCategory,
        'classificationTags': [_selectedCategory],
        'cover_url': coverUrl ?? '',
        'coverUrl': coverUrl ?? '',
        'pdf_url': '',
        'pdfUrl': '',
        'totalCopies': totalCopies,
        'total_copies': totalCopies,
        'copies': totalCopies,
        'availableCopies': availableCopies,
        'available_copies': availableCopies,
        'available': availableCopies,
        'created_by': currentUser.uid,
        'created_by_email': currentUser.email,
        'createdBy': currentUser.uid,
        'createdByEmail': currentUser.email,
        'updated_at': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final books = FirebaseFirestore.instance.collection('books');
      if (_editingBookId == null) {
        data['created_at'] = FieldValue.serverTimestamp();
        data['createdAt'] = FieldValue.serverTimestamp();
        await books.add(data);
      } else {
        await books.doc(_editingBookId).set(data, SetOptions(merge: true));
      }

      if (!mounted) {
        return;
      }

      _showSnackBar(_editingBookId == null ? 'Book saved.' : 'Book updated.');
      _clearForm();
      setState(() => _showForm = false);
    } catch (e) {
      _showSnackBar('Failed to save book: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<int> _activeBorrowCountFor(String bookId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('borrow_records')
        .where('bookId', isEqualTo: bookId)
        .where('status', whereIn: ['active', 'borrowed'])
        .get();
    return snapshot.docs.length;
  }

  Future<void> _deleteBook(_LibrarianBook book) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Color(0xFFE43C44)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Delete book?',
                  style: TextStyle(
                    color: _text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 48,
                  height: 64,
                  child: book.coverUrl.isEmpty
                      ? const _CoverPlaceholder()
                      : Image.network(
                          book.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const _CoverPlaceholder();
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'This removes it from the librarian catalog.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: _text,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE43C44),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('books')
          .doc(book.id)
          .delete();
      _showSnackBar('Book deleted.');
    } catch (e) {
      _showSnackBar('Failed to delete book: $e', isError: true);
    }
  }

  void _startAddBook() {
    _clearForm();
    _totalCopiesController.text = '1';
    setState(() => _showForm = true);
  }

  void _startEditBook(_LibrarianBook book) {
    _titleController.text = book.title;
    _authorController.text = book.author;
    _publisherController.text = book.publisher;
    _publicationController.text = book.publicationDate;
    _editionController.text = book.edition;
    _languageController.text = book.language;
    _pagesController.text = book.pages;
    _isbnController.text = book.isbn;
    _summaryController.text = book.summary;
    _totalCopiesController.text = book.totalCopies.toString();
    setState(() {
      _editingBookId = book.id;
      _selectedCategory = _categories.contains(book.category)
          ? book.category
          : 'General';
      _selectedCover = null;
      _coverUrl = book.coverUrl.isEmpty ? null : book.coverUrl;
      _showForm = true;
    });
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _authorController.clear();
    _publisherController.clear();
    _publicationController.clear();
    _editionController.clear();
    _languageController.clear();
    _pagesController.clear();
    _isbnController.clear();
    _summaryController.clear();
    _totalCopiesController.clear();
    _selectedCover = null;
    _coverUrl = null;
    _editingBookId = null;
    _selectedCategory = 'General';
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showForm) {
      return _buildAddBookForm();
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: () async => setState(() {}),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              26 + MediaQuery.of(context).viewInsets.bottom,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildCatalogHeader(),
                const SizedBox(height: 16),
                _buildSearchField(),
                const SizedBox(height: 22),
                _buildCatalogList(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Book Catalog',
            style: TextStyle(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: FilledButton.icon(
            onPressed: _startAddBook,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('Add'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
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
          hintText: 'Search title, author, publisher, or category',
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
            maxWidth: 104,
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

  void _showFilterSheet() {
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
            void updateCategory(String category) {
              setSheetState(() => _filterCategory = category);
              setState(() {});
            }

            void updateSort(bool value) {
              setSheetState(() => _sortAZ = value);
              setState(() {});
            }

            void resetFilters() {
              setSheetState(() {
                _filterCategory = 'All';
                _sortAZ = false;
              });
              setState(() {});
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5EAF0),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Filter books',
                              style: TextStyle(
                                color: _text,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          _SearchIconButton(
                            onPressed: resetFilters,
                            icon: Icons.restart_alt_rounded,
                            color: _text,
                            tooltip: 'Reset filters',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Category',
                        style: TextStyle(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemCount: _filterCategories.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 9),
                          itemBuilder: (context, index) {
                            final category = _filterCategories[index];
                            return _FilterChipButton(
                              label: category,
                              selected: _filterCategory == category,
                              onTap: () => updateCategory(category),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SwitchListTile(
                          value: _sortAZ,
                          onChanged: updateSort,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          activeThumbColor: _accent,
                          title: const Text(
                            'Sort A-Z',
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          subtitle: const Text(
                            'Show titles alphabetically',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCatalogList() {
    return StreamBuilder<Map<String, int>>(
      stream: _activeBorrowCountsStream(),
      builder: (context, borrowSnapshot) {
        if (borrowSnapshot.hasError) {
          return const _BooksMessage(
            icon: Icons.error_outline_rounded,
            message: 'Could not load books.',
          );
        }

        if (borrowSnapshot.connectionState == ConnectionState.waiting &&
            !borrowSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 42),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        return StreamBuilder<List<_LibrarianBook>>(
          stream: _bookStream(borrowSnapshot.data ?? {}),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const _BooksMessage(
                icon: Icons.error_outline_rounded,
                message: 'Could not load books.',
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 42),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              );
            }

            final books = _visibleBooks(snapshot.data ?? []);
            if (books.isEmpty) {
              return _BooksMessage(
                icon: Icons.menu_book_outlined,
                message: _searchQuery.trim().isEmpty && !_hasActiveFilters
                    ? 'No books yet. Add the first catalog item.'
                    : 'No books match your search.',
              );
            }

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: Column(
                key: ValueKey(
                  '${_searchQuery.trim()}-$_filterCategory-$_sortAZ-${books.length}',
                ),
                children: [
                  for (var index = 0; index < books.length; index++)
                    _CatalogEntry(
                      delay: Duration(
                        milliseconds: 45 * (index > 5 ? 5 : index),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _CatalogBookCard(
                          book: books[index],
                          onEdit: () => _startEditBook(books[index]),
                          onDelete: () => _deleteBook(books[index]),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAddBookForm() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        28 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFormHeader(),
            const SizedBox(height: 20),
            _buildCoverPicker(),
            const SizedBox(height: 18),
            _buildSectionTitle('Book Details'),
            const SizedBox(height: 12),
            _buildTextField(
              _titleController,
              'Book Title',
              Icons.menu_book_rounded,
            ),
            const SizedBox(height: 12),
            _buildTextField(_authorController, 'Author', Icons.person_rounded),
            const SizedBox(height: 12),
            _buildTextField(
              _publisherController,
              'Publisher',
              Icons.business_rounded,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _publicationController,
                    'Publication date / year',
                    Icons.event_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTextField(
                    _editionController,
                    'Edition',
                    Icons.layers_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _languageController,
                    'Language',
                    Icons.language_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildTextField(
                    _pagesController,
                    'Pages',
                    Icons.format_list_numbered_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTextField(
              _isbnController,
              'ISBN (Optional)',
              Icons.numbers_rounded,
              isRequired: false,
            ),
            const SizedBox(height: 18),
            _buildSectionTitle('Availability'),
            const SizedBox(height: 12),
            _buildTextField(
              _totalCopiesController,
              'Total Copies',
              Icons.library_books_rounded,
              keyboardType: TextInputType.number,
              validator: _validateTotalCopies,
            ),
            const SizedBox(height: 8),
            const Text(
              'Available copies are updated automatically from active borrowers.',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 18),
            _buildSectionTitle('Classification'),
            const SizedBox(height: 12),
            _buildCategoryDropdown(),
            const SizedBox(height: 18),
            _buildSectionTitle('Summary'),
            const SizedBox(height: 12),
            _buildTextField(
              _summaryController,
              'Summary of the book',
              Icons.notes_rounded,
              maxLines: 5,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveBook,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : _editingBookId == null
                      ? 'Save Book'
                      : 'Update Book',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
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

  Widget _buildFormHeader() {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: _isSaving
              ? null
              : () {
                  _clearForm();
                  setState(() => _showForm = false);
                },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to catalog',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: _text,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editingBookId == null ? 'Add Book' : 'Edit Book',
                style: const TextStyle(
                  color: _text,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Bibliographic information and catalog details',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _isSaving ? null : () => setState(_clearForm),
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Clear form',
        ),
      ],
    );
  }

  Widget _buildCoverPicker() {
    final hasImage = _selectedCover != null || (_coverUrl?.isNotEmpty ?? false);

    return InkWell(
      onTap: _isSaving ? null : _pickCover,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasImage ? _accent : Colors.black.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 58,
                height: 78,
                child: _selectedCover != null
                    ? Image.file(_selectedCover!, fit: BoxFit.cover)
                    : (_coverUrl?.isNotEmpty ?? false)
                    ? Image.network(
                        _coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const _CoverPlaceholder();
                        },
                      )
                    : const _CoverPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Book Cover',
                    style: TextStyle(
                      color: _text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasImage
                        ? 'Cover selected. It uploads when you save.'
                        : 'Tap to choose a cover image.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.image_rounded, color: _accent),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: _text,
        fontSize: 15,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool isRequired = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label, icon),
      validator:
          validator ??
          (value) {
            if (isRequired && (value == null || value.trim().isEmpty)) {
              return '$label is required';
            }
            return null;
          },
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey(_selectedCategory),
      initialValue: _selectedCategory,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: _inputDecoration(
        'Classification tags / category',
        Icons.sell_rounded,
      ),
      items: _categories.map((category) {
        return DropdownMenuItem<String>(
          value: category,
          child: Text(category, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: _isSaving
          ? null
          : (value) {
              if (value == null) {
                return;
              }
              setState(() => _selectedCategory = value);
            },
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 21),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  String? _validateTotalCopies(String? value) {
    final rawValue = value?.trim() ?? '';
    final copies = int.tryParse(rawValue);
    if (rawValue.isEmpty) {
      return 'Total Copies is required';
    }
    if (copies == null || copies < 1) {
      return 'Use 1 or more';
    }
    return null;
  }
}

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
          borderRadius: BorderRadius.circular(8),
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
            letterSpacing: 0,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _CatalogEntry extends StatelessWidget {
  const _CatalogEntry({required this.child, required this.delay});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
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
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _CatalogBookCard extends StatelessWidget {
  const _CatalogBookCard({
    required this.book,
    required this.onEdit,
    required this.onDelete,
  });

  final _LibrarianBook book;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _AniyomiTapResponse(
      onTap: onEdit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.13),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox(
                  width: 64,
                  height: 82,
                  child: book.coverUrl.isEmpty
                      ? const _CoverPlaceholder()
                      : Image.network(
                          book.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const _CoverPlaceholder();
                          },
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 82,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF11121A),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF11121A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: [
                          _MiniChip(text: book.availabilityLabel),
                          _MiniChip(text: book.category),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    _SmallActionButton(
                      label: 'Edit',
                      color: const Color(0xFFD7F4EF),
                      textColor: const Color(0xFF17817F),
                      onTap: onEdit,
                    ),
                    const SizedBox(height: 10),
                    _SmallActionButton(
                      label: 'Delete',
                      color: const Color(0xFFFFE5E7),
                      textColor: const Color(0xFFE43C44),
                      onTap: onDelete,
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

class _SmallActionButton extends StatelessWidget {
  const _SmallActionButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F5),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF11121A),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _BooksMessage extends StatelessWidget {
  const _BooksMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 34),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF2BA6A3), size: 34),
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

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 28),
    );
  }
}

class _LibrarianBook {
  const _LibrarianBook({
    required this.id,
    required this.title,
    required this.author,
    required this.publisher,
    required this.publicationDate,
    required this.edition,
    required this.language,
    required this.pages,
    required this.isbn,
    required this.summary,
    required this.category,
    required this.coverUrl,
    required this.totalCopies,
    required this.availableCopies,
    required this.storedAvailableCopies,
    required this.createdAtMillis,
  });

  factory _LibrarianBook.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    int activeBorrowCount = 0,
  }) {
    final data = doc.data();
    final totalCopies = _intValue(
      data['totalCopies'] ?? data['total_copies'] ?? data['copies'],
      fallback: 3,
    );
    final storedAvailableCopies = _intValue(
      data['availableCopies'] ?? data['available_copies'] ?? data['available'],
      fallback: totalCopies,
    );
    final availableCopies = (totalCopies - activeBorrowCount)
        .clamp(0, totalCopies)
        .toInt();

    return _LibrarianBook(
      id: doc.id,
      title: _stringValue(data['title'], fallback: 'Untitled Book'),
      author: _stringValue(data['author'], fallback: 'Unknown author'),
      publisher: _stringValue(data['publisher'], fallback: ''),
      publicationDate: _stringValue(
        data['publication_date'] ??
            data['publicationDate'] ??
            data['publication_year'] ??
            data['publicationYear'],
        fallback: '',
      ),
      edition: _stringValue(data['edition'], fallback: ''),
      language: _stringValue(data['language'], fallback: ''),
      pages: _stringValue(data['pages'], fallback: ''),
      isbn: _stringValue(data['isbn'], fallback: ''),
      summary: _stringValue(
        data['summary'] ?? data['description'],
        fallback: '',
      ),
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
      storedAvailableCopies: storedAvailableCopies,
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
  final String pages;
  final String isbn;
  final String summary;
  final String category;
  final String coverUrl;
  final int totalCopies;
  final int availableCopies;
  final int storedAvailableCopies;
  final int createdAtMillis;

  String get availabilityLabel => '$availableCopies/$totalCopies Available';

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

  static int _timestampMillis(Object? value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }
}
