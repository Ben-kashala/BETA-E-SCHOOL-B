import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../students/presentation/widgets/student_bottom_nav.dart';

class BookDetailPage extends ConsumerStatefulWidget {
  final int bookId;

  const BookDetailPage({super.key, required this.bookId});

  @override
  ConsumerState<BookDetailPage> createState() => _BookDetailPageState();
}

class _BookDetailPageState extends ConsumerState<BookDetailPage> {
  Map<String, dynamic>? _book;
  bool _isLoading = true;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadBook();
    _checkDownloadStatus();
  }

  Future<void> _loadBook() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/library/books/${widget.bookId}/');
      setState(() {
        _book = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkDownloadStatus() async {
    final db = DatabaseService.database;
    final result = await db.query(
      'library_books',
      where: 'book_id = ?',
      whereArgs: [widget.bookId],
    );

    setState(() {
      _isDownloaded = result.isNotEmpty && result.first['is_downloaded'] == 1;
    });
  }

  Future<void> _downloadBook() async {
    if (_book == null) return;

    final status = await Permission.storage.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission de stockage requise')),
        );
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });

    try {
      final urlRaw = _book!['book_file'] ?? _book!['file_url'] ?? _book!['pdf_url'];
      if (urlRaw == null || urlRaw.toString().trim().isEmpty) {
        throw Exception('Fichier non disponible pour ce livre');
      }
      String downloadUrl = urlRaw.toString();
      if (!downloadUrl.startsWith('http')) {
        final base = ApiService().baseUrl;
        final origin = Uri.parse(base).origin;
        downloadUrl = origin + (downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl');
      }

      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/books');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final fileName = downloadUrl.split('/').last;
      final safeName = fileName.contains('.') ? fileName : 'book_${widget.bookId}.pdf';
      final filePath = '${downloadDir.path}/book_${widget.bookId}_$safeName';

      await ApiService().downloadFile(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );

      final db = DatabaseService.database;
      await db.insert('library_books', {
        'book_id': widget.bookId,
        'title': _book!['title'],
        'author': _book!['author'],
        'description': _book!['description'],
        'cover_url': _book!['cover_url'],
        'file_path': filePath,
        'is_downloaded': 1,
        'progress': 1.0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      setState(() {
        _isDownloaded = true;
        _isDownloading = false;
        _progress = 1.0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Livre téléchargé avec succès')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authProvider).user?.role;
    final path = GoRouterState.of(context).uri.path;
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails du livre')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
            ? const StudentBottomNav()
            : null,
      );
    }

    if (_book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails du livre')),
        body: const Center(child: Text('Livre non trouvé')),
        bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
            ? const StudentBottomNav()
            : null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_book!['title'] ?? 'Livre'),
        actions: [
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(_isDownloaded ? Icons.check_circle : Icons.download),
              onPressed: _isDownloaded ? null : _downloadBook,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_book!['cover_url'] != null)
              Center(
                child: Image.network(
                  _book!['cover_url'],
                  height: 300,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              _book!['title'] ?? 'Sans titre',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_book!['author'] != null)
              Text(
                'Par ${_book!['author']}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 16),
            if (_book!['description'] != null)
              Text(
                _book!['description'],
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isDownloaded || _book!['file_url'] != null
                  ? () {
                      context.push('/library/${widget.bookId}/read');
                    }
                  : null,
              icon: const Icon(Icons.book),
              label: Text(_isDownloaded ? 'Lire le livre' : 'Télécharger et lire'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
          ? const StudentBottomNav()
          : null,
    );
  }
}
