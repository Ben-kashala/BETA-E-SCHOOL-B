import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/tutoring_message_form_modal.dart';

class ParentTutoringPage extends ConsumerStatefulWidget {
  const ParentTutoringPage({super.key});

  @override
  ConsumerState<ParentTutoringPage> createState() => _ParentTutoringPageState();
}

class _ParentTutoringPageState extends ConsumerState<ParentTutoringPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _messages = [];
  List<dynamic> _reports = [];
  List<dynamic> _children = [];
  bool _isLoading = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTab = _tabController.index);
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final [messagesRes, reportsRes, childrenRes] = await Future.wait([
        ApiService().get('/api/tutoring/messages/', useCache: false),
        ApiService().get('/api/tutoring/reports/', useCache: false),
        ApiService().get('/api/auth/students/parent_dashboard/', useCache: false),
      ]);

      setState(() {
        _messages = messagesRes.data is List 
            ? messagesRes.data 
            : (messagesRes.data['results'] ?? []);
        _reports = reportsRes.data is List 
            ? reportsRes.data 
            : (reportsRes.data['results'] ?? []);
        _children = childrenRes.data is List 
            ? childrenRes.data 
            : (childrenRes.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadReportPdf(String pdfUrl, String reportTitle) async {
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission de stockage requise')),
        );
        return;
      }

      final dio = Dio();
      final api = ApiService();
      final token = await api.getToken();
      
      final response = await dio.get(
        pdfUrl.startsWith('http') ? pdfUrl : '${api.baseUrl}$pdfUrl',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );

      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/tutoring');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final fileName = pdfUrl.split('/').last;
      final file = File('${downloadDir.path}/$fileName');
      await file.writeAsBytes(response.data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rapport téléchargé: ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du téléchargement: $e')),
        );
      }
    }
  }

  String _getChildName(dynamic child) {
    final identity = child['identity'] ?? child;
    final user = identity['user'] ?? {};
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    return '${firstName} ${lastName}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encadrement Domicile'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Messages', icon: Icon(Icons.message)),
            Tab(text: 'Rapports', icon: Icon(Icons.description)),
          ],
        ),
        actions: [
          if (_selectedTab == 0) // Messages tab
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                if (_children.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chargement des enfants en cours ou aucun enfant inscrit')),
                  );
                  return;
                }
                showDialog(
                  context: context,
                  builder: (context) => TutoringMessageFormModal(
                    children: _children,
                    onSubmitted: () {
                      Navigator.of(context).pop();
                      _loadData();
                    },
                  ),
                );
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Messages
                _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.message_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun message',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (_children.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Chargement des enfants en cours ou aucun enfant inscrit')),
                                  );
                                  return;
                                }
                                showDialog(
                                  context: context,
                                  builder: (context) => TutoringMessageFormModal(
                                    children: _children,
                                    onSubmitted: () {
                                      Navigator.of(context).pop();
                                      _loadData();
                                    },
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Envoyer un message'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.teal,
                                  child: Icon(Icons.message, color: Colors.white),
                                ),
                                title: Text(
                                  _getChildName(message['student'] ?? {}),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    Text(message['message'] ?? ''),
                                    const SizedBox(height: 8),
                                    if (message['created_at'] != null)
                                      Text(
                                        DateFormat('dd/MM/yyyy HH:mm').format(
                                          DateTime.parse(message['created_at']),
                                        ),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
                // Rapports
                _reports.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.description_outlined, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'Aucun rapport disponible',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: ExpansionTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Icon(Icons.description, color: Colors.white),
                                ),
                                title: Text(
                                  _getChildName(report['student'] ?? {}),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (report['subject'] != null)
                                      Text('Matière: ${report['subject']}'),
                                    if (report['created_at'] != null)
                                      Text(
                                        DateFormat('dd/MM/yyyy').format(
                                          DateTime.parse(report['created_at']),
                                        ),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (report['notes'] != null) ...[
                                          Text(
                                            'Notes',
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(report['notes']),
                                          const SizedBox(height: 16),
                                        ],
                                        if (report['parent_feedback'] != null) ...[
                                          Text(
                                            'Votre retour',
                                            style: Theme.of(context).textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(report['parent_feedback']),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            if (report['shared_at'] != null || report['created_at'] != null)
                                              Text(
                                                'Partagé le: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(report['shared_at'] ?? report['created_at']))}',
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                            if (report['report_pdf'] != null)
                                              ElevatedButton.icon(
                                                onPressed: () {
                                                  _downloadReportPdf(
                                                    report['report_pdf'],
                                                    'Rapport ${report['subject'] ?? ''}',
                                                  );
                                                },
                                                icon: const Icon(Icons.download),
                                                label: const Text('Télécharger PDF'),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
              ],
            ),
    );
  }
}
