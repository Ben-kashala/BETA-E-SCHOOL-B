import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/discipline_request_modal.dart';

/// Fiches de discipline — synchronisé avec le web (Parent : enfants ; Élève : ses fiches).
class DisciplinePage extends ConsumerStatefulWidget {
  const DisciplinePage({super.key});

  @override
  ConsumerState<DisciplinePage> createState() => _DisciplinePageState();
}

class _DisciplinePageState extends ConsumerState<DisciplinePage> {
  List<dynamic> _records = [];
  List<dynamic> _filteredRecords = [];
  Map<int, List<dynamic>> _requestsByRecord = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedStatus;
  String? _selectedSeverity;

  Future<void> _resolveRecord(int recordId) async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Résoudre la fiche'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Notes de résolution',
            hintText: 'Décrivez les actions prises...',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Résoudre')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService().post(
        '/api/academics/discipline/$recordId/resolve/',
        data: {'resolution_notes': ctrl.text.trim()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fiche résolue avec succès.')),
      );
      await _loadRecords();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de résoudre la fiche.')),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _closeRecord(int recordId) async {
    try {
      await ApiService().post('/api/academics/discipline/$recordId/close/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fiche fermée.')),
      );
      await _loadRecords();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de fermer la fiche.')),
      );
    }
  }

  Future<void> _handleRequestDecision(int requestId, bool approve) async {
    try {
      await ApiService().post(
        '/api/academics/discipline-requests/$requestId/${approve ? 'approve' : 'reject'}/',
        data: {'response': approve ? 'Demande approuvée' : 'Demande rejetée'},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(approve ? 'Demande approuvée.' : 'Demande rejetée.')),
      );
      await _loadRecords();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action impossible sur la demande.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final [recordsRes, requestsRes] = await Future.wait([
        api.get<dynamic>('/api/academics/discipline/', useCache: false),
        api.get<dynamic>('/api/academics/discipline-requests/',
            useCache: false),
      ]);

      final recordsData = recordsRes.data;
      final recordsList = recordsData is List
          ? recordsData
          : (recordsData is Map && recordsData['results'] != null)
              ? (recordsData['results'] as List)
              : <dynamic>[];
      final records = List<dynamic>.from(recordsList);

      final requestsData = requestsRes.data;
      final requestsList = requestsData is List
          ? requestsData
          : (requestsData is Map && requestsData['results'] != null)
              ? (requestsData['results'] as List)
              : <dynamic>[];
      final requests = List<dynamic>.from(requestsList);

      // Grouper les demandes par discipline_record
      final requestsByRecord = <int, List<dynamic>>{};
      for (var request in requests) {
        final recordId = request['discipline_record'];
        if (recordId != null) {
          final id = recordId is int
              ? recordId
              : (recordId is Map ? recordId['id'] : null);
          if (id != null) {
            if (!requestsByRecord.containsKey(id)) {
              requestsByRecord[id] = [];
            }
            requestsByRecord[id]!.add(request);
          }
        }
      }

      if (mounted) {
        setState(() {
          _records = records;
          _requestsByRecord = requestsByRecord;
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _records = [];
          _requestsByRecord = {};
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredRecords = _records.where((r) {
        final record = r as Map? ?? {};
        // Recherche
        if (_searchQuery.isNotEmpty) {
          final description =
              (record['description'] ?? '').toString().toLowerCase();
          final studentName =
              (record['student_name'] ?? '').toString().toLowerCase();
          if (!description.contains(_searchQuery.toLowerCase()) &&
              !studentName.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Filtre statut
        if (_selectedStatus != null) {
          if ((record['status'] ?? '').toString().toUpperCase() !=
              _selectedStatus!.toUpperCase()) {
            return false;
          }
        }
        // Filtre gravité
        if (_selectedSeverity != null) {
          if ((record['severity'] ?? '').toString().toUpperCase() !=
              _selectedSeverity!.toUpperCase()) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Color _severityColor(String? s) {
    switch (s?.toUpperCase()) {
      case 'HIGH':
        return Colors.red;
      case 'MEDIUM':
        return Colors.orange;
      case 'LOW':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Color _statusColor(String? s) {
    switch (s?.toUpperCase()) {
      case 'OPEN':
        return Colors.orange;
      case 'RESOLVED':
        return Colors.green;
      case 'CLOSED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getRequestTypeLabel(String type) {
    switch (type) {
      case 'APOLOGY':
        return 'Demande d\'excuse';
      case 'PUNISHMENT_LIFT':
        return 'Demande de levée de punition';
      case 'APPEAL':
        return 'Recours';
      case 'DISCUSSION':
        return 'Discussion';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final isParent = user?.isParent ?? false;
    final isTeacher = user?.isTeacher ?? false;
    final isAdmin = user?.isAdmin ?? false;
    final isDisciplineOfficer = user?.role == 'DISCIPLINE_OFFICER';
    final canResolve = isTeacher || isAdmin || isDisciplineOfficer;
    final canClose = isAdmin || isDisciplineOfficer;
    final canProcessRequests = isAdmin || isDisciplineOfficer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiches de discipline'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher une fiche...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'status',
                label: 'Statut',
                values: [
                  FilterValue(value: 'OPEN', label: 'Ouverte'),
                  FilterValue(value: 'RESOLVED', label: 'Résolue'),
                  FilterValue(value: 'CLOSED', label: 'Fermée'),
                ],
                selectedValue: _selectedStatus,
              ),
              FilterOption(
                key: 'severity',
                label: 'Gravité',
                values: [
                  FilterValue(value: 'LOW', label: 'Faible'),
                  FilterValue(value: 'MEDIUM', label: 'Moyenne'),
                  FilterValue(value: 'HIGH', label: 'Élevée'),
                ],
                selectedValue: _selectedSeverity,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() {
                _selectedStatus = filters['status'];
                _selectedSeverity = filters['severity'];
              });
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecords.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.gavel_outlined,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              isParent
                                  ? 'Aucune fiche pour vos enfants'
                                  : 'Aucune fiche de discipline',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRecords,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredRecords.length,
                          itemBuilder: (context, index) {
                            final r = _filteredRecords[index] as Map? ?? {};
                            final type = r['type']?.toString() ?? '';
                            final severity = r['severity']?.toString() ?? '';
                            final status = r['status']?.toString() ?? '';
                            final dateStr = r['date'] ?? r['created_at'];
                            final description =
                                r['description']?.toString() ?? '';
                            final studentName =
                                r['student_name']?.toString() ?? '';
                            final className = r['class_name']?.toString() ?? '';

                            final recordId = r['id'] as int?;
                            final recordRequests = recordId != null
                                ? _requestsByRecord[recordId] ?? []
                                : [];
                            final hasPendingRequest = recordRequests
                                .any((req) => req['status'] == 'PENDING');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                leading: CircleAvatar(
                                  backgroundColor: _severityColor(severity),
                                  child: Icon(
                                    type.toUpperCase() == 'POSITIVE'
                                        ? Icons.thumb_up
                                        : Icons.gavel,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  isParent
                                      ? studentName
                                      : (description.isNotEmpty
                                          ? description
                                          : 'Fiche #${r['id']}'),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isParent && className.isNotEmpty)
                                      Text(className),
                                    if (dateStr != null)
                                      Text(DateFormat('dd/MM/yyyy').format(
                                          DateTime.tryParse(
                                                  dateStr.toString()) ??
                                              DateTime.now())),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status)
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(status,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: _statusColor(status))),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(severity,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    _severityColor(severity))),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: isParent &&
                                        recordId != null &&
                                        !hasPendingRequest
                                    ? IconButton(
                                        icon: const Icon(Icons.add),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) =>
                                                DisciplineRequestModal(
                                              disciplineRecordId: recordId,
                                              onSubmitted: () {
                                                _loadRecords();
                                              },
                                            ),
                                          );
                                        },
                                      )
                                    : null,
                                onExpansionChanged: (expanded) {
                                  // Keep default expansion behavior.
                                },
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (description.isNotEmpty) ...[
                                          Text(
                                            'Description',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(description),
                                          const SizedBox(height: 16),
                                        ],
                                        // Demandes existantes
                                        if (isParent &&
                                            recordRequests.isNotEmpty) ...[
                                          Text(
                                            'Mes demandes',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          ...recordRequests.map((req) {
                                            final reqStatus =
                                                req['status'] ?? '';
                                            final reqType =
                                                req['request_type'] ?? '';
                                            final reqMessage =
                                                req['message'] ?? '';
                                            final reqResponse = req['response'];
                                            final reqRespondedBy =
                                                req['responded_by_name'];
                                            final reqRespondedAt =
                                                req['responded_at'];

                                            return Card(
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              color: reqStatus == 'APPROVED'
                                                  ? Colors.green.shade50
                                                  : reqStatus == 'REJECTED'
                                                      ? Colors.red.shade50
                                                      : Colors.orange.shade50,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Chip(
                                                          label: Text(
                                                            reqStatus ==
                                                                    'PENDING'
                                                                ? 'En attente'
                                                                : reqStatus ==
                                                                        'APPROVED'
                                                                    ? 'Approuvée'
                                                                    : 'Rejetée',
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        12),
                                                          ),
                                                          backgroundColor:
                                                              reqStatus ==
                                                                      'APPROVED'
                                                                  ? Colors.green
                                                                  : reqStatus ==
                                                                          'REJECTED'
                                                                      ? Colors
                                                                          .red
                                                                      : Colors
                                                                          .orange,
                                                          labelStyle:
                                                              const TextStyle(
                                                                  color: Colors
                                                                      .white),
                                                        ),
                                                        Text(
                                                          _getRequestTypeLabel(
                                                              reqType),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodySmall,
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      reqMessage,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodyMedium,
                                                    ),
                                                    if (reqResponse !=
                                                        null) ...[
                                                      const SizedBox(
                                                          height: 12),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(8),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(4),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Réponse de l\'école:',
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .labelSmall,
                                                            ),
                                                            const SizedBox(
                                                                height: 4),
                                                            Text(reqResponse),
                                                            if (reqRespondedBy !=
                                                                    null ||
                                                                reqRespondedAt !=
                                                                    null) ...[
                                                              const SizedBox(
                                                                  height: 4),
                                                              Text(
                                                                'Par ${reqRespondedBy ?? 'N/A'} ${reqRespondedAt != null ? 'le ${DateFormat('dd/MM/yyyy').format(DateTime.parse(reqRespondedAt))}' : ''}',
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .labelSmall,
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ] else if (isParent &&
                                            recordId != null &&
                                            !hasPendingRequest) ...[
                                          Center(
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (context) =>
                                                      DisciplineRequestModal(
                                                    disciplineRecordId:
                                                        recordId,
                                                    onSubmitted: () {
                                                      _loadRecords();
                                                    },
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.add),
                                              label: const Text(
                                                  'Créer une demande'),
                                            ),
                                          ),
                                        ] else if (!isParent &&
                                            recordRequests.isNotEmpty) ...[
                                          Text(
                                            'Demandes des parents',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          ...recordRequests.map((req) {
                                            final reqStatus =
                                                (req['status'] ?? '')
                                                    .toString();
                                            final reqId = req['id'] as int?;
                                            return Card(
                                              margin: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(10),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _getRequestTypeLabel(
                                                          (req['request_type'] ??
                                                                  '')
                                                              .toString()),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelLarge,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                        '${req['message'] ?? ''}'),
                                                    const SizedBox(height: 6),
                                                    Text('Statut: $reqStatus'),
                                                    if (canProcessRequests &&
                                                        reqStatus ==
                                                            'PENDING' &&
                                                        reqId != null) ...[
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        children: [
                                                          OutlinedButton(
                                                            onPressed: () =>
                                                                _handleRequestDecision(
                                                                    reqId,
                                                                    false),
                                                            child: const Text(
                                                                'Rejeter'),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          ElevatedButton(
                                                            onPressed: () =>
                                                                _handleRequestDecision(
                                                                    reqId,
                                                                    true),
                                                            child: const Text(
                                                                'Approuver'),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                        if (!isParent &&
                                            canResolve &&
                                            recordId != null) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              if (status.toUpperCase() ==
                                                  'OPEN')
                                                ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _resolveRecord(recordId),
                                                  icon: const Icon(Icons
                                                      .check_circle_outline),
                                                  label: const Text('Résoudre'),
                                                ),
                                              if (canClose &&
                                                  (status.toUpperCase() ==
                                                          'OPEN' ||
                                                      status.toUpperCase() ==
                                                          'RESOLVED')) ...[
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _closeRecord(recordId),
                                                  icon: const Icon(
                                                      Icons.lock_outline),
                                                  label: const Text('Fermer'),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
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
