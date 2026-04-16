import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminClassesPage extends ConsumerStatefulWidget {
  const AdminClassesPage({super.key});

  @override
  ConsumerState<AdminClassesPage> createState() => _AdminClassesPageState();
}

class _AdminClassesPageState extends ConsumerState<AdminClassesPage> {
  List<dynamic> _classes = [];
  List<dynamic> _filteredClasses = [];
  bool _isLoading = true;
  String _searchQuery = '';

  String? _titulaireLabel(dynamic raw) {
    if (raw == null) return null;
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
      return 'Titulaire assigné';
    }
    if (raw is int || raw is num) return 'Titulaire #$raw';

    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
  }

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/schools/classes/');
      setState(() {
        _classes = response.data is List 
            ? response.data 
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredClasses = _classes.where((cls) {
        if (_searchQuery.isNotEmpty) {
          final name = (cls['name'] ?? '').toString().toLowerCase();
          return name.contains(_searchQuery.toLowerCase());
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              context.push('/admin/classes/create');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher une classe...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClasses.isEmpty
                    ? const Center(child: Text('Aucune classe'))
                    : RefreshIndicator(
                        onRefresh: _loadClasses,
                        child: ListView.builder(
                          itemCount: _filteredClasses.length,
                          itemBuilder: (context, index) {
                            final classItem = _filteredClasses[index];
                            final titulaire = _titulaireLabel(classItem['titulaire']);
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: ListTile(
                                leading: const Icon(Icons.class_),
                                title: Text(classItem['name'] ?? 'Classe'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Niveau: ${classItem['level'] ?? 'N/A'}'),
                                    if (titulaire != null)
                                      Text('Titulaire: $titulaire'),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  context.push('/admin/classes/${classItem['id']}');
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}
