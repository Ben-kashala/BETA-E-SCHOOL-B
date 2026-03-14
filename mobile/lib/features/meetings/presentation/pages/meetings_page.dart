import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';

class MeetingsPage extends ConsumerStatefulWidget {
  const MeetingsPage({super.key});

  @override
  ConsumerState<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends ConsumerState<MeetingsPage> {
  List<dynamic> _meetings = [];
  List<dynamic> _filteredMeetings = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedStatus;
  String? _copiedCode;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }

  Future<void> _loadMeetings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService().get('/api/meetings/');
      setState(() {
        _meetings = response.data is List<dynamic>
            ? response.data
            : (response.data['results'] ?? []);
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateMeeting() async {
    List<dynamic> teachers = [];
    List<dynamic> parents = [];
    List<dynamic> students = [];
    try {
      final t = await ApiService().get('/api/auth/teachers/', useCache: false);
      teachers = t.data is List ? t.data : (t.data['results'] ?? []);
      final p = await ApiService().get('/api/auth/parents/', useCache: false);
      parents = p.data is List ? p.data : (p.data['results'] ?? []);
      final s = await ApiService().get('/api/auth/students/', useCache: false);
      students = s.data is List ? s.data : (s.data['results'] ?? []);
    } catch (_) {}

    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final description = TextEditingController();
    int? teacherId = teachers.isNotEmpty ? (teachers.first['id'] as int) : null;
    int? parentId;
    int? studentId;
    String meetingType = 'INDIVIDUAL';
    DateTime meetingDate = DateTime.now().add(const Duration(days: 1));
    int durationMinutes = 30;
    bool loading = false;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nouvelle réunion', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Titre *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'Description *', alignLabelWithHint: true),
                      maxLines: 2,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: teacherId,
                      decoration: const InputDecoration(labelText: 'Enseignant *'),
                      items: teachers.map((t) {
                        final u = t['user'] ?? {};
                        final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                        return DropdownMenuItem<int>(value: t['id'] as int, child: Text(name.isEmpty ? 'Enseignant' : name));
                      }).toList(),
                      onChanged: (v) => setModalState(() => teacherId = v),
                      validator: (v) => v == null ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: parentId,
                      decoration: const InputDecoration(labelText: 'Parent (optionnel)'),
                      items: [const DropdownMenuItem<int>(value: null, child: Text('— Aucun —')), ...parents.map((p) {
                        final u = p['user'] ?? {};
                        final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                        return DropdownMenuItem<int>(value: p['id'] as int, child: Text(name.isEmpty ? 'Parent' : name));
                      })],
                      onChanged: (v) => setModalState(() => parentId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: studentId,
                      decoration: const InputDecoration(labelText: 'Élève (optionnel)'),
                      items: [const DropdownMenuItem<int>(value: null, child: Text('— Aucun —')), ...students.map((s) {
                        final name = s['user_name'] ?? '${s['user']?['first_name'] ?? ''} ${s['user']?['last_name'] ?? ''}'.trim();
                        return DropdownMenuItem<int>(value: s['id'] as int, child: Text(name.isEmpty ? 'Élève' : name));
                      })],
                      onChanged: (v) => setModalState(() => studentId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: meetingType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'INDIVIDUAL', child: Text('Individuelle')),
                        DropdownMenuItem(value: 'GROUP', child: Text('Groupe')),
                        DropdownMenuItem(value: 'PARENT_MEETING', child: Text('Réunion parent')),
                      ],
                      onChanged: (v) => setModalState(() => meetingType = v ?? 'INDIVIDUAL'),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date et heure'),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(meetingDate)),
                      onTap: () async {
                        final date = await showDatePicker(context: ctx, initialDate: meetingDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (date != null) {
                          final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(meetingDate));
                          if (time != null) setModalState(() => meetingDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: durationMinutes,
                      decoration: const InputDecoration(labelText: 'Durée (minutes)'),
                      items: [15, 30, 45, 60, 90].map((m) => DropdownMenuItem<int>(value: m, child: Text('$m min'))).toList(),
                      onChanged: (v) => setModalState(() => durationMinutes = v ?? 30),
                    ),
                    const SizedBox(height: 24),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => loading = true);
                                try {
                                  await ApiService().post('/api/meetings/', data: {
                                    'title': title.text.trim(),
                                    'description': description.text.trim(),
                                    'teacher': teacherId,
                                    'parent': parentId,
                                    'student': studentId,
                                    'meeting_type': meetingType,
                                    'meeting_date': meetingDate.toUtc().toIso8601String(),
                                    'duration_minutes': durationMinutes,
                                    'status': 'SCHEDULED',
                                  });
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Réunion créée.')));
                                    _loadMeetings();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')));
                                }
                              },
                              child: const Text('Créer'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _applyFilters() {
    setState(() {
      _filteredMeetings = _meetings.where((meeting) {
        // Recherche
        if (_searchQuery.isNotEmpty) {
          final title = (meeting['title'] ?? '').toString().toLowerCase();
          final description = (meeting['description'] ?? '').toString().toLowerCase();
          if (!title.contains(_searchQuery.toLowerCase()) &&
              !description.contains(_searchQuery.toLowerCase())) {
            return false;
          }
        }
        // Filtre statut
        if (_selectedStatus != null) {
          if ((meeting['status'] ?? 'scheduled').toString().toLowerCase() != _selectedStatus!.toLowerCase()) {
            return false;
          }
        }
        return true;
      }).toList();
    });
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'scheduled':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réunions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateMeeting,
          ),
        ],
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher une réunion...',
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              _applyFilters();
            },
            filters: [
              FilterOption(
                key: 'status',
                label: 'Statut',
                values: [
                  FilterValue(value: 'scheduled', label: 'Programmée'),
                  FilterValue(value: 'completed', label: 'Terminée'),
                  FilterValue(value: 'cancelled', label: 'Annulée'),
                ],
                selectedValue: _selectedStatus,
              ),
            ],
            onFiltersChanged: (filters) {
              setState(() => _selectedStatus = filters['status']);
              _applyFilters();
            },
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMeetings.isEmpty
                    ? const Center(child: Text('Aucune réunion programmée'))
                    : RefreshIndicator(
                        onRefresh: _loadMeetings,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredMeetings.length,
                          itemBuilder: (context, index) {
                            final meeting = _filteredMeetings[index];
                      final date = meeting['date'] != null
                          ? DateTime.parse(meeting['date'])
                          : null;
                      final status = meeting['status'] ?? 'scheduled';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: _getStatusColor(status),
                            child: const Icon(Icons.event, color: Colors.white),
                          ),
                          title: Text(meeting['title'] ?? 'Réunion'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (meeting['description'] != null)
                                Text(
                                  meeting['description'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              const SizedBox(height: 4),
                              if (date != null)
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      DateFormat('dd/MM/yyyy HH:mm').format(date),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (meeting['description'] != null) ...[
                                    Text(
                                      meeting['description'],
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  if (meeting['teacher'] != null) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 16),
                                        const SizedBox(width: 8),
                                        Text('Avec: ${meeting['teacher']['name'] ?? 'N/A'}'),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  // Lien visioconférence
                                  if (meeting['video_link'] != null) ...[
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        final url = meeting['video_link'];
                                        if (url != null && await canLaunchUrl(Uri.parse(url))) {
                                          await launchUrl(
                                            Uri.parse(url),
                                            mode: LaunchMode.externalApplication,
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.video_call),
                                      label: const Text('Rejoindre la visioconférence'),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 48),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  // Code de réunion
                                  if (meeting['meeting_id'] != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Code de réunion',
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  meeting['meeting_id'],
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                        fontFamily: 'monospace',
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _copiedCode == 'meeting-${meeting['id']}'
                                                  ? Icons.check
                                                  : Icons.copy,
                                            ),
                                            onPressed: () {
                                              Clipboard.setData(
                                                ClipboardData(text: meeting['meeting_id']),
                                              );
                                              setState(() {
                                                _copiedCode = 'meeting-${meeting['id']}';
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Code copié')),
                                              );
                                              Future.delayed(const Duration(seconds: 2), () {
                                                if (mounted) {
                                                  setState(() => _copiedCode = null);
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  // Mot de passe de réunion
                                  if (meeting['meeting_password'] != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Mot de passe',
                                                  style: Theme.of(context).textTheme.labelSmall,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  meeting['meeting_password'],
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                        fontFamily: 'monospace',
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _copiedCode == 'password-${meeting['id']}'
                                                  ? Icons.check
                                                  : Icons.copy,
                                            ),
                                            onPressed: () {
                                              Clipboard.setData(
                                                ClipboardData(text: meeting['meeting_password']),
                                              );
                                              setState(() {
                                                _copiedCode = 'password-${meeting['id']}';
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Mot de passe copié')),
                                              );
                                              Future.delayed(const Duration(seconds: 2), () {
                                                if (mounted) {
                                                  setState(() => _copiedCode = null);
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
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
