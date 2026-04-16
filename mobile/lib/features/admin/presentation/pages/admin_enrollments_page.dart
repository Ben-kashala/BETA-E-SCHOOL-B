import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../accountant/presentation/widgets/accountant_bottom_nav.dart';
import '../widgets/admin_bottom_nav.dart';

/// Liste des demandes d’inscription — alignée sur le web (`admin/Enrollments.tsx`).
/// [baseRoute] : `/admin/enrollments` ou `/accountant/enrollments` pour le sous-chemin `…/new`.
class AdminEnrollmentsPage extends ConsumerStatefulWidget {
  const AdminEnrollmentsPage({
    super.key,
    this.baseRoute = '/admin/enrollments',
  });

  /// Route parente pour `context.push('$baseRoute/new')`.
  final String baseRoute;

  @override
  ConsumerState<AdminEnrollmentsPage> createState() => _AdminEnrollmentsPageState();
}

class _AdminEnrollmentsPageState extends ConsumerState<AdminEnrollmentsPage> {
  List<dynamic> _all = [];
  bool _loading = true;
  String _searchQuery = '';
  DateTime? _filterDate;

  bool get _canApproveReject => ref.watch(authProvider).user?.role != 'ACCOUNTANT';

  List<dynamic> get _filtered {
    return _all.where((raw) {
      final app = raw as Map<String, dynamic>;
      if (_filterDate != null) {
        final created = app['created_at']?.toString();
        if (created == null) return false;
        try {
          final d = DateTime.parse(created);
          final appDay = DateTime(d.year, d.month, d.day);
          final f = _filterDate!;
          final target = DateTime(f.year, f.month, f.day);
          if (appDay != target) return false;
        } catch (_) {
          return false;
        }
      }
      final q = _searchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      final sid = '${app['generated_student_id'] ?? ''}'.toLowerCase();
      final fn = '${app['first_name'] ?? ''}'.toLowerCase();
      final ln = '${app['last_name'] ?? ''}'.toLowerCase();
      final full = '$fn $ln'.trim();
      final cls = '${app['requested_class_name'] ?? ''}'.toLowerCase();
      return sid.contains(q) ||
          fn.contains(q) ||
          ln.contains(q) ||
          full.contains(q) ||
          cls.contains(q);
    }).toList();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService().get('/api/enrollment/applications/', useCache: false);
      if (!mounted) return;
      setState(() {
        _all = _extractList(response.data);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id) async {
    try {
      await ApiService().post('/api/enrollment/applications/$id/approve/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription approuvée')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    }
  }

  Future<void> _reject(int id) async {
    try {
      await ApiService().post('/api/enrollment/applications/$id/reject/', data: {
        'notes': 'Rejeté depuis l’application mobile',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inscription rejetée')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    }
  }

  static String _statusLabel(String? s) {
    switch (s) {
      case 'PENDING':
        return 'En attente';
      case 'APPROVED':
        return 'Approuvée';
      case 'REJECTED':
        return 'Rejetée';
      case 'COMPLETED':
        return 'Complétée';
      default:
        return s ?? '—';
    }
  }

  static Color _statusColor(String? s) {
    switch (s) {
      case 'PENDING':
        return Colors.orange;
      case 'APPROVED':
        return Colors.green;
      case 'REJECTED':
        return Colors.red;
      case 'COMPLETED':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _fullName(Map<String, dynamic> app) {
    return [app['first_name'], app['last_name'], app['middle_name']]
        .where((e) => e != null && '$e'.trim().isNotEmpty)
        .map((e) => '$e'.trim())
        .join(' ');
  }

  String _contactLine(Map<String, dynamic> app) {
    final em = app['email']?.toString().trim();
    final ph = app['phone']?.toString().trim();
    if (em != null && em.isNotEmpty) return em;
    if (ph != null && ph.isNotEmpty) return ph;
    return '—';
  }

  Future<void> _openDetail(Map<String, dynamic> enrollment) async {
    final id = enrollment['id'];
    final iid = id is int ? id : int.tryParse('$id');
    var detail = Map<String, dynamic>.from(enrollment);
    if (iid != null) {
      try {
        final res = await ApiService().get('/api/enrollment/applications/$iid/', useCache: false);
        if (res.data is Map) {
          detail = Map<String, dynamic>.from(res.data as Map);
        }
      } catch (_) {}
    }
    if (!mounted) return;
    final status = detail['status']?.toString() ?? 'PENDING';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fullName(detail).isEmpty ? 'Détail inscription' : _fullName(detail)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ID élève : ${detail['generated_student_id'] ?? '—'}'),
              const SizedBox(height: 8),
              Text('Classe : ${detail['requested_class_name'] ?? 'N/A'}'),
              const SizedBox(height: 8),
              Text('Parent : ${detail['parent_name'] ?? '—'}'),
              const SizedBox(height: 8),
              Text('Statut : ${_statusLabel(status)}'),
              if (detail['created_at'] != null) ...[
                const SizedBox(height: 8),
                Text('Date : ${_formatDate(detail['created_at'])}'),
              ],
              if (detail['notes'] != null && '${detail['notes']}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Notes : ${detail['notes']}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
          if (status == 'PENDING' && _canApproveReject && iid != null) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _approve(iid);
              },
              child: const Text('Approuver', style: TextStyle(color: Colors.green)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _reject(iid);
              },
              child: const Text('Rejeter', style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(dynamic v) {
    if (v == null) return '—';
    try {
      return DateFormat('dd/MM/yyyy', 'fr_FR').format(DateTime.parse(v.toString()));
    } catch (_) {
      return '$v';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = _searchQuery.trim().isNotEmpty || _filterDate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Inscriptions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.moduleButtonColor,
                foregroundColor: AppTheme.onAvatarBackgroundColor,
              ),
              onPressed: () => context.push('${widget.baseRoute}/new'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Inscrire'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.baseRoute.startsWith('/accountant')
          ? const AccountantBottomNav()
          : widget.baseRoute.startsWith('/admin')
              ? const AdminBottomNav()
              : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Card(
              color: AppTheme.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      style: const TextStyle(color: Colors.black87),
                      cursorColor: Colors.black87,
                      decoration: const InputDecoration(
                        hintText: 'Rechercher par ID élève, Nom ou Classe...',
                        hintStyle: TextStyle(color: Colors.black54),
                        prefixIcon: Icon(Icons.search, color: Colors.black54),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final now = DateTime.now();
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _filterDate ?? now,
                                firstDate: DateTime(now.year - 10),
                                lastDate: DateTime(now.year + 2),
                              );
                              if (d != null) setState(() => _filterDate = d);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Date d’inscription',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today_outlined),
                                isDense: true,
                              ),
                              child: Text(
                                _filterDate != null
                                    ? DateFormat('dd/MM/yyyy', 'fr_FR').format(_filterDate!)
                                    : 'jj/mm/aaaa',
                                style: TextStyle(
                                  color: _filterDate != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (hasFilters) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => setState(() {
                              _searchQuery = '';
                              _filterDate = null;
                            }),
                            child: const Text('Réinitialiser'),
                          ),
                        ],
                      ],
                    ),
                    if (hasFilters)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${_filtered.length} inscription(s) trouvée(s) sur ${_all.length}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _all.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucune demande d\'inscription trouvée',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : _filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Aucune inscription ne correspond à votre recherche.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: ScrollContentPadding.page(context, trailing: 24),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1F2E5A),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: DataTable(
                                    columnSpacing: 20,
                                    headingRowColor: WidgetStateProperty.all(
                                      const Color(0xFF263766),
                                    ),
                                    dataRowMinHeight: 52,
                                    dataRowMaxHeight: 60,
                                    dividerThickness: 0.6,
                                    headingTextStyle: const TextStyle(
                                      color: Color(0xFFE8EEFF),
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                      fontSize: 11,
                                    ),
                                    dataTextStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12.5,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('ID Élève')),
                                      DataColumn(label: Text('Nom complet')),
                                      DataColumn(label: Text('Contact')),
                                      DataColumn(label: Text('Classe')),
                                      DataColumn(label: Text('Parent')),
                                      DataColumn(label: Text('Date')),
                                      DataColumn(label: Text('Statut')),
                                      DataColumn(label: Text('Actions')),
                                    ],
                                    rows: _filtered.map((raw) {
                                      final enrollment = raw as Map<String, dynamic>;
                                      final status = enrollment['status']?.toString() ?? 'PENDING';
                                      final name = _fullName(enrollment);
                                      final sid = enrollment['generated_student_id']?.toString();
                                      final idRaw = enrollment['id'];
                                      final eid = idRaw is int ? idRaw : int.tryParse('$idRaw');

                                      return DataRow(
                                        color: WidgetStateProperty.all(
                                          const Color(0xFF1F2E5A),
                                        ),
                                        cells: [
                                          DataCell(Text(sid ?? 'En attente', style: const TextStyle(fontFamily: 'monospace'))),
                                          DataCell(Text(name.isEmpty ? 'Élève' : name.toUpperCase())),
                                          DataCell(Text(_contactLine(enrollment))),
                                          DataCell(Text('${enrollment['requested_class_name'] ?? 'N/A'}'.toUpperCase())),
                                          DataCell(Text('${enrollment['parent_name'] ?? '—'}'.toUpperCase())),
                                          DataCell(Text(_formatDate(enrollment['created_at']))),
                                          DataCell(
                                            Text(
                                              _statusLabel(status),
                                              style: TextStyle(
                                                color: _statusColor(status),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Détails',
                                                  onPressed: () => _openDetail(enrollment),
                                                  icon: Icon(
                                                    Icons.visibility_outlined,
                                                    color: const Color(0xFFE8EEFF),
                                                  ),
                                                ),
                                                if (status == 'PENDING' && _canApproveReject && eid != null) ...[
                                                  IconButton(
                                                    tooltip: 'Approuver',
                                                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                                                    onPressed: () => _approve(eid),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Rejeter',
                                                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                                                    onPressed: () => _reject(eid),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                  ),
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

}
