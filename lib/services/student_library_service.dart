import 'package:cloud_firestore/cloud_firestore.dart';

class StudentBookLibraryEntry {
  const StudentBookLibraryEntry({
    required this.bookId,
    required this.categories,
  });

  final String bookId;
  final List<String> categories;

  bool get isFavorite => categories.contains(StudentLibraryService.favorites);

  factory StudentBookLibraryEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return StudentBookLibraryEntry(
      bookId: doc.id,
      categories: StudentLibraryService.normalizeCategories(data['categories']),
    );
  }
}

class StudentLibraryService {
  const StudentLibraryService._();

  static const String favorites = 'Favorites';

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static CollectionReference<Map<String, dynamic>> _categoryCollection(
    String uid,
  ) {
    return _userDoc(uid).collection('book_categories');
  }

  static CollectionReference<Map<String, dynamic>> _oldLibraryCollection(
    String uid,
  ) {
    return _userDoc(uid).collection('book_library');
  }

  static Stream<List<String>> categoriesStream(String uid) {
    return _categoryCollection(uid).snapshots().map((snapshot) {
      return normalizeCategories(
        snapshot.docs.map((doc) => doc.data()['name']).toList(),
      );
    });
  }

  static Future<List<String>> fetchCategories(String uid) async {
    await ensureDefaultCategory(uid);
    final snapshot = await _categoryCollection(uid).get();
    return normalizeCategories(
      snapshot.docs.map((doc) => doc.data()['name']).toList(),
    );
  }

  static Future<void> addCategory({
    required String uid,
    required String category,
  }) async {
    final categories = await fetchCategories(uid);
    final cleanCategory = category.trim();
    if (cleanCategory.isEmpty) {
      return;
    }

    final alreadyExists = categories.any(
      (value) => value.toLowerCase() == cleanCategory.toLowerCase(),
    );
    if (alreadyExists) {
      return;
    }

    await _categoryCollection(uid).doc(_categoryDocId(cleanCategory)).set({
      'name': cleanCategory,
      'nameLower': cleanCategory.toLowerCase(),
      'books': <String>[],
      'isDefault': cleanCategory == favorites,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<Map<String, StudentBookLibraryEntry>> libraryEntriesStream(
    String uid,
  ) {
    return _categoryCollection(uid).snapshots().map((snapshot) {
      final entries = <String, Set<String>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final category = _categoryName(data, fallback: doc.id);
        final bookIds = _bookIdsFromCategory(data);
        for (final bookId in bookIds) {
          entries.putIfAbsent(bookId, () => <String>{}).add(category);
        }
      }

      return {
        for (final entry in entries.entries)
          entry.key: StudentBookLibraryEntry(
            bookId: entry.key,
            categories: normalizeCategories(entry.value),
          ),
      };
    });
  }

  static Stream<StudentBookLibraryEntry?> bookEntryStream({
    required String uid,
    required String bookId,
  }) {
    return libraryEntriesStream(uid).map((entries) => entries[bookId]);
  }

  static Future<void> saveBookCategories({
    required String uid,
    required String bookId,
    required List<String> categories,
  }) async {
    await ensureDefaultCategory(uid);
    final normalized = normalizeCategories(categories);
    final categoryCollection = _categoryCollection(uid);
    final snapshot = await categoryCollection.get();
    final batch = FirebaseFirestore.instance.batch();
    final selected = normalized.map((value) => value.toLowerCase()).toSet();
    final existingNames = <String>{};

    for (final doc in snapshot.docs) {
      final category = _categoryName(doc.data(), fallback: doc.id);
      final isSelected = selected.contains(category.toLowerCase());
      existingNames.add(category.toLowerCase());

      batch.set(doc.reference, {
        'books': isSelected
            ? FieldValue.arrayUnion([bookId])
            : FieldValue.arrayRemove([bookId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final category in normalized) {
      if (existingNames.contains(category.toLowerCase())) {
        continue;
      }

      final reference = categoryCollection.doc(_categoryDocId(category));
      batch.set(reference, {
        'name': category,
        'nameLower': category.toLowerCase(),
        'books': FieldValue.arrayUnion([bookId]),
        'isDefault': category == favorites,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  static Future<void> removeBook({
    required String uid,
    required String bookId,
  }) async {
    final snapshot = await _categoryCollection(uid).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.set(doc.reference, {
        'books': FieldValue.arrayRemove([bookId]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  static Future<void> ensureDefaultCategory(String uid) async {
    final reference = _categoryCollection(uid).doc(_categoryDocId(favorites));
    final snapshot = await reference.get();
    await reference.set({
      'name': favorites,
      'nameLower': favorites.toLowerCase(),
      if (!snapshot.exists) 'books': <String>[],
      'isDefault': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _migrateOldLibrary(uid);
  }

  static List<String> normalizeCategories(Object? rawCategories) {
    final values = <String>[
      if (rawCategories is Iterable)
        for (final value in rawCategories)
          if (value is String) value.trim(),
    ].where((value) => value.isNotEmpty).toList();

    final normalized = <String>[favorites];
    for (final value in values) {
      if (value.toLowerCase() == favorites.toLowerCase()) {
        continue;
      }
      final alreadyExists = normalized.any(
        (category) => category.toLowerCase() == value.toLowerCase(),
      );
      if (!alreadyExists) {
        normalized.add(value);
      }
    }

    return normalized;
  }

  static String _categoryDocId(String category) {
    final safeId = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (safeId.isNotEmpty) {
      return safeId;
    }
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  static String _categoryName(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final name = data['name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }
    return fallback;
  }

  static List<String> _bookIdsFromCategory(Map<String, dynamic> data) {
    final rawBooks = data['books'] ?? data['bookIds'];
    if (rawBooks is! Iterable) {
      return const [];
    }

    return rawBooks
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  static Future<void> _migrateOldLibrary(String uid) async {
    final oldSnapshot = await _oldLibraryCollection(uid).get();
    if (oldSnapshot.docs.isEmpty) {
      return;
    }

    final booksByCategory = <String, Set<String>>{};
    for (final doc in oldSnapshot.docs) {
      final categories = normalizeCategories(doc.data()['categories']);
      for (final category in categories) {
        booksByCategory.putIfAbsent(category, () => <String>{}).add(doc.id);
      }
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final entry in booksByCategory.entries) {
      final category = entry.key;
      batch.set(
        _categoryCollection(uid).doc(_categoryDocId(category)),
        {
          'name': category,
          'nameLower': category.toLowerCase(),
          'books': FieldValue.arrayUnion(entry.value.toList()),
          'isDefault': category == favorites,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    for (final doc in oldSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
