import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../../../admin/presentation/widgets/admin_bottom_nav.dart';
import '../../../discipline_officer/presentation/widgets/discipline_officer_bottom_nav.dart';

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

  DateTime? _parseMeetingDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  int? _extractId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Map) {
      final id = value['id'];
      if (id is int) return id;
      if (id is num) return id.toInt();
    }
    return null;
  }

  Future<void> _openMeetingLink(dynamic rawUrl) async {
    final urlText = rawUrl?.toString().trim() ?? '';
    if (urlText.isEmpty) return;

    final uri = Uri.tryParse(urlText);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien de réunion invalide.')),
      );
      return;
    }

    try {
      final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          ) ||
          await launchUrl(uri, mode: LaunchMode.externalApplication) ||
          await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible d’ouvrir le lien de réunion sur cet appareil.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’ouvrir le lien de réunion.'),
        ),
      );
    }
  }

  Future<void> _showMeetingForm({dynamic existingMeeting}) async {
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
    final location = TextEditingController();
    final videoLink = TextEditingController();
    final isEditing = existingMeeting != null;
    int? teacherId = _extractId(existingMeeting?['teacher']) ??
        (teachers.isNotEmpty ? (teachers.first['id'] as int) : null);
    int? parentId = _extractId(existingMeeting?['parent']);
    int? studentId = _extractId(existingMeeting?['student']);
    String meetingType = (existingMeeting?['meeting_type'] ?? 'INDIVIDUAL').toString();
    DateTime meetingDate = _parseMeetingDate(existingMeeting?['meeting_date']) ??
        DateTime.now().add(const Duration(days: 1));
    int durationMinutes = existingMeeting?['duration_minutes'] is num
        ? (existingMeeting['duration_minutes'] as num).toInt()
        : 30;
    String? videoPlatform = existingMeeting?['video_platform']?.toString();
    bool autoGenerateVideoLink = false;
    bool isPublished = existingMeeting?['is_published'] == true;
    List<int> selectedTeacherIds = [];
    List<int> selectedParentIds = [];
    bool loading = false;

    title.text = existingMeeting?['title']?.toString() ?? '';
    description.text = existingMeeting?['description']?.toString() ?? '';
    location.text = existingMeeting?['location']?.toString() ?? '';
    videoLink.text = existingMeeting?['video_link']?.toString() ?? '';

    String teacherName(dynamic teacher) {
      final u = teacher['user'] ?? {};
      final name =
          '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
      return name.isEmpty ? 'Enseignant' : name;
    }

    String parentName(dynamic parent) {
      final u = parent['user'] ?? {};
      final name =
          '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
      return name.isEmpty ? 'Parent' : name;
    }

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
                    Text(
                      isEditing ? 'Modifier la réunion' : 'Nouvelle réunion',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
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
                    DropdownButtonFormField<String>(
                      initialValue: meetingType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'INDIVIDUAL', child: Text('Individuelle')),
                        DropdownMenuItem(value: 'GROUP', child: Text('Groupe')),
                        DropdownMenuItem(value: 'GENERAL', child: Text('Générale')),
                        DropdownMenuItem(value: 'TEACHER_MEETING', child: Text('Réunion avec enseignant')),
                        DropdownMenuItem(value: 'PARENT_MEETING', child: Text('Réunion avec parent')),
                      ],
                      onChanged: (v) => setModalState(() => meetingType = v ?? 'INDIVIDUAL'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: teacherId,
                      decoration: const InputDecoration(labelText: 'Enseignant principal'),
                      items: teachers.map((t) {
                        return DropdownMenuItem<int>(
                          value: t['id'] as int,
                          child: Text(teacherName(t)),
                        );
                      }).toList(),
                      onChanged: (v) => setModalState(() => teacherId = v),
                      validator: (v) => v == null ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    if (meetingType == 'TEACHER_MEETING' || meetingType == 'GROUP' || meetingType == 'GENERAL') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(child: Text('Enseignants supplémentaires', style: TextStyle(fontWeight: FontWeight.w600))),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                final ids = teachers
                                    .map((t) => t['id'])
                                    .whereType<int>()
                                    .where((id) => id != teacherId)
                                    .toList();
                                if (selectedTeacherIds.length == ids.length) {
                                  selectedTeacherIds = [];
                                } else {
                                  selectedTeacherIds = ids;
                                }
                              });
                            },
                            child: Text(
                              selectedTeacherIds.length ==
                                      teachers
                                          .map((t) => t['id'])
                                          .whereType<int>()
                                          .where((id) => id != teacherId)
                                          .length
                                  ? 'Tout désélectionner'
                                  : 'Tout sélectionner',
                            ),
                          ),
                        ],
                      ),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: teachers.map((t) {
                            final id = t['id'] as int;
                            if (id == teacherId) return const SizedBox.shrink();
                            return CheckboxListTile(
                              value: selectedTeacherIds.contains(id),
                              title: Text(teacherName(t)),
                              onChanged: (checked) {
                                setModalState(() {
                                  if (checked == true) {
                                    selectedTeacherIds = [...selectedTeacherIds, id];
                                  } else {
                                    selectedTeacherIds =
                                        selectedTeacherIds.where((e) => e != id).toList();
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<int>(
                      initialValue: parentId,
                      decoration: const InputDecoration(labelText: 'Parent (optionnel)'),
                      items: [const DropdownMenuItem<int>(value: null, child: Text('— Aucun —')), ...parents.map((p) {
                        return DropdownMenuItem<int>(value: p['id'] as int, child: Text(parentName(p)));
                      })],
                      onChanged: (v) => setModalState(() => parentId = v),
                    ),
                    const SizedBox(height: 12),
                    if (meetingType == 'PARENT_MEETING' || meetingType == 'GROUP' || meetingType == 'GENERAL' || meetingType == 'TEACHER_MEETING') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(child: Text('Parents participants', style: TextStyle(fontWeight: FontWeight.w600))),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                final ids = parents.map((p) => p['id']).whereType<int>().toList();
                                if (selectedParentIds.length == ids.length) {
                                  selectedParentIds = [];
                                } else {
                                  selectedParentIds = ids;
                                }
                              });
                            },
                            child: Text(
                              selectedParentIds.length ==
                                      parents.map((p) => p['id']).whereType<int>().length
                                  ? 'Tout désélectionner'
                                  : 'Tout sélectionner',
                            ),
                          ),
                        ],
                      ),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: parents.map((p) {
                            final id = p['id'] as int;
                            return CheckboxListTile(
                              value: selectedParentIds.contains(id),
                              title: Text(parentName(p)),
                              onChanged: (checked) {
                                setModalState(() {
                                  if (checked == true) {
                                    selectedParentIds = [...selectedParentIds, id];
                                  } else {
                                    selectedParentIds =
                                        selectedParentIds.where((e) => e != id).toList();
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<int>(
                      initialValue: studentId,
                      decoration: const InputDecoration(labelText: 'Élève (optionnel)'),
                      items: [const DropdownMenuItem<int>(value: null, child: Text('— Aucun —')), ...students.map((s) {
                        final name = s['user_name'] ?? '${s['user']?['first_name'] ?? ''} ${s['user']?['last_name'] ?? ''}'.trim();
                        return DropdownMenuItem<int>(value: s['id'] as int, child: Text(name.isEmpty ? 'Élève' : name));
                      })],
                      onChanged: (v) => setModalState(() => studentId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: location,
                      decoration: const InputDecoration(labelText: 'Lieu'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: videoPlatform,
                      decoration: const InputDecoration(labelText: 'Plateforme visio'),
                      items: const [
                        DropdownMenuItem(value: 'GOOGLE_MEET', child: Text('Google Meet')),
                        DropdownMenuItem(value: 'ZOOM', child: Text('Zoom')),
                        DropdownMenuItem(value: 'TEAMS', child: Text('Microsoft Teams')),
                        DropdownMenuItem(value: 'OTHER', child: Text('Autre')),
                      ],
                      onChanged: (v) => setModalState(() {
                        videoPlatform = v;
                        if (v == null || v == 'OTHER') {
                          autoGenerateVideoLink = false;
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Générer automatiquement le lien'),
                      value: autoGenerateVideoLink,
                      onChanged: (videoPlatform == null || videoPlatform == 'OTHER')
                          ? null
                          : (value) => setModalState(() => autoGenerateVideoLink = value),
                    ),
                    if (videoPlatform != null &&
                        videoPlatform != 'OTHER' &&
                        !autoGenerateVideoLink) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: videoLink,
                        decoration: const InputDecoration(labelText: 'Lien vidéo'),
                        keyboardType: TextInputType.url,
                      ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Publier la réunion'),
                      value: isPublished,
                      onChanged: (value) => setModalState(() => isPublished = value),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date et heure'),
                      subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(meetingDate)),
                      onTap: () async {
                        final date = await showDatePicker(context: ctx2, initialDate: meetingDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                        if (date != null) {
                          if (!ctx2.mounted) return;
                          final time = await showTimePicker(context: ctx2, initialTime: TimeOfDay.fromDateTime(meetingDate));
                          if (time != null) setModalState(() => meetingDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: durationMinutes,
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
                                  final payload = {
                                    'title': title.text.trim(),
                                    'description': description.text.trim(),
                                    'teacher': teacherId,
                                    'parent': parentId,
                                    'student': studentId,
                                    'meeting_type': meetingType,
                                    'meeting_date': meetingDate.toUtc().toIso8601String(),
                                    'duration_minutes': durationMinutes,
                                    'location': location.text.trim().isEmpty ? null : location.text.trim(),
                                    'video_platform': videoPlatform,
                                    'video_link': videoLink.text.trim().isEmpty ? null : videoLink.text.trim(),
                                    'auto_generate_video_link': autoGenerateVideoLink,
                                    'is_published': isPublished,
                                    'participant_ids': selectedTeacherIds,
                                    'parent_ids': selectedParentIds,
                                    'status': 'SCHEDULED',
                                  };
                                  if (isEditing) {
                                    await ApiService().patch(
                                      '/api/meetings/${existingMeeting['id']}/',
                                      data: payload,
                                    );
                                  } else {
                                    await ApiService().post('/api/meetings/', data: payload);
                                  }
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isEditing
                                              ? 'Réunion modifiée.'
                                              : 'Réunion créée.',
                                        ),
                                      ),
                                    );
                                    _loadMeetings();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')));
                                }
                              },
                              child: Text(isEditing ? 'Enregistrer' : 'Créer'),
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

  /// `teacher` peut être un PK (int) ou un objet avec `name` / `user`.
  String _participantLabel(dynamic participant, String fallbackPrefix) {
    if (participant == null) return 'N/A';
    if (participant is Map) {
      final name = participant['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name';
      final u = participant['user'];
      if (u is Map) {
        final n =
            '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
        if (n.isNotEmpty) return n;
      }
      final id = participant['id'];
      if (id != null) return '$fallbackPrefix #$id';
      return fallbackPrefix;
    }
    if (participant is int || participant is num) {
      return '$fallbackPrefix #$participant';
    }
    return fallbackPrefix;
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
    final path = GoRouterState.of(context).uri.path;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réunions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showMeetingForm(),
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
                      final date = _parseMeetingDate(meeting['meeting_date']);
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
                                  if (date != null) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.calendar_today, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(date)}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if ((meeting['location'] ?? '').toString().trim().isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.place_outlined, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Lieu: ${meeting['location']}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                  if (meeting['teacher'] != null) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.person, size: 16),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Avec: ${_participantLabel(meeting['teacher'], 'Enseignant')}',
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  // Lien visioconférence
                                  if (meeting['video_link'] != null) ...[
                                    ElevatedButton.icon(
                                      onPressed: () => _openMeetingLink(meeting['video_link']),
                                      icon: const Icon(Icons.video_call),
                                      label: const Text('Rejoindre la visioconférence'),
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 48),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  FilledButton.icon(
                                    onPressed: () => _showMeetingForm(existingMeeting: meeting),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('Modifier la réunion'),
                                  ),
                                  const SizedBox(height: 16),
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
      bottomNavigationBar: path.startsWith('/admin/')
          ? const AdminBottomNav()
          : path.startsWith('/discipline-officer/')
              ? const DisciplineOfficerBottomNav()
              : null,
    );
  }
}
