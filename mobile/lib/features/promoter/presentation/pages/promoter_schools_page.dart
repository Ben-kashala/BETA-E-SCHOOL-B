import 'package:flutter/material.dart';
import '../../../../core/network/api_service.dart';

class PromoterSchoolsPage extends StatefulWidget {
  const PromoterSchoolsPage({super.key});

  @override
  State<PromoterSchoolsPage> createState() => _PromoterSchoolsPageState();
}

class _PromoterSchoolsPageState extends State<PromoterSchoolsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _schools = [];
  List<dynamic> _filteredSchools = [];
  String _searchQuery = '';
  String _typeFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  Future<void> _loadSchools() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/api/schools/schools/my-schools/',
        useCache: false,
      );
      final data = response.data;
      final schools = data is List
          ? data
          : (data is Map && data['results'] is List
              ? data['results'] as List
              : []);

      setState(() {
        _schools = schools;
        _errorMessage = null;
        _applyFilters();
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _schools = [];
        _filteredSchools = [];
        _errorMessage = 'Erreur lors du chargement des écoles.';
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _schools.where((item) {
      final school = item as Map<String, dynamic>;
      final name = (school['name'] ?? '').toString().toLowerCase();
      final code = (school['code'] ?? '').toString().toLowerCase();
      final city = (school['city'] ?? '').toString().toLowerCase();
      final type = (school['school_type'] ?? '').toString().toUpperCase();

      if (q.isNotEmpty &&
          !name.contains(q) &&
          !code.contains(q) &&
          !city.contains(q)) {
        return false;
      }
      if (_typeFilter != 'ALL' && type != _typeFilter) {
        return false;
      }
      return true;
    }).toList();

    setState(() {
      _filteredSchools = filtered;
    });
  }

  String _schoolTypeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'MATERNELLE':
        return 'Maternelle';
      case 'PRIMAIRE':
        return 'Primaire';
      case 'HUMANITAIRE':
        return 'Humanitaire';
      default:
        return type;
    }
  }

  void _openSchoolDetails(Map<String, dynamic> school) {
    final payments =
        (school['payments_totals'] as Map?)?.cast<String, dynamic>() ?? {};
    final expenses =
        (school['expenses_totals'] as Map?)?.cast<String, dynamic>() ?? {};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                school['name']?.toString() ?? 'École',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('${school['code'] ?? '-'} - ${school['city'] ?? '-'}'),
              const SizedBox(height: 8),
              Text(
                  'Type: ${_schoolTypeLabel('${school['school_type'] ?? '-'}')}'),
              Text('Année scolaire: ${school['academic_year'] ?? '-'}'),
              Text("Élèves: ${school['students_count'] ?? 0}"),
              const Divider(height: 18),
              Text('Entrées', style: Theme.of(ctx).textTheme.titleMedium),
              if (payments.isEmpty)
                const Text('0.00')
              else
                ...payments.entries.map(
                  (entry) => Text('${_formatAmount(entry.value)} ${entry.key}'),
                ),
              const SizedBox(height: 8),
              Text('Dépenses', style: Theme.of(ctx).textTheme.titleMedium),
              if (expenses.isEmpty)
                const Text('0.00')
              else
                ...expenses.entries.map(
                  (entry) => Text('${_formatAmount(entry.value)} ${entry.key}'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(dynamic value) {
    final number = value is num ? value.toDouble() : 0.0;
    return number.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes écoles'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher une école (nom, code, ville)...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _applyFilters();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tous'),
                  selected: _typeFilter == 'ALL',
                  onSelected: (_) {
                    _typeFilter = 'ALL';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Maternelle'),
                  selected: _typeFilter == 'MATERNELLE',
                  onSelected: (_) {
                    _typeFilter = 'MATERNELLE';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Primaire'),
                  selected: _typeFilter == 'PRIMAIRE',
                  onSelected: (_) {
                    _typeFilter = 'PRIMAIRE';
                    _applyFilters();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Humanitaire'),
                  selected: _typeFilter == 'HUMANITAIRE',
                  onSelected: (_) {
                    _typeFilter = 'HUMANITAIRE';
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadSchools,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? ListView(
                          children: [
                            const SizedBox(height: 120),
                            Center(child: Text(_errorMessage!)),
                            const SizedBox(height: 8),
                            Center(
                              child: ElevatedButton(
                                onPressed: _loadSchools,
                                child: const Text('Réessayer'),
                              ),
                            ),
                          ],
                        )
                      : _filteredSchools.isEmpty
                          ? const Center(child: Text("Aucune école trouvée."))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filteredSchools.length,
                              itemBuilder: (context, index) {
                                final school = _filteredSchools[index]
                                    as Map<String, dynamic>;
                                final payments =
                                    (school['payments_totals'] as Map?)
                                            ?.cast<String, dynamic>() ??
                                        {};
                                final expenses =
                                    (school['expenses_totals'] as Map?)
                                            ?.cast<String, dynamic>() ??
                                        {};

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _openSchoolDetails(school),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            school['name']?.toString() ??
                                                'École',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${school['code'] ?? '-'} - ${school['city'] ?? '-'}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Type: ${_schoolTypeLabel('${school['school_type'] ?? '-'}')}',
                                          ),
                                          Text(
                                              "Élèves: ${school['students_count'] ?? 0}"),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Entrées: ${payments.isEmpty ? '0.00' : payments.entries.map((e) => '${_formatAmount(e.value)} ${e.key}').join(' | ')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Dépenses: ${expenses.isEmpty ? '0.00' : expenses.entries.map((e) => '${_formatAmount(e.value)} ${e.key}').join(' | ')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
