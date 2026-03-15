import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/database/hive_service.dart';

class BookReaderPage extends ConsumerStatefulWidget {
  final int bookId;
  final String? initialUrl;

  const BookReaderPage({
    super.key,
    required this.bookId,
    this.initialUrl,
  });

  @override
  ConsumerState<BookReaderPage> createState() => _BookReaderPageState();
}

class _BookReaderPageState extends ConsumerState<BookReaderPage> {
  PdfViewerController? _pdfViewerController;
  PdfTextSearchResult? _searchResult;
  String? _pdfPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _showControls = true;
  double _zoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = PdfViewerController();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    setState(() => _isLoading = true);

    try {
      // Vérifier si le PDF est déjà téléchargé
      final db = DatabaseService.database;
      final result = await db.query(
        'library_books',
        where: 'book_id = ?',
        whereArgs: [widget.bookId],
      );

      if (result.isNotEmpty && result.first['file_path'] != null) {
        final filePath = result.first['file_path'] as String;
        final file = File(filePath);
        if (await file.exists()) {
          setState(() {
            _pdfPath = filePath;
            _isLoading = false;
          });
          return;
        }
      }

      // Télécharger le PDF
      await _downloadPdf();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      // Obtenir l'URL du PDF
      final bookResponse = await ApiService().get('/api/library/books/${widget.bookId}/');
      final book = bookResponse.data as Map<String, dynamic>;
      final pdfUrl = widget.initialUrl ?? book['book_file'] ?? book['file_url'] ?? book['pdf_url'];

      if (pdfUrl == null || pdfUrl.toString().trim().isEmpty) {
        throw Exception('URL du PDF non disponible');
      }
      String downloadUrl = pdfUrl.toString();
      if (!downloadUrl.startsWith('http')) {
        final origin = Uri.parse(ApiService().baseUrl).origin;
        downloadUrl = origin + (downloadUrl.startsWith('/') ? downloadUrl : '/$downloadUrl');
      }

      // Télécharger le fichier
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/books');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final fileName = downloadUrl.split('/').last;
      final filePath = '${downloadDir.path}/book_${widget.bookId}_${fileName.contains('.') ? fileName : 'document.pdf'}';

      await ApiService().downloadFile(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      // Enregistrer dans la base de données
      final db = DatabaseService.database;
      await db.insert('library_books', {
        'book_id': widget.bookId,
        'title': book['title'],
        'author': book['author'],
        'description': book['description'],
        'cover_url': book['cover_url'],
        'file_path': filePath,
        'is_downloaded': 1,
        'progress': 1.0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      setState(() {
        _pdfPath = filePath;
        _isDownloading = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _isLoading = false;
      });
      rethrow;
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _goToPage(int page) {
    _pdfViewerController?.jumpToPage(page);
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      _pdfViewerController?.nextPage();
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _pdfViewerController?.previousPage();
    }
  }

  void _restoreBookmark() {
    final page = HiveService.getSetting<int>('pdf_bookmark_${widget.bookId}');
    if (page != null && page > 0 && _pdfViewerController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pdfViewerController?.jumpToPage(page);
      });
    }
  }

  void _saveBookmark() {
    HiveService.saveSetting('pdf_bookmark_${widget.bookId}', _currentPage);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Signet enregistré (page $_currentPage)')),
      );
    }
  }

  void _zoomIn() {
    if (_pdfViewerController == null) return;
    setState(() {
      _zoomLevel = (_zoomLevel + 0.25).clamp(0.5, 3.0);
      _pdfViewerController!.zoomLevel = _zoomLevel;
    });
  }

  void _showFullscreen() {
    if (_pdfPath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('Lecteur PDF'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: SfPdfViewer.file(File(_pdfPath!), controller: PdfViewerController()),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechercher'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Texte à rechercher'),
          onSubmitted: (text) {
            if (text.trim().isEmpty) return;
            Navigator.of(ctx).pop();
            _runSearch(text.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              _runSearch(controller.text.trim());
            },
            child: const Text('Rechercher'),
          ),
        ],
      ),
    );
  }

  void _runSearch(String text) {
    _searchResult?.clear();
    _searchResult = _pdfViewerController?.searchText(text);
    if (_searchResult == null) return;
    if (kIsWeb) {
      setState(() {});
    } else {
      _searchResult!.addListener(() {
        if (mounted) setState(() {});
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recherche: « $text »')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _showControls
          ? AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lecteur PDF'),
                  if (_totalPages > 0)
                    Text(
                      'Page $_currentPage sur $_totalPages',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _showSearchDialog,
                ),
                if (_searchResult != null && _searchResult!.hasResult) ...[
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchResult?.clear();
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_before),
                    onPressed: () => _searchResult?.previousInstance(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_next),
                    onPressed: () => _searchResult?.nextInstance(),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.bookmark),
                  onPressed: _saveBookmark,
                ),
              ],
            )
          : null,
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isDownloading) ...[
                    CircularProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 16),
                    Text('Téléchargement: ${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            )
          : _pdfPath == null
              ? const Center(child: Text('PDF non disponible'))
              : GestureDetector(
                  onTap: _toggleControls,
                  child: Stack(
                    children: [
                      // Lecteur PDF
                      SfPdfViewer.file(
                        File(_pdfPath!),
                        controller: _pdfViewerController,
                        currentSearchTextHighlightColor: Colors.yellow,
                        otherSearchTextHighlightColor: Colors.orange,
                        onDocumentLoaded: (details) {
                          setState(() {
                            _totalPages = details.document.pages.count;
                          });
                          _restoreBookmark();
                        },
                        onPageChanged: (details) {
                          setState(() {
                            _currentPage = details.newPageNumber;
                          });
                        },
                      ),
                      // Contrôles
                      if (_showControls)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Barre de progression
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.first_page, color: Colors.white),
                                          onPressed: _currentPage == 1 ? null : () => _goToPage(1),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left, color: Colors.white),
                                          onPressed: _currentPage == 1 ? null : _previousPage,
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: _currentPage.toDouble(),
                                            min: 1,
                                            max: _totalPages.toDouble(),
                                            divisions: _totalPages,
                                            label: 'Page $_currentPage',
                                            onChanged: (value) {
                                              _goToPage(value.toInt());
                                            },
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right, color: Colors.white),
                                          onPressed: _currentPage == _totalPages ? null : _nextPage,
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.last_page, color: Colors.white),
                                          onPressed: _currentPage == _totalPages ? null : () => _goToPage(_totalPages),
                                        ),
                                      ],
                                    ),
                                    // Informations
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.zoom_in, color: Colors.white),
                                          label: Text('Zoom ${(_zoomLevel * 100).toInt()}%', style: const TextStyle(color: Colors.white)),
                                          onPressed: _zoomIn,
                                        ),
                                        TextButton.icon(
                                          icon: const Icon(Icons.fullscreen, color: Colors.white),
                                          label: const Text('Plein écran', style: TextStyle(color: Colors.white)),
                                          onPressed: _showFullscreen,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
      floatingActionButton: _showControls
          ? FloatingActionButton(
              onPressed: _toggleControls,
              child: const Icon(Icons.visibility_off),
            )
          : FloatingActionButton(
              onPressed: _toggleControls,
              child: const Icon(Icons.visibility),
            ),
    );
  }
}
