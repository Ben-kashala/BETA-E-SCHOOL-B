import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/payment_form_modal.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends ConsumerState<PaymentsPage> {
  List<dynamic> _payments = [];
  List<dynamic> _pendingPayments = [];
  List<dynamic> _filteredPayments = [];
  List<dynamic> _filteredPendingPayments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCurrency;
  int _selectedTab = 0;
  List<dynamic> _children = [];
  List<dynamic> _feeTypes = [];
  bool _isParent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      setState(() {
        _isParent = user?.isParent ?? false;
      });
      _loadPayments();
      if (_isParent) {
        _loadChildrenAndFeeTypes();
      }
    });
  }

  Future<void> _loadChildrenAndFeeTypes() async {
    try {
      final [childrenRes, feeTypesRes] = await Future.wait([
        ApiService().get('/api/auth/students/parent_dashboard/', useCache: false),
        ApiService().get('/api/payments/fee-types/', useCache: false),
      ]);
      setState(() {
        _children = childrenRes.data is List ? childrenRes.data : (childrenRes.data['results'] ?? []);
        _feeTypes = feeTypesRes.data is List ? feeTypesRes.data : (feeTypesRes.data['results'] ?? []);
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService();
      final response = await api.get<dynamic>('/api/payments/payments/', useCache: false);
      final data = response.data;
      final List<dynamic> allPayments = data is List
          ? data
          : (data is Map && data['results'] != null)
              ? (data['results'] as List)
              : [];
      final rawList = allPayments is List<dynamic> ? allPayments : List<dynamic>.from(allPayments);
      setState(() {
        _payments = rawList.where((p) => _statusEqual(p['status'], 'COMPLETED')).toList();
        _pendingPayments = rawList.where((p) => _statusEqual(p['status'], 'PENDING')).toList();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  bool _statusEqual(dynamic a, String b) =>
      a != null && (a.toString().toUpperCase() == b.toUpperCase());

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final cur = _selectedCurrency;
    setState(() {
      _filteredPayments = _payments.where((p) {
        final matchQuery = q.isEmpty ||
            (_paymentTitle(p).toLowerCase().contains(q)) ||
            (p['amount']?.toString().toLowerCase().contains(q) ?? false);
        final matchCur = cur == null || (p['currency']?.toString() == cur);
        return matchQuery && matchCur;
      }).toList();
      _filteredPendingPayments = _pendingPayments.where((p) {
        final matchQuery = q.isEmpty ||
            (_paymentTitle(p).toLowerCase().contains(q)) ||
            (p['amount']?.toString().toLowerCase().contains(q) ?? false);
        final matchCur = cur == null || (p['currency']?.toString() == cur);
        return matchQuery && matchCur;
      }).toList();
    });
  }

  Future<void> _processPayment(Map<String, dynamic> payment) async {
    // Ouvrir l'URL de paiement
    final paymentUrl = payment['payment_url'];
    if (paymentUrl != null && await canLaunchUrl(Uri.parse(paymentUrl))) {
      await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir le lien de paiement')),
        );
      }
    }
  }

  Future<void> _downloadReceipt(int paymentId, String paymentIdStr) async {
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
        '${api.baseUrl}/api/payments/payments/$paymentId/download_receipt/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
        ),
      );

      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/receipts');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final file = File('${downloadDir.path}/receipt_$paymentIdStr.pdf');
      await file.writeAsBytes(response.data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reçu téléchargé: ${file.path}')),
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

  String _paymentTitle(dynamic payment) {
    final fp = payment['fee_payments'];
    if (fp is List && fp.isNotEmpty) {
      final first = fp.first;
      if (first is Map && first['fee_type_name'] != null) return first['fee_type_name'].toString();
    }
    final ft = payment['fee_type'];
    if (ft is Map && ft['name'] != null) return ft['name'].toString();
    return payment['payment_id']?.toString() ?? 'Paiement';
  }

  Color _getStatusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'COMPLETED':
        return Colors.green;
      case 'PENDING':
      case 'PROCESSING':
        return Colors.orange;
      case 'FAILED':
      case 'CANCELLED':
      case 'REFUNDED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  void _openNewPaymentModal() {
    if (_children.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chargement des enfants en cours ou aucun enfant inscrit')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => PaymentFormModal(
        children: _children,
        feeTypes: _feeTypes,
        onSubmitted: () {
          Navigator.of(context).pop();
          _loadPayments();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Paiements'),
          actions: [
            if (_isParent)
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _openNewPaymentModal,
                tooltip: 'Nouveau paiement',
              ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'En attente'),
              Tab(text: 'Historique'),
            ],
            onTap: (index) {
              setState(() => _selectedTab = index);
              _applyFilters();
            },
          ),
        ),
        body: Column(
          children: [
            SearchFilterBar(
              hintText: 'Rechercher un paiement...',
              onSearchChanged: (value) {
                setState(() => _searchQuery = value);
                _applyFilters();
              },
              filters: [
                FilterOption(
                  key: 'currency',
                  label: 'Devise',
                  values: [
                    FilterValue(value: 'CDF', label: 'CDF'),
                    FilterValue(value: 'USD', label: 'USD'),
                  ],
                  selectedValue: _selectedCurrency,
                ),
              ],
              onFiltersChanged: (filters) {
                setState(() => _selectedCurrency = filters['currency']);
                _applyFilters();
              },
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        // Paiements en attente
                        _filteredPendingPayments.isEmpty
                            ? const Center(child: Text('Aucun paiement en attente'))
                            : RefreshIndicator(
                                onRefresh: _loadPayments,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredPendingPayments.length,
                                  itemBuilder: (context, index) {
                                    final payment = _filteredPendingPayments[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: CircleAvatar(
                                    backgroundColor: _getStatusColor(payment['status']),
                                    child: const Icon(Icons.payment, color: Colors.white),
                                  ),
                                  title: Text(_paymentTitle(payment)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Montant: ${payment['amount']} ${payment['currency'] ?? 'CDF'}'),
                                      if (payment['due_date'] != null)
                                        Text(
                                          'Échéance: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(payment['due_date'].toString()))}',
                                        ),
                                    ],
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () => _processPayment(payment),
                                    child: const Text('Payer'),
                                  ),
                                ),
                              );
                            },
                          ),
                                ),
                        // Historique des paiements
                        _filteredPayments.isEmpty
                            ? const Center(child: Text('Aucun paiement effectué'))
                            : RefreshIndicator(
                                onRefresh: _loadPayments,
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _filteredPayments.length,
                                  itemBuilder: (context, index) {
                                    final payment = _filteredPayments[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: CircleAvatar(
                                    backgroundColor: _getStatusColor(payment['status']),
                                    child: const Icon(Icons.check, color: Colors.white),
                                  ),
                                  title: Text(_paymentTitle(payment)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Montant: ${payment['amount']} ${payment['currency'] ?? 'CDF'}'),
                                      if (payment['payment_date'] != null)
                                        Text(
                                          'Payé le: ${DateFormat('dd/MM/yyyy').format(DateTime.parse(payment['payment_date'].toString()))}',
                                        ),
                                    ],
                                  ),
                                  trailing: payment['status'] == 'COMPLETED'
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.download),
                                              onPressed: () {
                                                _downloadReceipt(
                                                  payment['id'],
                                                  payment['payment_id']?.toString() ?? payment['id'].toString(),
                                                );
                                              },
                                              tooltip: 'Télécharger le reçu',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.receipt),
                                              onPressed: () {
                                                context.push('/payments/${payment['id']}/receipt');
                                              },
                                            ),
                                          ],
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
