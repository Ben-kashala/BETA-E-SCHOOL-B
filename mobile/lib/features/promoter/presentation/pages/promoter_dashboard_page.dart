import 'package:flutter/material.dart';
import '../../../../core/network/api_service.dart';

class PromoterDashboardPage extends StatefulWidget {
  const PromoterDashboardPage({super.key});

  @override
  State<PromoterDashboardPage> createState() => _PromoterDashboardPageState();
}

class _PromoterDashboardPageState extends State<PromoterDashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get(
        '/api/schools/schools/promoter-dashboard/',
        useCache: false,
      );
      final data = response.data;
      setState(() {
        _stats = data is Map<String, dynamic>
            ? data
            : Map<String, dynamic>.from(data as Map);
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _stats = {};
        _isLoading = false;
      });
    }
  }

  String _formatAmount(dynamic value) {
    final number = value is num ? value.toDouble() : 0.0;
    return number.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final schoolsByType =
        (_stats['schools_by_type'] as Map?)?.cast<String, dynamic>() ?? {};
    final paymentsByCurrency =
        (_stats['payments_by_currency'] as Map?)?.cast<String, dynamic>() ?? {};
    final expensesByCurrency =
        (_stats['expenses_by_currency'] as Map?)?.cast<String, dynamic>() ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Promoteur'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _StatCard(
                    title: "Nombre d'écoles",
                    value: '${_stats['schools_total'] ?? 0}',
                    icon: Icons.school,
                    color: Colors.blue,
                  ),
                  _StatCard(
                    title: "Nombre d'élèves",
                    value: '${_stats['students_total'] ?? 0}',
                    icon: Icons.groups,
                    color: Colors.green,
                  ),
                  _CurrencyCard(
                    title: 'Entrées (paiements)',
                    data: paymentsByCurrency,
                    formatter: _formatAmount,
                    icon: Icons.credit_card,
                    color: Colors.teal,
                  ),
                  _CurrencyCard(
                    title: 'Dépenses payées',
                    data: expensesByCurrency,
                    formatter: _formatAmount,
                    icon: Icons.arrow_downward,
                    color: Colors.red,
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Répartition des écoles par type",
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _TypeLine(
                            label: 'Maternelle',
                            value: '${schoolsByType['MATERNELLE'] ?? 0}',
                          ),
                          _TypeLine(
                            label: 'Primaire',
                            value: '${schoolsByType['PRIMAIRE'] ?? 0}',
                          ),
                          _TypeLine(
                            label: 'Humanitaire',
                            value: '${schoolsByType['HUMANITAIRE'] ?? 0}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title),
        subtitle: Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  final String Function(dynamic value) formatter;
  final IconData icon;
  final Color color;

  const _CurrencyCard({
    required this.title,
    required this.data,
    required this.formatter,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color,
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.isEmpty)
              const Text('0.00')
            else
              ...data.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${formatter(entry.value)} ${entry.key}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypeLine extends StatelessWidget {
  final String label;
  final String value;

  const _TypeLine({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
