import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../layout/accountant_responsive.dart';
import '../widgets/accountant_bottom_nav.dart';
import '../widgets/accountant_payment_form_sheet.dart';

/// Fond type dashboard web (sidebar / panneau principal).
const Color _kWebBg = Color(0xFF1a223f);
const Color _kWebPanel = Color(0xFF252d4a);
const Color _kWebHeaderRow = Color(0xFF353f5c);
const Color _kWebTextMuted = Color(0xFFB0B8D4);

/// Gestion des paiements — alignée visuellement sur le web (`accountant/Payments.tsx`).
class AccountantPaymentsPage extends ConsumerStatefulWidget {
  const AccountantPaymentsPage({super.key});

  @override
  ConsumerState<AccountantPaymentsPage> createState() => _AccountantPaymentsPageState();
}

class _AccountantPaymentsPageState extends ConsumerState<AccountantPaymentsPage> {
  List<dynamic> _payments = [];
  List<dynamic> _summaryByFeeType = [];
  bool _loading = true;
  final Set<int> _actionBusy = {};

  static const _methodLabels = {
    'CASH': 'Espèces',
    'MOBILE_MONEY': 'Mobile Money',
    'MOBILE_MONEY_MPESA': 'M-Pesa',
    'MOBILE_MONEY_ORANGE': 'Orange Money',
    'MOBILE_MONEY_AIRTEL': 'Airtel Money',
    'BANK_TRANSFER': 'Virement bancaire',
    'CARD': 'Carte bancaire',
    'ONLINE': 'Paiement en ligne',
  };

  static String _fmt(num n) => NumberFormat('#,##0.00', 'fr_FR').format(n);

