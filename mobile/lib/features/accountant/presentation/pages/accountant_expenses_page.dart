import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

const _categories = ['SALARIES', 'MAINTENANCE', 'MATERIEL', 'UTILITIES', 'EVENTS', 'OTHER'];
const _categoryLabels = {'SALARIES': 'Salaires', 'MAINTENANCE': 'Entretien', 'MATERIEL': 'Matériel pédagogique', 'UTILITIES': 'Eau/Électricité', 'EVENTS': 'Activités', 'OTHER': 'Autre'};
const _paymentMethods = ['CASH', 'MOBILE_MONEY', 'BANK_TRANSFER', 'CARD', 'ONLINE', 'MOBILE_MONEY_MPESA', 'MOBILE_MONEY_ORANGE', 'MOBILE_MONEY_AIRTEL'];
const _paymentLabels = {'CASH': 'Espèces', 'MOBILE_MONEY': 'Mobile Money', 'BANK_TRANSFER': 'Virement', 'CARD': 'Carte', 'ONLINE': 'En ligne', 'MOBILE_MONEY_MPESA': 'M-Pesa', 'MOBILE_MONEY_ORANGE': 'Orange Money', 'MOBILE_MONEY_AIRTEL': 'Airtel Money'};

class AccountantExpensesPage extends ConsumerStatefulWidget {
  const AccountantExpensesPage({super.key});

  @override
  ConsumerState<AccountantExpensesPage> createState() => _AccountantExpensesPageState();
}

class _AccountantExpensesPageState extends ConsumerState<AccountantExpensesPage> {
  List<dynamic> _expenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  Future<void> _loadExpenses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/payments/expenses/', useCache: false);
      setState(() {
        _expenses = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _showExpenseDetail(dynamic expense) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(expense['title'] ?? 'Dépense'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (expense['description'] != null && (expense['description'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(expense['description'] as String),
                ),
              Text('${expense['amount'] ?? 0} ${expense['currency'] ?? 'CDF'}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Catégorie: ${_categoryLabels[expense['category']] ?? expense['category']}'),
              Text('Moyen: ${_paymentLabels[expense['payment_method']] ?? expense['payment_method']}'),
              Text('Statut: ${expense['status'] == 'PAID' ? 'Payée' : expense['status'] == 'PENDING' ? 'En attente' : expense['status']}'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer'))],
      ),
    );
  }

  void _showCreateExpense() {
    final formKey = GlobalKey<FormState>();
    final title = TextEditingController();
    final description = TextEditingController();
    final amount = TextEditingController();
    String category = 'OTHER';
    String paymentMethod = 'CASH';
    String currency = 'CDF';
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Nouvelle dépense', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Libellé *'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      decoration: const InputDecoration(labelText: 'Montant *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        if (double.tryParse(v.replaceFirst(',', '.')) == null) return 'Nombre invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(labelText: 'Catégorie'),
                      items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabels[c] ?? c))).toList(),
                      onChanged: (v) => setModalState(() => category = v ?? 'OTHER'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: const InputDecoration(labelText: 'Moyen de paiement'),
                      items: _paymentMethods.map((m) => DropdownMenuItem(value: m, child: Text(_paymentLabels[m] ?? m))).toList(),
                      onChanged: (v) => setModalState(() => paymentMethod = v ?? 'CASH'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currency,
                      decoration: const InputDecoration(labelText: 'Devise'),
                      items: const [DropdownMenuItem(value: 'CDF', child: Text('CDF')), DropdownMenuItem(value: 'USD', child: Text('USD'))],
                      onChanged: (v) => setModalState(() => currency = v ?? 'CDF'),
                    ),
                    const SizedBox(height: 24),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler'))),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                setModalState(() => loading = true);
                                try {
                                  await ApiService().post('/api/payments/expenses/', data: {
                                    'title': title.text.trim(),
                                    'description': description.text.trim(),
                                    'amount': amount.text.trim().replaceFirst(',', '.'),
                                    'currency': currency,
                                    'category': category,
                                    'payment_method': paymentMethod,
                                    'status': 'PENDING',
                                  });
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Dépense enregistrée.')));
                                    _loadExpenses();
                                  }
                                } catch (e) {
                                  setModalState(() => loading = false);
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}')));
                                }
                              },
                              child: const Text('Enregistrer'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateExpense,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _expenses.isEmpty
              ? const Center(child: Text('Aucune dépense'))
              : RefreshIndicator(
                  onRefresh: _loadExpenses,
                  child: ListView.builder(
                    itemCount: _expenses.length,
                    itemBuilder: (context, index) {
                      final expense = _expenses[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          leading: const Icon(Icons.money_off, color: Colors.red),
                          title: Text(expense['title'] ?? expense['description'] ?? 'Dépense'),
                          subtitle: Text('${expense['amount'] ?? 0} ${expense['currency'] ?? 'CDF'}'),
                          trailing: Chip(
                            label: Text(expense['status'] == 'PAID' ? 'Payée' : 'En attente'),
                            backgroundColor: expense['status'] == 'PAID'
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                          ),
                          onTap: () => _showExpenseDetail(expense),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
