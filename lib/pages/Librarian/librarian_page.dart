import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:libretrack/services/storage_service.dart';

class LibrarianPage extends StatefulWidget {
  const LibrarianPage({super.key});

  @override
  State<LibrarianPage> createState() => _LibrarianPageState();
}

class _LibrarianPageState extends State<LibrarianPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _isbnController = TextEditingController();

  File? _selectedCover;
  File? _selectedPdf;
  String? _uploadedCoverUrl;
  String? _uploadedPdfUrl;

  bool _isUploading = false;

  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _isbnController.dispose();
    super.dispose();
  }

  // ============================================================================
  // PICK BOOK COVER IMAGE
  // ============================================================================
  Future<void> _pickBookCover() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        if (!mounted) {
          return;
        }

        setState(() => _selectedCover = File(pickedFile.path));
      }
    } catch (e) {
      _showSnackBar('Error picking image: $e', isError: true);
    }
  }

  // ============================================================================
  // PICK PDF FILE
  // ============================================================================
  Future<void> _pickPdfFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path == null || path.isEmpty) {
          _showSnackBar('Could not read the selected PDF', isError: true);
          return;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _selectedPdf = File(path);
        });
      }
    } catch (e) {
      _showSnackBar('Error picking PDF: $e', isError: true);
    }
  }

  // ============================================================================
  // UPLOAD BOOK COVER
  // ============================================================================
  Future<void> _uploadBookCover() async {
    if (_selectedCover == null) {
      _showSnackBar('Please select a book cover image', isError: true);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final url = await _storageService.uploadBookCover(_selectedCover!);
      if (!mounted) {
        return;
      }

      setState(() {
        _uploadedCoverUrl = url;
      });
      _showSnackBar('Book cover uploaded!');
    } catch (e) {
      _showSnackBar('Failed to upload cover: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  // ============================================================================
  // UPLOAD PDF
  // ============================================================================
  Future<void> _uploadPdf() async {
    if (_selectedPdf == null) {
      _showSnackBar('Please select a PDF file', isError: true);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final url = await _storageService.uploadPDF(_selectedPdf!);
      if (!mounted) {
        return;
      }

      setState(() {
        _uploadedPdfUrl = url;
      });
      _showSnackBar('PDF uploaded!');
    } catch (e) {
      _showSnackBar('Failed to upload PDF: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  // ============================================================================
  // SAVE BOOK TO FIRESTORE (after uploads)
  // ============================================================================
  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fill all fields', isError: true);
      return;
    }

    if (_uploadedCoverUrl == null) {
      _showSnackBar('Please upload a book cover', isError: true);
      return;
    }

    if (_uploadedPdfUrl == null) {
      _showSnackBar('Please upload a PDF file', isError: true);
      return;
    }

    setState(() => _isUploading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _showSnackBar('Please log in first', isError: true);
        return;
      }

      // Save book to Firestore with the uploaded URLs
      await FirebaseFirestore.instance.collection('books').add({
        'title': _titleController.text.trim(),
        'author': _authorController.text.trim(),
        'description': _descriptionController.text.trim(),
        'isbn': _isbnController.text.trim(),
        'cover_url': _uploadedCoverUrl,
        'pdf_url': _uploadedPdfUrl,
        'coverUrl': _uploadedCoverUrl,
        'pdfUrl': _uploadedPdfUrl,
        'created_by': currentUser.uid,
        'created_by_email': currentUser.email,
        'createdBy': currentUser.uid,
        'createdByEmail': currentUser.email,
        'created_at': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) {
        return;
      }

      _showSnackBar('Book saved successfully!');
      _clearForm();
    } catch (e) {
      _showSnackBar('Failed to save book: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _clearForm() {
    _titleController.clear();
    _authorController.clear();
    _descriptionController.clear();
    _isbnController.clear();
    setState(() {
      _selectedCover = null;
      _selectedPdf = null;
      _uploadedCoverUrl = null;
      _uploadedPdfUrl = null;
    });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Book'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ──── Book Details Form ────
                _buildTextField(_titleController, 'Book Title', Icons.book),
                const SizedBox(height: 16),
                _buildTextField(_authorController, 'Author Name', Icons.person),
                const SizedBox(height: 16),
                _buildTextField(
                  _descriptionController,
                  'Description',
                  Icons.description,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  _isbnController,
                  'ISBN (Optional)',
                  Icons.numbers,
                  isRequired: false,
                ),
                const SizedBox(height: 24),

                // ──── Book Cover Upload ────
                const Text(
                  'Book Cover Image',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildFilePickerButton(
                  'Pick Book Cover',
                  _selectedCover != null,
                  _pickBookCover,
                  Icons.image,
                ),
                const SizedBox(height: 12),
                if (_selectedCover != null)
                  _buildUploadButton(
                    'Upload Cover',
                    _uploadBookCover,
                    _isUploading,
                  ),
                if (_uploadedCoverUrl != null)
                  _buildUploadSuccess('Cover uploaded ✓'),
                const SizedBox(height: 24),

                // ──── PDF Upload ────
                const Text(
                  'PDF File',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                _buildFilePickerButton(
                  'Pick PDF File',
                  _selectedPdf != null,
                  _pickPdfFile,
                  Icons.picture_as_pdf,
                ),
                const SizedBox(height: 12),
                if (_selectedPdf != null)
                  _buildUploadButton('Upload PDF', _uploadPdf, _isUploading),
                if (_uploadedPdfUrl != null)
                  _buildUploadSuccess('PDF uploaded ✓'),
                const SizedBox(height: 24),

                // ──── Save Button ────
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _saveBook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3C13C5),
                      disabledBackgroundColor: Colors.grey,
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Book',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool isRequired = true,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
      ),
      validator: (value) {
        if (isRequired && (value == null || value.isEmpty)) {
          return '$label is required';
        }
        return null;
      },
    );
  }

  Widget _buildFilePickerButton(
    String label,
    bool isSelected,
    VoidCallback onTap,
    IconData icon,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.green : Colors.grey),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? Colors.green : Colors.grey,
              ),
            ),
            if (isSelected) const Spacer(),
            if (isSelected) const Icon(Icons.check, color: Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadButton(String label, VoidCallback onTap, bool isLoading) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3C13C5),
          disabledBackgroundColor: Colors.grey,
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
              )
            : Text(label, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _buildUploadSuccess(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        border: Border.all(color: Colors.green),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.green, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
