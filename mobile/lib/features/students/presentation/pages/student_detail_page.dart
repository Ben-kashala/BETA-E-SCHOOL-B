import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/network/api_service.dart';

class StudentDetailPage extends ConsumerStatefulWidget {
  final int studentId;

  const StudentDetailPage({super.key, required this.studentId});

  @override
  ConsumerState<StudentDetailPage> createState() => _StudentDetailPageState();
}

class _StudentDetailPageState extends ConsumerState<StudentDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _studentData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Ne pas appeler setState pendant initState : démarrer le chargement après le premier frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadStudentDetail();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentDetail() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get<dynamic>(
        '/api/accounts/students/${widget.studentId}/full_detail/',
        useCache: false,
      );
      if (!mounted) return;
      final data = response.data;
      if (data is Map) {
        setState(() {
          _studentData = Map<String, dynamic>.from(data);
          _isLoading = false;
        });
      } else {
        setState(() {
          _studentData = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _studentData = null;
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadBulletin(int schoolClassId, String academicYear) async {
    try {
      final api = ApiService();
      final baseUrl = api.baseUrl;
      final url = '$baseUrl/api/accounts/students/${widget.studentId}/bulletin_pdf/?school_class=$schoolClassId&academic_year=${Uri.encodeComponent(academicYear)}';
      
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fiche élève')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_studentData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fiche élève')),
        body: const Center(child: Text('Élève non trouvé')),
      );
    }

    final identity = _studentData!['identity'] is Map
        ? Map<String, dynamic>.from(_studentData!['identity'] as Map)
        : <String, dynamic>{};
    final user = identity['user'] is Map
        ? Map<String, dynamic>.from(identity['user'] as Map)
        : <String, dynamic>{};
    final classEnrollments =
        (_studentData!['class_enrollments'] as List<dynamic>?) ?? <dynamic>[];
    final gradeBulletins =
        (_studentData!['grade_bulletins'] as List<dynamic>?) ?? <dynamic>[];
    final reportCards =
        (_studentData!['report_cards'] as List<dynamic>?) ?? <dynamic>[];
    final payments =
        (_studentData!['payments'] as List<dynamic>?) ?? <dynamic>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          identity['student_id']?.toString() ?? 'Fiche élève',
          overflow: TextOverflow.ellipsis,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Identité', icon: Icon(Icons.person)),
            Tab(text: 'Parcours', icon: Icon(Icons.school)),
            Tab(text: 'Paiements', icon: Icon(Icons.payment)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Onglet Identité
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 32),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('Matricule', identity['student_id']?.toString() ?? '-'),
                    _buildInfoRow(
                      'Nom complet',
                      _stringOr(
                        identity['user_name'],
                        '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim(),
                      ),
                    ),
                    if (user['date_of_birth'] != null)
                      _buildInfoRow(
                        'Date de naissance',
                        _formatDateSafe(user['date_of_birth']) ?? '—',
                      ),
                    _buildInfoRow('Email', user['email'] ?? '-'),
                    _buildInfoRow('Téléphone', user['phone'] ?? '-'),
                    _buildInfoRow('Adresse', user['address'] ?? '-'),
                    _buildInfoRow('Classe actuelle', identity['class_name'] ?? identity['school_class']?['name'] ?? '-'),
                    _buildInfoRow('Année scolaire', identity['academic_year'] ?? '-'),
                    _buildInfoRow('Parent / Tuteur', identity['parent_name'] ?? '-'),
                    if (identity['enrollment_date'] != null)
                      _buildInfoRow(
                        'Date d\'inscription',
                        _formatDateSafe(identity['enrollment_date']) ?? '—',
                      ),
                    _buildInfoRow('Ancien élève', identity['is_former_student'] == true ? 'Oui' : 'Non'),
                    if (identity['is_former_student'] == true && identity['graduation_year'] != null)
                      _buildInfoRow('Année de sortie', identity['graduation_year'].toString()),
                    if (identity['blood_group'] != null || identity['allergies'] != null)
                      _buildInfoRow('Groupe sanguin / Allergies', '${identity['blood_group'] ?? ''} ${identity['allergies'] ?? ''}'.trim()),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Onglet Parcours
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Inscriptions par classe
                if (classEnrollments.isNotEmpty) ...[
                  Text(
                    'Inscriptions par classe',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: classEnrollments.length,
                      itemBuilder: (context, index) {
                        final raw = classEnrollments[index];
                        final enrollment = raw is Map<String, dynamic>
                            ? raw
                            : Map<String, dynamic>.from(raw as Map);
                        final classLabel = enrollment['school_class_name'] ??
                            enrollment['class_name'] ??
                            'Classe';
                        final scId = enrollment['school_class'];
                        final year = enrollment['academic_year']?.toString();
                        return ListTile(
                          title: Text(classLabel.toString()),
                          subtitle: Text('Année: ${year ?? '-'}'),
                          trailing: scId != null && year != null && year.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.download),
                                  onPressed: () {
                                    final id = scId is int
                                        ? scId
                                        : (scId is num
                                            ? scId.toInt()
                                            : int.tryParse(scId.toString()));
                                    if (id != null) {
                                      _downloadBulletin(id, year);
                                    }
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                // Notes (bulletin RDC)
                if (gradeBulletins.isNotEmpty) ...[
                  Text(
                    'Notes (bulletin RDC)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Matière')),
                          DataColumn(label: Text('Année')),
                          DataColumn(label: Text('S1'), numeric: true),
                          DataColumn(label: Text('S2'), numeric: true),
                          DataColumn(label: Text('T.G.'), numeric: true),
                        ],
                        rows: gradeBulletins.map<DataRow>((dynamic raw) {
                          final b = raw is Map<String, dynamic>
                              ? raw
                              : Map<String, dynamic>.from(raw as Map);
                          return DataRow(
                            cells: [
                              DataCell(Text(b['subject_name']?.toString() ?? '-')),
                              DataCell(Text(b['academic_year']?.toString() ?? '-')),
                              DataCell(Text(_formatScore(b['total_s1']))),
                              DataCell(Text(_formatScore(b['total_s2']))),
                              DataCell(Text(_formatScore(b['total_general']))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                // Bulletins (décision)
                if (reportCards.isNotEmpty) ...[
                  Text(
                    'Bulletins (décision)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...reportCards.map<Widget>((dynamic raw) {
                    final card = raw is Map<String, dynamic>
                        ? raw
                        : Map<String, dynamic>.from(raw as Map);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          '${card['academic_year'] ?? ''} — ${card['class_name'] ?? card['school_class_name'] ?? ''}',
                        ),
                        subtitle: Text('Décision: ${card['decision'] ?? '-'}'),
                        trailing: card['school_class'] != null &&
                                card['academic_year'] != null
                            ? IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () {
                                  _downloadBulletin(
                                    card['school_class'],
                                    card['academic_year'].toString(),
                                  );
                                },
                              )
                            : null,
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          // Onglet Paiements
          payments.isEmpty
              ? const Center(child: Text('Aucun paiement'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: payments.length,
                  itemBuilder: (context, index) {
                    final raw = payments[index];
                    final payment = raw is Map<String, dynamic>
                        ? raw
                        : Map<String, dynamic>.from(raw as Map);
                    final payDate = payment['payment_date'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text('${payment['amount']} ${payment['currency'] ?? 'CDF'}'),
                        subtitle: Text(
                          payDate != null
                              ? (_formatDateSafe(payDate) ?? payDate.toString())
                              : '-',
                        ),
                        trailing: Text(payment['status']?.toString() ?? '-'),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  String _stringOr(dynamic primary, String fallback) {
    final p = primary?.toString().trim();
    if (p != null && p.isNotEmpty) return p;
    final f = fallback.trim();
    return f.isEmpty ? '—' : f;
  }

  /// Dates ISO ou formats courants ; évite une exception pendant le build.
  String? _formatDateSafe(dynamic v) {
    if (v == null) return null;
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(v.toString()));
    } catch (_) {
      return null;
    }
  }

  /// Formate une note (l'API peut renvoyer num, String ou autre).
  String _formatScore(dynamic v) {
    if (v == null) return '-';

    // Toujours passer par num.tryParse pour éviter d'appeler toStringAsFixed sur une String.
    num? parsed;
    if (v is num) {
      parsed = v;
    } else {
      parsed = num.tryParse(v.toString());
    }

    if (parsed == null) {
      return v.toString();
    }

    return parsed.toStringAsFixed(1);
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 5)),
        ],
      ),
    );
  }
}
