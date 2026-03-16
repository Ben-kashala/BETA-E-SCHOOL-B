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
    _loadStudentDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentDetail() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/accounts/students/${widget.studentId}/full_detail/');
      setState(() {
        _studentData = response.data as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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

    final identity = _studentData!['identity'] ?? {};
    final user = identity['user'] ?? {};
    final classEnrollments = _studentData!['class_enrollments'] ?? [];
    final gradeBulletins = _studentData!['grade_bulletins'] ?? [];
    final reportCards = _studentData!['report_cards'] ?? [];
    final payments = _studentData!['payments'] ?? [];

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
                    _buildInfoRow('Nom complet', identity['user_name'] ?? '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim()),
                    if (user['date_of_birth'] != null)
                      _buildInfoRow('Date de naissance', DateFormat('dd/MM/yyyy').format(DateTime.parse(user['date_of_birth']))),
                    _buildInfoRow('Email', user['email'] ?? '-'),
                    _buildInfoRow('Téléphone', user['phone'] ?? '-'),
                    _buildInfoRow('Adresse', user['address'] ?? '-'),
                    _buildInfoRow('Classe actuelle', identity['class_name'] ?? identity['school_class']?['name'] ?? '-'),
                    _buildInfoRow('Année scolaire', identity['academic_year'] ?? '-'),
                    _buildInfoRow('Parent / Tuteur', identity['parent_name'] ?? '-'),
                    if (identity['enrollment_date'] != null)
                      _buildInfoRow('Date d\'inscription', DateFormat('dd/MM/yyyy').format(DateTime.parse(identity['enrollment_date']))),
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
                        final enrollment = classEnrollments[index];
                        return ListTile(
                          title: Text(enrollment['class_name'] ?? 'Classe'),
                          subtitle: Text('Année: ${enrollment['academic_year'] ?? '-'}'),
                          trailing: enrollment['school_class'] != null && enrollment['academic_year'] != null
                              ? IconButton(
                                  icon: const Icon(Icons.download),
                                  onPressed: () {
                                    _downloadBulletin(
                                      enrollment['school_class'],
                                      enrollment['academic_year'],
                                    );
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
                        rows: gradeBulletins.map((b) {
                          return DataRow(
                            cells: [
                              DataCell(Text(b['subject_name'] ?? '-')),
                              DataCell(Text(b['academic_year'] ?? '-')),
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
                  ...reportCards.map((card) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${card['academic_year'] ?? ''} - ${card['class_name'] ?? ''}'),
                        subtitle: Text('Décision: ${card['decision'] ?? '-'}'),
                        trailing: card['school_class'] != null && card['academic_year'] != null
                            ? IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () {
                                  _downloadBulletin(
                                    card['school_class'],
                                    card['academic_year'],
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
                    final payment = payments[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text('${payment['amount']} ${payment['currency'] ?? 'CDF'}'),
                        subtitle: Text(
                          payment['payment_date'] != null
                              ? DateFormat('dd/MM/yyyy').format(DateTime.parse(payment['payment_date']))
                              : '-',
                        ),
                        trailing: Text(payment['status'] ?? '-'),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
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
