import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

class AccountantCaissePage extends ConsumerStatefulWidget {
  const AccountantCaissePage({super.key});

  @override
  ConsumerState<AccountantCaissePage> createState() => _AccountantCaissePageState();
}

class _AccountantCaissePageState extends ConsumerState<AccountantCaissePage> {
  Map<String, dynamic>? _caisseData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCaisse();
  }

  Future<void> _loadCaisse() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/payments/caisse/balance/', useCache: false);
      final data = response.data;
      Map<String, dynamic>? balanceMap = {};
      if (data is List && data.isNotEmpty) {
        for (final e in data) {
          if (e is Map && e['currency'] != null) {
            final cur = e['currency'] as String;
            balanceMap['balance_${cur.toLowerCase()}'] = (e['balance'] ?? 0).toString();
          }
        }
      }
      setState(() {
        _caisseData = balanceMap.isNotEmpty ? balanceMap : {'balance_cdf': 0, 'balance_usd': 0};
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _caisseData = {'balance_cdf': 0, 'balance_usd': 0};
        _isLoading = false;
      });
    }
  }

  void _showAddTransaction() {
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController();
    final description = TextEditingController();
    String movementType = 'IN';
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
                    const Text('Nouvelle transaction caisse', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: movementType,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(value: 'IN', child: Text('Entrée')),
                        DropdownMenuItem(value: 'OUT', child: Text('Sortie')),
                      ],
                      onChanged: (v) => setModalState(() => movementType = v ?? 'IN'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      decoration: const InputDecoration(labelText: 'Montant *'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Requis';
                        final n = double.tryParse(v.replaceFirst(',', '.'));
                        if (n == null || n <= 0) return 'Montant invalide';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currency,
                      decoration: const InputDecoration(labelText: 'Devise'),
                      items: const [DropdownMenuItem(value: 'CDF', child: Text('CDF')), DropdownMenuItem(value: 'USD', child: Text('USD'))],
                      onChanged: (v) => setModalState(() => currency = v ?? 'CDF'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'Description (optionnel)', alignLabelWithHint: true),
                      maxLines: 2,
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
                                  await ApiService().post('/api/payments/caisse/', data: {
                                    'movement_type': movementType,
                                    'amount': amount.text.trim().replaceFirst(',', '.'),
                                    'currency': currency,
                                    'description': description.text.trim(),
                                  });
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Transaction enregistrée.')));
                                    _loadCaisse();
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
        title: const Text('Caisse'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _caisseData == null
              ? const Center(child: Text('Données non disponibles'))
              : RefreshIndicator(
                  onRefresh: _loadCaisse,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Solde CDF
                        Card(
                          color: Colors.blue,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const Text(
                                  'Solde CDF',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_caisseData!['balance_cdf'] ?? 0} CDF',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Solde USD
                        Card(
                          color: Colors.green,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                const Text(
                                  'Solde USD',
                                  style: TextStyle(color: Colors.white, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_caisseData!['balance_usd'] ?? 0} USD',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Actions
                        ElevatedButton.icon(
                          onPressed: _showAddTransaction,
                          icon: const Icon(Icons.add),
                          label: const Text('Nouvelle transaction'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
