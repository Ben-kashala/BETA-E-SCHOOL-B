import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/network/api_service.dart';

class PaymentReceiptPage extends ConsumerStatefulWidget {
  final int paymentId;

  const PaymentReceiptPage({super.key, required this.paymentId});

  @override
  ConsumerState<PaymentReceiptPage> createState() => _PaymentReceiptPageState();
}

class _PaymentReceiptPageState extends ConsumerState<PaymentReceiptPage> {
  Map<String, dynamic>? _payment;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPayment();
  }

  Future<void> _loadPayment() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get<dynamic>(
        '/api/payments/payments/${widget.paymentId}/',
        useCache: false,
      );
      final data = response.data;
      if (data is Map) {
        setState(() {
          _payment = Map<String, dynamic>.from(data);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  bool _isCompleted(Map<String, dynamic> p) {
    final s = p['status']?.toString().toUpperCase();
    return s == 'COMPLETED';
  }

  String _paymentTitle(Map<String, dynamic> payment) {
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

  /// Chaîne API non vide (évite d'afficher « null »).
  String? _trimmed(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  Future<void> _downloadReceipt() async {
    if (_payment == null || !_isCompleted(_payment!)) return;

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

      final paymentId = _payment!['id'];
      final pid = paymentId is int
          ? paymentId
          : (paymentId is num ? paymentId.toInt() : int.tryParse(paymentId.toString()));
      if (pid == null) return;

      final paymentIdStr =
          _payment!['payment_id']?.toString() ?? paymentId.toString();

      final bytes = await api.downloadAuthenticatedBinary(
        '/api/payments/payments/$pid/download_receipt/',
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


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reçu de paiement')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_payment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reçu de paiement')),
        body: const Center(child: Text('Reçu non trouvé')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reçu de paiement'),
        actions: [
          if (_isCompleted(_payment!))
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Télécharger le PDF',
              onPressed: _downloadReceipt,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long, size: 64, color: Colors.green),
                      const SizedBox(height: 16),
                      Text(
                        'REÇU DE PAIEMENT',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Payeur et élève',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'Parent / payeur',
                  _trimmed(_payment!['user_name']) ?? '—',
                ),
                _buildInfoRow(
                  'Élève concerné',
                  _trimmed(_payment!['student_name']) ?? '—',
                ),
                if (_trimmed(_payment!['school_name']) != null)
                  _buildInfoRow('Établissement', _payment!['school_name']),
                if (_trimmed(_payment!['payer_phone']) != null)
                  _buildInfoRow('Téléphone payeur', _payment!['payer_phone']),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildInfoRow('Libellé', _paymentTitle(_payment!)),
                _buildInfoRow('ID Paiement', _payment!['payment_id'] ?? 'N/A'),
                _buildInfoRow('Montant', '${_payment!['amount']} ${_payment!['currency'] ?? 'CDF'}'),
                if (_payment!['payment_date'] != null)
                  _buildInfoRow(
                    'Date de paiement',
                    DateFormat('dd/MM/yyyy HH:mm').format(
                      DateTime.parse(_payment!['payment_date'].toString()),
                    ),
                  ),
                if (_payment!['payment_method'] != null)
                  _buildInfoRow('Méthode', _payment!['payment_method']?.toString()),
                const Divider(),
                const SizedBox(height: 16),
                // Type de frais
                if (_payment!['fee_type'] != null) ...[
                  const Text(
                    'Type de frais',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Nom', _payment!['fee_type']['name'] ?? 'N/A'),
                ],
                const SizedBox(height: 16),
                if (_isCompleted(_payment!)) ...[
                  const Divider(),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: _downloadReceipt,
                      icon: const Icon(Icons.download),
                      label: const Text('Télécharger le reçu (PDF)'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    final text = value?.toString() ?? '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(text, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
