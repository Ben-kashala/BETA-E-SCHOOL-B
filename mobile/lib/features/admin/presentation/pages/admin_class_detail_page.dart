import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_service.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminClassDetailPage extends ConsumerStatefulWidget {
  const AdminClassDetailPage({super.key, required this.classId});

  final int classId;

  @override
  ConsumerState<AdminClassDetailPage> createState() => _AdminClassDetailPageState();
}

class _AdminClassDetailPageState extends ConsumerState<AdminClassDetailPage> {
  Map<String, dynamic>? _classData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadClass();
  }

  Future<void> _loadClass() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/api/schools/classes/${widget.classId}/',
        useCache: false,
      );
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _classData = data is Map ? Map<String, dynamic>.from(data) : null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _classData = null;
        _isLoading = false;
      });
    }
  }

  String _teacherLabel(dynamic raw) {
    if (raw == null) return 'Non assigné';
    if (raw is Map) {
      final fullName = raw['full_name']?.toString().trim();
      if (fullName != null && fullName.isNotEmpty) return fullName;

      final user = raw['user'];
      if (user is Map) {
        final firstName = user['first_name']?.toString().trim() ?? '';
        final lastName = user['last_name']?.toString().trim() ?? '';
        final combined = '$firstName $lastName'.trim();
        if (combined.isNotEmpty) return combined;
      }

      final id = raw['id'];
      if (id != null) return 'Titulaire #$id';
    }
    if (raw is int || raw is num) return 'Titulaire #$raw';

    final text = raw.toString().trim();
    return text.isEmpty ? 'Non assigné' : text;
  }

  Widget _infoTile(BuildContext context, String label, String value, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail classe'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _classData == null
              ? const Center(child: Text('Classe introuvable'))
              : RefreshIndicator(
                  onRefresh: _loadClass,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _infoTile(
                        context,
                        'Nom',
                        '${_classData!['name'] ?? 'Classe'}',
                        Icons.class_,
                      ),
                      _infoTile(
                        context,
                        'Niveau',
                        '${_classData!['level'] ?? 'N/A'}',
                        Icons.stairs_outlined,
                      ),
                      _infoTile(
                        context,
                        'Titulaire',
                        _teacherLabel(_classData!['titulaire']),
                        Icons.person_outline,
                      ),
                      _infoTile(
                        context,
                        'Section',
                        '${_classData!['section_name'] ?? _classData!['section'] ?? 'N/A'}',
                        Icons.account_tree_outlined,
                      ),
                      _infoTile(
                        context,
                        'Année scolaire',
                        '${_classData!['academic_year'] ?? 'N/A'}',
                        Icons.calendar_today_outlined,
                      ),
                      _infoTile(
                        context,
                        'Capacité',
                        '${_classData!['capacity'] ?? 'N/A'}',
                        Icons.groups_outlined,
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}