  List<dynamic> _list(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/api/payments/payments/', useCache: false),
        ApiService().get('/api/payments/payments/summary-by-fee-type/', useCache: false),
      ]);
      final pay = _list(results[0].data);
      final sum = results[1].data is List ? results[1].data as List : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _payments = pay;
        _summaryByFeeType = sum;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _validate(int id) async {
    setState(() => _actionBusy.add(id));
    try {
      await ApiService().post('/api/payments/payments/$id/validate/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement validé avec succès')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy.remove(id));
    }
  }

  Future<void> _reject(int id) async {
    setState(() => _actionBusy.add(id));
    try {
      await ApiService().post('/api/payments/payments/$id/reject/');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement rejeté')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _actionBusy.remove(id));
    }
  }

  Future<void> _downloadReceipt(int id, String paymentIdStr) async {
    try {
      final bytes = await ApiService().downloadAuthenticatedBinary(
        '/api/payments/payments/$id/download_receipt/',
      );
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDir.path}/downloads/receipts');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safe = paymentIdStr.replaceAll(RegExp(r'[^\w\-\.]'), '_');
      final file = File('${dir.path}/receipt_$safe.pdf');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reçu téléchargé')),
        );
      }
      await OpenFilex.open(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : ${ApiService.parseDioError(e)}')),
        );
      }
    }
  }

  TextStyle _headerStyleFor(BuildContext context) => TextStyle(
        fontSize: AccountantResponsive.isCompact(context) ? 10 : 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: _kWebTextMuted,
      );

  double _tableFontSize(BuildContext context) =>
      AccountantResponsive.isCompact(context) ? 11 : 12;

  Widget _statusBadge(String status) {
    final u = status.toUpperCase();
    late Color accent;
    switch (u) {
      case 'COMPLETED':
        accent = const Color(0xFF4CAF50);
        break;
      case 'PENDING':
      case 'PROCESSING':
        accent = const Color(0xFFFFC107);
        break;
      case 'FAILED':
        accent = Colors.redAccent;
        break;
      default:
        accent = Colors.blueGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent, width: 1.5),
        color: accent.withValues(alpha: 0.12),
      ),
      child: Text(
        u,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  String _dateStr(dynamic p) {
    final status = '${p['status'] ?? ''}'.toUpperCase();
    if (status == 'PENDING' || status == 'PROCESSING') return '—';
    try {
      if (p['payment_date'] != null) {
        final date = DateTime.parse(p['payment_date'].toString());
        return DateFormat('d MMM yyyy', 'fr_FR').format(date);
      }
    } catch (_) {}
    return '—';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _kWebBg,
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: _kWebBg,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: AccountantResponsive.appBarTitleFontSize(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: _kWebPanel,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      child: Scaffold(
        backgroundColor: _kWebBg,
        appBar: AppBar(
          title: Text(
            'Gestion des Paiements',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AccountantResponsive.appBarTitleFontSize(context)),
          ),
          actions: [
            if (AccountantResponsive.widthOf(context) < 360)
              IconButton(
                tooltip: 'Payer',
                onPressed: _loading
                    ? null
                    : () => showAccountantPaymentFormSheet(
                          context,
                          onSuccess: _load,
                        ),
                icon: const Icon(Icons.add_circle_outline),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.moduleButtonColor,
                    foregroundColor: AppTheme.onAvatarBackgroundColor,
                    padding: EdgeInsets.symmetric(
                      horizontal: AccountantResponsive.isCompact(context) ? 8 : 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _loading
                      ? null
                      : () => showAccountantPaymentFormSheet(
                            context,
                            onSuccess: _load,
                          ),
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(
                    AccountantResponsive.widthOf(context) < 420 ? 'Payer' : 'Effectuer un paiement',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white70))
            : RefreshIndicator(
                color: AppTheme.moduleButtonColor,
                backgroundColor: _kWebPanel,
                onRefresh: _load,
                child: ListView(
                  padding: AccountantResponsive.pageInsets(context, top: 16, bottomExtra: 24),
                  children: [
                    _paymentsTableBlock(context),
                    const SizedBox(height: 28),
                    Text(
                      'Classement des montants par type de frais',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: AccountantResponsive.bodyTitleFontSize(context),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Frais d\'inscription, Première tranche, Deuxième tranche, etc. — selon les types de frais définis pour l\'école.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _kWebTextMuted),
                    ),
                    const SizedBox(height: 12),
                    _summaryTable(context),
                  ],
                ),
              ),
        bottomNavigationBar: const AccountantBottomNav(),
      ),
    );
  }

  Widget _paymentsTableBlock(BuildContext context) {
    if (_payments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _kWebPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Text(
            'Aucun paiement trouvé',
            style: TextStyle(color: _kWebTextMuted),
          ),
        ),
      );
    }

    final tableMinW = AccountantResponsive.tableScrollInnerWidth(
      context,
      minScrollWidth: AccountantResponsive.paymentsTableMinWidth(context),
    );

    return Container(
      decoration: BoxDecoration(
        color: _kWebPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableMinW,
          child: Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
            columnWidths: const {
              0: FlexColumnWidth(2.2),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(1.6),
              3: FlexColumnWidth(1.8),
              4: FlexColumnWidth(1.4),
              5: FlexColumnWidth(1.4),
              6: FlexColumnWidth(1.6),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: _kWebHeaderRow),
                children: [
                  _th(context, 'ID'),
                  _th(context, 'UTILISATEUR'),
                  _th(context, 'MONTANT'),
                  _th(context, 'MÉTHODE'),
                  _th(context, 'STATUT'),
                  _th(context, 'DATE'),
                  _th(context, 'ACTIONS'),
                ],
              ),
              ..._payments.map((p) => _paymentTableRow(context, p)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(BuildContext context, String label) {
    final h = AccountantResponsive.cellPaddingH(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(h, 12, h, 12),
      child: Text(label, style: _headerStyleFor(context)),
    );
  }

  TableRow _paymentTableRow(BuildContext context, dynamic p) {
    final id = p['id'];
    final pid = id is int ? id : int.tryParse('$id');
    final status = p['status']?.toString() ?? '';
    final method = p['payment_method']?.toString() ?? '';
    final methodLabel = _methodLabels[method] ?? method;
    final userName = (p['user_name']?.toString() ?? '—').toUpperCase();
    final payId = p['payment_id']?.toString() ?? '$id';
    final amount = p['amount'];
    final cur = p['currency']?.toString() ?? 'CDF';
    final dateStr = _dateStr(p);
    final busy = pid != null && _actionBusy.contains(pid);
    final st = status.toUpperCase();
    final fs = _tableFontSize(context);

    return TableRow(
      children: [
        _td(
          context,
          Text(
            payId,
            style: TextStyle(color: Colors.white, fontSize: fs, fontFamily: 'monospace'),
          ),
        ),
        _td(
          context,
          Text(
            userName,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fs),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _td(
          context,
          Text(
            '${_fmt(double.tryParse('$amount') ?? 0)} $cur',
            style: TextStyle(color: Colors.white, fontSize: fs),
          ),
        ),
        _td(
          context,
          Text(methodLabel, style: TextStyle(color: Colors.white70, fontSize: fs)),
        ),
        _td(context, Align(alignment: Alignment.centerLeft, child: _statusBadge(status))),
        _td(
          context,
          Text(dateStr, style: TextStyle(color: Colors.white70, fontSize: fs)),
        ),
        _td(
          context,
          st == 'PENDING'
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Valider',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: busy || pid == null ? null : () => _validate(pid),
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                            )
                          : const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 24),
                    ),
                    IconButton(
                      tooltip: 'Rejeter',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: busy || pid == null ? null : () => _reject(pid),
                      icon: const Icon(Icons.cancel_outlined, color: Color(0xFFE57373), size: 24),
                    ),
                  ],
                )
              : st == 'COMPLETED' && pid != null
                  ? TextButton.icon(
                      onPressed: () => _downloadReceipt(pid, payId),
                      icon: const Icon(Icons.description_outlined, size: 18, color: Color(0xFF64B5F6)),
                      label: const Text('Reçu', style: TextStyle(color: Color(0xFF64B5F6), fontWeight: FontWeight.w600)),
                    )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _td(BuildContext context, Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AccountantResponsive.cellPaddingV(context),
        horizontal: AccountantResponsive.cellPaddingH(context),
      ),
      child: child,
    );
  }

  Widget _summaryTable(BuildContext context) {
    if (_summaryByFeeType.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kWebPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          'Aucune donnée (les montants par type de frais proviennent des paiements ventilés par type).',
          style: TextStyle(color: _kWebTextMuted, fontSize: 13),
        ),
      );
    }

    final totals = <String, ({double amount, int count})>{};
    for (final row in _summaryByFeeType) {
      if (row is! Map) continue;
      final c = '${row['currency'] ?? 'CDF'}';
      final ta = double.tryParse('${row['total_amount'] ?? 0}') ?? 0;
      final pc = int.tryParse('${row['payment_count'] ?? 0}') ?? 0;
      final prev = totals[c] ?? (amount: 0.0, count: 0);
      totals[c] = (amount: prev.amount + ta, count: prev.count + pc);
    }

    final totalLine = totals.entries.map((e) => '${_fmt(e.value.amount)} ${e.key}').join(' / ');
    final totalCount = totals.values.fold<int>(0, (a, b) => a + b.count);

    return Container(
      decoration: BoxDecoration(
        color: _kWebPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: AccountantResponsive.tableScrollInnerWidth(
              context,
              minScrollWidth: AccountantResponsive.isCompact(context) ? 480 : 560,
            ),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              dataTableTheme: DataTableThemeData(
                headingTextStyle: _headerStyleFor(context),
                dataTextStyle: TextStyle(
                  color: Colors.white70,
                  fontSize: AccountantResponsive.isCompact(context) ? 12 : 13,
                ),
              ),
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(_kWebHeaderRow),
              dataRowColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return Colors.white.withValues(alpha: 0.04);
                }
                return null;
              }),
              columns: const [
                DataColumn(label: Text('RANG')),
                DataColumn(label: Text('TYPE DE FRAIS')),
                DataColumn(label: Text('MONTANT TOTAL'), numeric: true),
                DataColumn(label: Text('DEVISE')),
                DataColumn(label: Text('NB PAIEMENTS'), numeric: true),
              ],
              rows: [
                ..._summaryByFeeType.map((row) {
                  final m = row as Map;
                  return DataRow(
                    cells: [
                      DataCell(Text('${m['rank'] ?? ''}', style: const TextStyle(color: Colors.white))),
                      DataCell(Text('${m['fee_type_name'] ?? '—'}', style: const TextStyle(color: Colors.white))),
                      DataCell(Text(
                        _fmt(double.tryParse('${m['total_amount'] ?? 0}') ?? 0),
                        style: const TextStyle(color: Colors.white),
                      )),
                      DataCell(Text('${m['currency'] ?? ''}', style: const TextStyle(color: Colors.white70))),
                      DataCell(Text('${m['payment_count'] ?? 0}', style: const TextStyle(color: Colors.white70))),
                    ],
                  );
                }),
                DataRow(
                  color: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.06)),
                  cells: [
                    const DataCell(SizedBox()),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    DataCell(Text(totalLine, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                    const DataCell(Text('—', style: TextStyle(color: Colors.white70))),
                    DataCell(Text('$totalCount', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
