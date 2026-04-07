import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/payment_form_modal.dart';

class PaymentsPage extends ConsumerStatefulWidget {
  const PaymentsPage({super.key});

  @override
  ConsumerState<PaymentsPage> createState() => _PaymentsPageState();
}

/// Méthodes prises en charge par l’API `initiate-mobile` (Airtel, Orange, M-Pesa).
const _kMobileMoneyApiMethods = {
  'MOBILE_MONEY_ORANGE',
  'MOBILE_MONEY_MPESA',
  'MOBILE_MONEY_AIRTEL',
};

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
        _pendingPayments = rawList.where((p) {
          final s = p['status']?.toString().toUpperCase() ?? '';
          return s == 'PENDING' || s == 'PROCESSING';
        }).toList();
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
    final id = _parsePaymentId(payment['id']);
    if (id == null) return;

    final method = payment['payment_method']?.toString() ?? '';
    final status = payment['status']?.toString().toUpperCase() ?? '';

    if (_kMobileMoneyApiMethods.contains(method) &&
        (status == 'PENDING' || status == 'PROCESSING')) {
      await _mobileMoneyOperatorFlow(payment, id, method, status);
      return;
    }

    final paymentUrl = payment['payment_url']?.toString();
    if (paymentUrl != null && paymentUrl.isNotEmpty) {
      final uri = Uri.tryParse(paymentUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!mounted) return;
    final msg = method == 'ONLINE'
        ? 'Lien de paiement indisponible. Réessayez plus tard ou contactez l’école.'
        : 'Ce paiement ne dispose pas de lien en ligne. Pour ${method.isEmpty ? "ce mode" : method}, rapprochez-vous de l’école ou choisissez Orange Money, M-Pesa ou Airtel Money si proposé.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _mobileMoneyOperatorFlow(
    Map<String, dynamic> payment,
    int paymentId,
    String paymentMethod,
    String status,
  ) async {
    if (status == 'PROCESSING') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmer le paiement'),
          content: const Text(
            'Si vous avez validé le paiement sur votre téléphone (USSD / application opérateur), '
            'vous pouvez enregistrer le reçu côté école.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ApiService().post<dynamic>(
                    '/api/payments/payments/$paymentId/confirm-mobile/',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Paiement enregistré')),
                    );
                    _loadPayments();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ApiService.parseDioError(e))),
                    );
                  }
                }
              },
              child: const Text('J’ai payé sur le téléphone'),
            ),
          ],
        ),
      );
      return;
    }

    final phoneController = TextEditingController(
      text: payment['payer_phone']?.toString() ?? '',
    );

    if (!mounted) return;
    var initiateBusy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Paiement Mobile Money'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Numéro utilisé pour payer (${_methodLabel(paymentMethod)}).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone du payeur',
                      hintText: '+243…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: initiateBusy ? null : () => Navigator.pop(ctx),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: initiateBusy
                    ? null
                    : () async {
                        final phone = phoneController.text.trim();
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Indiquez le numéro de téléphone'),
                            ),
                          );
                          return;
                        }
                        setLocal(() => initiateBusy = true);
                        try {
                          final res = await ApiService().post<Map<String, dynamic>>(
                            '/api/payments/payments/initiate-mobile/',
                            data: {
                              'payment_id': paymentId,
                              'phone_number': phone,
                              'payment_method': paymentMethod,
                            },
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          final apiMsg = res.data?['message']?.toString() ??
                              'Demande envoyée. Validez sur votre téléphone.';
                          if (mounted) {
                            await showDialog<void>(
                              context: this.context,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Étape suivante'),
                                content: Text(apiMsg),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx),
                                    child: const Text('Fermer'),
                                  ),
                                  FilledButton(
                                    onPressed: () async {
                                      Navigator.pop(dctx);
                                      try {
                                        await ApiService().post<dynamic>(
                                          '/api/payments/payments/$paymentId/confirm-mobile/',
                                        );
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Paiement enregistré'),
                                            ),
                                          );
                                          _loadPayments();
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(this.context).showSnackBar(
                                            SnackBar(content: Text(ApiService.parseDioError(e))),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('J’ai payé sur le téléphone'),
                                  ),
                                ],
                              ),
                            );
                            _loadPayments();
                          }
                        } catch (e) {
                          setLocal(() => initiateBusy = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(ApiService.parseDioError(e))),
                            );
                          }
                        }
                      },
                child: initiateBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Envoyer la demande'),
              ),
            ],
          );
        },
      ),
    );

    phoneController.dispose();
  }

  String _methodLabel(String code) {
    const labels = {
      'MOBILE_MONEY_ORANGE': 'Orange Money',
      'MOBILE_MONEY_MPESA': 'M-Pesa',
      'MOBILE_MONEY_AIRTEL': 'Airtel Money',
    };
    return labels[code] ?? code;
  }

  int? _parsePaymentId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<void> _downloadReceipt(int paymentId, String paymentIdStr) async {
    try {
      final api = ApiService();
      final headers = await api.getAuthHeaders();
      if (headers['Authorization'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session expirée. Reconnectez-vous.')),
          );
        }
        return;
      }

      final bytes = await api.downloadAuthenticatedBinary(
        '/api/payments/payments/$paymentId/download_receipt/',
      );

      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads/receipts');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      final safe = paymentIdStr.replaceAll(RegExp(r'[^\w\-\.]'), '_');
      final file = File('${downloadDir.path}/receipt_$safe.pdf');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reçu téléchargé')),
        );
      }
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        final msg = e is Exception
            ? e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')
            : ApiService.parseDioError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Téléchargement impossible : $msg')),
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
              TextButton(
                onPressed: _openNewPaymentModal,
                child: const Text('Payer'),
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
                                  padding: ScrollContentPadding.page(context),
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
                                    child: Text(
                                      _statusEqual(payment['status'], 'PROCESSING')
                                          ? 'Confirmer'
                                          : 'Payer',
                                    ),
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
                                  padding: ScrollContentPadding.page(context),
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
                                  trailing: _statusEqual(payment['status'], 'COMPLETED')
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.download),
                                              onPressed: () {
                                                final pid = _parsePaymentId(payment['id']);
                                                if (pid == null) return;
                                                _downloadReceipt(
                                                  pid,
                                                  payment['payment_id']?.toString() ??
                                                      payment['id'].toString(),
                                                );
                                              },
                                              tooltip: 'Télécharger le reçu',
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.receipt),
                                              tooltip: 'Détail du reçu',
                                              onPressed: () {
                                                final pid = _parsePaymentId(payment['id']);
                                                if (pid == null) return;
                                                context.push('/payments/$pid/receipt');
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
