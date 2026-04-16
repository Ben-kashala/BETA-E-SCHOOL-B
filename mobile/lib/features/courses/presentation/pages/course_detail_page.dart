import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../students/presentation/widgets/student_bottom_nav.dart';
import 'dart:io';

class CourseDetailPage extends ConsumerStatefulWidget {
  final int courseId;

  const CourseDetailPage({super.key, required this.courseId});

  @override
  ConsumerState<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends ConsumerState<CourseDetailPage> {
  Map<String, dynamic>? _course;
  bool _isLoading = true;
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadCourse();
    _checkDownloadStatus();
  }

  Future<void> _loadCourse() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/elearning/courses/${widget.courseId}/');
      setState(() {
        _course = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> _checkDownloadStatus() async {
    final db = DatabaseService.database;
    final result = await db.query(
      'downloaded_courses',
      where: 'course_id = ?',
      whereArgs: [widget.courseId],
    );

    setState(() {
      _isDownloaded = result.isNotEmpty;
    });
  }

  Future<void> _downloadCourse() async {
    if (_course == null) return;

    // Demander les permissions
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
      _downloadProgress = 0.0;
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/courses');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      String? contentPath = downloadDir.path;
      final contentUrl = _course!['content_url']?.toString() ?? _course!['video_url']?.toString();
      if (contentUrl != null && contentUrl.startsWith('http')) {
        final ext = contentUrl.contains('.pdf') ? 'pdf' : (contentUrl.contains('.mp4') ? 'mp4' : 'html');
        final filePath = '${downloadDir.path}/course_${widget.courseId}.$ext';
        await ApiService().downloadFile(
          contentUrl,
          filePath,
          onReceiveProgress: (received, total) {
            if (mounted && total > 0) {
              setState(() => _downloadProgress = received / total);
            }
          },
        );
        contentPath = filePath;
      }

      final db = DatabaseService.database;
      await db.insert('downloaded_courses', {
        'course_id': widget.courseId,
        'title': _course!['title'],
        'description': _course!['description'],
        'content_path': contentPath,
        'downloaded_at': DateTime.now().millisecondsSinceEpoch,
        'is_complete': 1,
      });

      setState(() {
        _isDownloaded = true;
        _isDownloading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cours téléchargé avec succès')),
        );
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur de téléchargement: $e')),
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
        appBar: AppBar(title: const Text('Détails du cours')),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
            ? const StudentBottomNav()
            : null,
      );
    }

    if (_course == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Détails du cours')),
        body: const Center(child: Text('Cours non trouvé')),
        bottomNavigationBar: role == 'STUDENT' && !path.startsWith('/teacher/')
            ? const StudentBottomNav()
            : null,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_course!['title'] ?? 'Cours'),
        actions: [
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
              ),
            )
          else
            IconButton(
              icon: _isDownloaded ? const Icon(Icons.check_circle) : const Icon(Icons.download),
              onPressed: _isDownloaded || _isDownloading ? null : _downloadCourse,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_course!['thumbnail'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _course!['thumbnail'],
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              _course!['title'] ?? 'Sans titre',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            if (_course!['description'] != null)
              Text(
                _course!['description'],
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final url = _course!['content_url']?.toString() ?? _course!['video_url']?.toString();
                if (url != null && url.trim().isNotEmpty) {
                  final uri = Uri.tryParse(url);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lien non disponible')));
                  }
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contenu à venir')));
                }
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Commencer le cours'),
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
