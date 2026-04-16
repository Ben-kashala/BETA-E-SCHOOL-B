import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/layout/scroll_content_padding.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/search_filter_bar.dart';
import '../widgets/admin_bottom_nav.dart';

class AdminPaymentsPage extends ConsumerStatefulWidget {
  const AdminPaymentsPage({super.key});

  @override
  ConsumerState<AdminPaymentsPage> createState() => _AdminPaymentsPageState();
}

class _AdminPaymentsPageState extends ConsumerState<AdminPaymentsPage> {
  List<dynamic> _payments = [];
  List<dynamic> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCurrency;
  String _sortBy = 'date_desc';
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _isLoading = true);
    try {
      final response =
          await ApiService().get<dynamic>('/api/payments/payments/', useCache: false);
      final data = response.data;
      final list = data is List
          ? data
          : (data is Map && data['results'] is List)
              ? data['results'] as List
              : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _payments = List<dynamic>.from(list);
        _isLoading = false;
      });
      _applyFilters();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final currency = _selectedCurrency;
    final filtered = _payments.where((payment) {
        final title = _paymentTitle(payment).toLowerCase();
        final userName = (payment['user_name'] ?? '').toString().toLowerCase();
        final amount = (payment['amount'] ?? '').toString().toLowerCase();
        final paymentId = (payment['payment_id'] ?? '').toString().toLowerCase();
        final matchesQuery = q.isEmpty ||
            title.contains(q) ||
            userName.contains(q) ||
            amount.contains(q) ||
            paymentId.contains(q);
        final matchesCurrency =
            currency == null || payment['currency']?.toString() == currency;
        return matchesQuery && matchesCurrency;
      }).toList();

    filtered.sort((a, b) {
      switch (_sortBy) {
        case 'amount_asc':
          return _amountValue(a).compareTo(_amountValue(b));
        case 'amount_desc':
          return _amountValue(b).compareTo(_amountValue(a));
        case 'status':
          return _statusRank(a['status']).compareTo(_statusRank(b['status']));
        case 'date_asc':
          return _dateValue(a).compareTo(_dateValue(b));
        case 'date_desc':
        default:
          return _dateValue(b).compareTo(_dateValue(a));
      }
    });

    setState(() {
      _filtered = filtered;
    });
  }

  String _paymentTitle(dynamic payment) {
    final fp = payment['fee_payments'];
    if (fp is List && fp.isNotEmpty) {
      final first = fp.first;
      if (first is Map && first['fee_type_name'] != null) {
        return first['fee_type_name'].toString();
      }
    }
    final ft = payment['fee_type'];
    if (ft is Map && ft['name'] != null) return ft['name'].toString();
    return payment['payment_id']?.toString() ?? 'Paiement';
  }

  int? _parsePaymentId(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _dateStr(dynamic payment) {
    try {
      final raw = payment['payment_date'] ?? payment['created_at'];
      if (raw == null) return '—';
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return '—';
    }
  }

  DateTime _dateValue(dynamic payment) {
    try {
      final raw = payment['payment_date'] ?? payment['created_at'];
      if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.parse(raw.toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  double _amountValue(dynamic payment) {
    final raw = payment['amount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('$raw') ?? 0;
  }

  int _statusRank(dynamic status) {
    switch ('${status ?? ''}'.toUpperCase()) {
      case 'PENDING':
        return 0;
      case 'PROCESSING':
        return 1;
      case 'COMPLETED':
        return 2;
      case 'FAILED':
      case 'REJECTED':
      case 'CANCELLED':
        return 3;
      default:
        return 4;
    }
  }

  String _methodLabel(dynamic payment) {
    const labels = {
      'CASH': 'Espèces',
      'MOBILE_MONEY': 'Mobile Money',
      'MOBILE_MONEY_MPESA': 'M-Pesa',
      'MOBILE_MONEY_ORANGE': 'Orange Money',
      'MOBILE_MONEY_AIRTEL': 'Airtel Money',
      'BANK_TRANSFER': 'Virement',
      'CARD': 'Carte',
      'ONLINE': 'Paiement en ligne',
    };
    final code = '${payment['payment_method'] ?? ''}';
    return labels[code] ?? (code.isEmpty ? '—' : code);
  }

  Color _statusColor(String? status) {
    switch (status?.toUpperCase()) {
      case 'COMPLETED':
        return Colors.green;
      case 'PENDING':
        return Colors.orange;
      case 'PROCESSING':
        return Colors.blue;
      case 'FAILED':
      case 'REJECTED':
      case 'CANCELLED':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        status.isEmpty ? '—' : status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _actionsRow(int? id, String status, bool busy, String paymentIdStr) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (status == 'PENDING' && id != null) ...[
          OutlinedButton.icon(
            onPressed: busy ? null : () => _reject(id),
            icon: const Icon(Icons.close),
            label: const Text('Rejeter'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: busy ? null : () => _validate(id),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Valider'),
          ),
        ],
        if (status == 'COMPLETED' && id != null)
          TextButton.icon(
            onPressed: () => _downloadReceipt(id, paymentIdStr),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Reçu'),
          ),
      ],
    );
  }

  Widget _sortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              'Trier par',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            DropdownButton<String>(
              value: _sortBy,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                  value: 'date_desc',
                  child: Text('Date décroissante'),
                ),
                DropdownMenuItem(
                  value: 'date_asc',
                  child: Text('Date croissante'),
                ),
                DropdownMenuItem(
                  value: 'amount_desc',
                  child: Text('Montant décroissant'),
                ),
                DropdownMenuItem(
                  value: 'amount_asc',
                  child: Text('Montant croissant'),
                ),
                DropdownMenuItem(
                  value: 'status',
                  child: Text('Statut'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _sortBy = value;
                _applyFilters();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileCard(dynamic payment) {
    final id = _parsePaymentId(payment['id']);
    final status = '${payment['status'] ?? ''}'.toUpperCase();
    final busy = id != null && _busyIds.contains(id);
    final paymentIdStr =
        payment['payment_id']?.toString() ?? '${payment['id']}';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: _statusColor(status),
                  child: const Icon(Icons.payment, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _paymentTitle(payment),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text('ID: $paymentIdStr'),
                      Text('Utilisateur: ${payment['user_name'] ?? '—'}'),
                      Text(
                        'Montant: ${payment['amount'] ?? '0'} ${payment['currency'] ?? 'CDF'}',
                      ),
                      Text('Méthode: ${_methodLabel(payment)}'),
                      Text('Date: ${_dateStr(payment)}'),
                    ],
                  ),
                ),
                _statusBadge(status),
              ],
            ),
            const SizedBox(height: 12),
            _actionsRow(id, status, busy, paymentIdStr),
          ],
        ),
      ),
    );
  }

  Widget _tableView() {
    return SingleChildScrollView(
      padding: ScrollContentPadding.page(context),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('Utilisateur')),
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Montant')),
            DataColumn(label: Text('Méthode')),
            DataColumn(label: Text('Statut')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _filtered.map((payment) {
            final id = _parsePaymentId(payment['id']);
            final status = '${payment['status'] ?? ''}'.toUpperCase();
            final busy = id != null && _busyIds.contains(id);
            final paymentIdStr =
                payment['payment_id']?.toString() ?? '${payment['id']}';
            return DataRow(
              cells: [
                DataCell(Text(paymentIdStr)),
                DataCell(SizedBox(
                  width: 150,
                  child: Text(
                    '${payment['user_name'] ?? '—'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(SizedBox(
                  width: 140,
                  child: Text(
                    _paymentTitle(payment),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(Text(
                  '${payment['amount'] ?? '0'} ${payment['currency'] ?? 'CDF'}',
                )),
                DataCell(SizedBox(
                  width: 120,
                  child: Text(
                    _methodLabel(payment),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                DataCell(_statusBadge(status)),
                DataCell(Text(_dateStr(payment))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 180),
                    child: _actionsRow(id, status, busy, paymentIdStr),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _validate(int id) async {
    setState(() => _busyIds.add(id));
    try {
      await ApiService().post('/api/payments/payments/$id/validate/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement validé avec succès')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.parseDioError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _reject(int id) async {
    setState(() => _busyIds.add(id));
    try {
      await ApiService().post('/api/payments/payments/$id/reject/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paiement rejeté')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.parseDioError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _downloadReceipt(int paymentId, String paymentIdStr) async {
    try {
      final bytes = await ApiService().downloadAuthenticatedBinary(
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Téléchargement impossible : ${ApiService.parseDioError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des Paiements'),
      ),
      body: Column(
        children: [
          SearchFilterBar(
            hintText: 'Rechercher un paiement...',
            onSearchChanged: (value) {
              _searchQuery = value;
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
              _selectedCurrency = filters['currency'];
              _applyFilters();
            },
          ),
          _sortBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('Aucun paiement trouvé'))
                    : RefreshIndicator(
                        onRefresh: _loadPayments,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 900) {
                              return _tableView();
                            }
                            return ListView.builder(
                              padding: ScrollContentPadding.page(context),
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) =>
                                  _mobileCard(_filtered[index]),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: const AdminBottomNav(),
    );
  }
}

