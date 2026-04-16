import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../layout/accountant_responsive.dart';
import '../widgets/accountant_bottom_nav.dart';

/// Tableau de bord comptable — aligné sur le web (`frontend/src/pages/accountant/Dashboard.tsx`).
class AccountantDashboardPage extends ConsumerStatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  ConsumerState<AccountantDashboardPage> createState() =>
      _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends ConsumerState<AccountantDashboardPage> {
  bool _loading = true;
  int _totalPayments = 0;
  int _pendingCount = 0;
  Map<String, double> _completedPaymentsByCurrency = {};
  Map<String, double> _paidExpensesByCurrency = {};
  double _balanceCDF = 0;
  double _balanceUSD = 0;
  int _expensesCount = 0;
  int _studentsCount = 0;

  static String _fmt(num n) => NumberFormat('#,##0.00', 'fr_FR').format(n);

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<Response<dynamic>> _safe(Future<Response<dynamic>> f) async {
    try {
      return await f;
    } catch (_) {
      return Response(
        requestOptions: RequestOptions(path: '/'),
        data: {'results': <dynamic>[]},
      );
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _safe(ApiService().get('/api/payments/payments/', useCache: false)),
        _safe(ApiService().get('/api/payments/payments/', queryParameters: {'status': 'PENDING'}, useCache: false)),
        _safe(ApiService().get('/api/payments/expenses/', useCache: false)),
        _safe(ApiService().get('/api/payments/caisse/balance/', useCache: false)),
        _safe(ApiService().get('/api/auth/students/', useCache: false)),
      ]);

      final payments = _extractList(results[0].data);
      final pending = _extractList(results[1].data);
      final expenses = _extractList(results[2].data);
      final balanceRaw = results[3].data;
      final studentsData = results[4].data;

      final completedPayments = payments
          .where((p) => '${p['status']}'.toUpperCase() == 'COMPLETED')
          .toList();
      final paymentsByCurrency = <String, double>{};
      for (final p in completedPayments) {
        final cur = '${p['currency'] ?? 'CDF'}';
        final amt = double.tryParse('${p['amount'] ?? 0}') ?? 0;
        paymentsByCurrency[cur] = (paymentsByCurrency[cur] ?? 0) + amt;
      }

      final paidExpenses =
          expenses.where((e) => '${e['status']}'.toUpperCase() == 'PAID').toList();
      final expensesByCurrency = <String, double>{};
      for (final e in paidExpenses) {
        final cur = '${e['currency'] ?? 'CDF'}';
        final amt = double.tryParse('${e['amount'] ?? 0}') ?? 0;
        expensesByCurrency[cur] = (expensesByCurrency[cur] ?? 0) + amt;
      }

      final balanceList = balanceRaw is List ? balanceRaw : <dynamic>[];
      var cdf = 0.0, usd = 0.0;
      for (final b in balanceList) {
        if (b is! Map) continue;
        if (b['currency'] == 'CDF') {
          cdf = double.tryParse('${b['balance'] ?? 0}') ?? 0;
        }
        if (b['currency'] == 'USD') {
          usd = double.tryParse('${b['balance'] ?? 0}') ?? 0;
        }
      }

      var stuCount = 0;
      if (studentsData is Map) {
        final c = studentsData['count'];
        if (c is int) {
          stuCount = c;
        } else {
          stuCount = _extractList(studentsData).length;
        }
      }

      if (!mounted) return;
      setState(() {
        _totalPayments = payments.length;
        _pendingCount = pending.length;
        _completedPaymentsByCurrency = paymentsByCurrency;
        _paidExpensesByCurrency = expensesByCurrency;
        _balanceCDF = cdf;
        _balanceUSD = usd;
        _expensesCount = expenses.length;
        _studentsCount = stuCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tableau de bord Comptable',
          style: TextStyle(
            fontSize: AccountantResponsive.appBarTitleFontSize(context),
            color: AppTheme.primaryColor,
          ),
        ),
      ),
      bottomNavigationBar: const AccountantBottomNav(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AccountantResponsive.pageInsets(context, top: 8, bottomExtra: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Vue d’ensemble',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontSize: AccountantResponsive.bodyTitleFontSize(context),
                    ),
              ),
              const SizedBox(height: 12),
              _mainGrid(context),
              if (_completedPaymentsByCurrency.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Paiements effectués',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: AccountantResponsive.bodyTitleFontSize(context) + 2,
                      ),
                ),
                const SizedBox(height: 12),
                _amountByCurrencySection(
                  _completedPaymentsByCurrency,
                  'Paiements effectués',
                  Icons.trending_up,
                  Colors.blue.shade700,
                ),
              ],
              if (_paidExpensesByCurrency.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Dépenses effectuées',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: AccountantResponsive.bodyTitleFontSize(context) + 2,
                      ),
                ),
                const SizedBox(height: 12),
                _amountByCurrencySection(
                  _paidExpensesByCurrency,
                  'Dépenses effectuées',
                  Icons.attach_money,
                  Colors.red.shade600,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mainGrid(BuildContext context) {
    final cards = <_DashCard>[
      _DashCard('Paiements en attente', _loading ? '…' : '$_pendingCount', Icons.credit_card, Colors.amber.shade700),
      _DashCard('Total paiements', _loading ? '…' : '$_totalPayments', Icons.trending_up, Colors.blue.shade600),
      _DashCard('Solde CDF', _loading ? '…' : '${_fmt(_balanceCDF)} CDF', Icons.account_balance_wallet, Colors.green.shade700),
      _DashCard('Solde USD', _loading ? '…' : '${_fmt(_balanceUSD)} USD', Icons.account_balance_wallet, Colors.teal.shade700),
      _DashCard('Nombre d\'élèves', _loading ? '…' : '$_studentsCount', Icons.people, Colors.indigo.shade600),
      _DashCard('Dépenses enregistrées', _loading ? '…' : '$_expensesCount', Icons.payments, Colors.purple.shade600),
    ];

    final n = AccountantResponsive.dashboardGridColumns(context);
    return GridView.count(
      crossAxisCount: n,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: AccountantResponsive.dashboardGridAspectRatio(context),
      children: cards.map((c) => _statCard(c)).toList(),
    );
  }

  Widget _statCard(_DashCard c) {
    // Les cartes sont claires; on force des couleurs lisibles, indépendantes du thème système.
    const cardTextColor = AppTheme.textPrimary;
    const cardSubtleColor = AppTheme.textSecondary;
    return Card(
      elevation: 2,
      color: AppTheme.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    c.title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cardSubtleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: AccountantResponsive.isCompact(context) ? 12 : 13,
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(c.icon, color: Colors.white, size: 20),
                ),
              ],
            ),
            const Spacer(),
            Text(
              c.value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cardTextColor,
                    fontSize: AccountantResponsive.isCompact(context) ? 18 : 20,
                    height: 1.2,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountByCurrencySection(
    Map<String, double> byCurrency,
    String titlePrefix,
    IconData icon,
    Color iconBg,
  ) {
    const textColor = AppTheme.textPrimary;
    const subtleColor = AppTheme.textSecondary;
    return Column(
      children: byCurrency.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            color: AppTheme.surfaceColor,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$titlePrefix (${e.key})',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: subtleColor,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_fmt(e.value)} ${e.key}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

}

class _DashCard {
  _DashCard(this.title, this.value, this.icon, this.color);
  final String title;
  final String value;
  final IconData icon;
  final Color color;
}
