import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminFormerStudentsPage extends ConsumerStatefulWidget {
  const AdminFormerStudentsPage({super.key});

  @override
  ConsumerState<AdminFormerStudentsPage> createState() =>
      _AdminFormerStudentsPageState();
}

class _AdminFormerStudentsPageState extends ConsumerState<AdminFormerStudentsPage> {
  List<dynamic> _students = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFormerStudents();
  }

  Future<void> _loadFormerStudents() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/api/accounts/students/',
        queryParameters: {'is_former_student': 'true'},
      );
      setState(() {
        _students = response.data is List
            ? response.data
            : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Anciens élèves'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final s = _students[index];
                      final name =
                          '${s['user']?['first_name'] ?? ''} ${s['user']?['last_name'] ?? ''}'
                              .trim();
                      if (_searchQuery.isNotEmpty &&
                          !name.toLowerCase().contains(
                              _searchQuery.trim().toLowerCase())) {
                        return const SizedBox.shrink();
                      }
                      return ListTile(
                        title: Text(name.isNotEmpty ? name : 'Sans nom'),
                        subtitle: Text(s['student_id']?.toString() ?? ''),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}
