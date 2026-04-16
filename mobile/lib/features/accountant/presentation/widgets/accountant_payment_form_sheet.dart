import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

const _mmMethods = {
  'MOBILE_MONEY_ORANGE',
  'MOBILE_MONEY_MPESA',
  'MOBILE_MONEY_AIRTEL',
  'MOBILE_MONEY',
};

/// L’API peut renvoyer la même année plusieurs fois → [DropdownButton] exige des valeurs uniques.
List<String> _dedupeAcademicYears(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final s in raw) {
    final t = s.trim();
    if (t.isEmpty) continue;
    if (seen.add(t)) out.add(t);
  }
  return out;
}

/// Formulaire « Effectuer un paiement » — aligné sur `PaymentForm` web (mode comptable).
Future<void> showAccountantPaymentFormSheet(
  BuildContext context, {
  required VoidCallback onSuccess,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _AccountantPaymentFormBody(onSuccess: onSuccess),
  );
}

class _AccountantPaymentFormBody extends ConsumerStatefulWidget {
  const _AccountantPaymentFormBody({required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  ConsumerState<_AccountantPaymentFormBody> createState() =>
      _AccountantPaymentFormBodyState();
}

class _AccountantPaymentFormBodyState extends ConsumerState<_AccountantPaymentFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  List<dynamic> _parents = [];
  List<dynamic> _students = [];
  List<dynamic> _feeTypes = [];
  List<String> _academicYears = [];

  int? _parentUserId;
  int? _studentId;
  int? _feeTypeId;
  String _currency = 'CDF';
  String _paymentMethod = 'CASH';
  String _status = 'COMPLETED';
  String? _academicYear;

  static const _methods = [
    'CASH',
    'BANK_TRANSFER',
    'MOBILE_MONEY_AIRTEL',
    'MOBILE_MONEY_ORANGE',
    'MOBILE_MONEY_MPESA',
    'MOBILE_MONEY',
    'ONLINE',
    'CARD',
  ];

  static const _methodLabels = {
    'CASH': 'Espèces',
    'BANK_TRANSFER': 'Virement bancaire',
    'MOBILE_MONEY_AIRTEL': 'Airtel Money',
    'MOBILE_MONEY_ORANGE': 'Orange Money',
    'MOBILE_MONEY_MPESA': 'M-Pesa',
    'MOBILE_MONEY': 'Mobile Money (manuel / autre)',
    'ONLINE': 'Paiement en ligne',
    'CARD': 'Carte bancaire',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _list(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiService().get('/api/auth/users/', queryParameters: {'role': 'PARENT'}, useCache: false),
        ApiService().get('/api/auth/students/', useCache: false),
        ApiService().get('/api/payments/fee-types/', useCache: false),
        ApiService().get('/api/academics/academic-years/available/', useCache: false),
      ]);
      final parents = _list(results[0].data);
      final students = _list(results[1].data);
      final fees = _list(results[2].data);
      final ay = results[3].data;
      var years = <String>[];
      String? cur;
      if (ay is Map) {
        final cs = '${ay['current'] ?? ''}'.trim();
        cur = cs.isEmpty ? null : cs;
        final a = ay['available'];
        if (a is List) {
          years = a.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
        }
      }
      years = _dedupeAcademicYears(years);
      if (years.isEmpty) {
        final y = DateTime.now().year;
        years = ['$y-${y + 1}'];
      }
      var selected = cur;
      if (selected != null && !years.contains(selected)) {
        selected = years.first;
      }
      selected ??= years.first;
      if (!mounted) return;
      setState(() {
        _parents = parents;
        _students = students;
        _feeTypes = fees;
        _academicYears = years;
        _academicYear = selected;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _studentParentId(dynamic s) {
    final p = s['parent'];
    if (p == null) return null;
    if (p is int) return p;
    if (p is num) return p.toInt();
    if (p is Map) {
      final id = p['id'];
      if (id is int) return id;
      return int.tryParse('$id');
    }
    return int.tryParse('$p');
  }

  List<dynamic> get _filteredStudents {
    if (_parentUserId == null) return [];
    return _students.where((s) => _studentParentId(s) == _parentUserId).toList();
  }

  String _parentLabel(dynamic u) {
    final fn = u['first_name'] ?? '';
    final ln = u['last_name'] ?? '';
    final em = u['email'] ?? '';
    final name = '$fn $ln'.trim();
    return em.isNotEmpty ? '$name ($em)' : (name.isEmpty ? 'Parent #${u['id']}' : name);
  }

  String _studentLabel(dynamic s) {
    final u = s['user'] ?? {};
    final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    final sid = s['student_id'] ?? '';
    return sid.isNotEmpty ? '$name — $sid' : (name.isEmpty ? 'Élève #${s['id']}' : name);
  }

  bool get _isMm => _mmMethods.contains(_paymentMethod);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_parentUserId == null || _studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez un parent et un élève.')),
      );
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim().replaceFirst(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant invalide.')),
      );
      return;
    }
    if (_isMm && _phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez le téléphone pour le Mobile Money.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final payload = <String, dynamic>{
        'user': _parentUserId,
        'student': _studentId,
        'amount': amount,
        'currency': _currency,
        'payment_method': _paymentMethod,
        'description': _descCtrl.text.trim(),
        'reference_number': _refCtrl.text.trim(),
        if (_feeTypeId != null) 'fee_type': _feeTypeId,
        if (_academicYear != null && _academicYear!.isNotEmpty) 'academic_year': _academicYear,
        'status': _isMm ? 'PENDING' : _status,
      };

      final res = await ApiService().post<Map<String, dynamic>>(
        '/api/payments/payments/',
        data: payload,
      );
      final pid = res.data?['id'];
      final id = pid is int ? pid : int.tryParse('$pid');
      if (id == null) throw Exception('Réponse sans identifiant de paiement');

      if (_isMm) {
        await ApiService().post<Map<String, dynamic>>(
          '/api/payments/payments/initiate-mobile/',
          data: {
            'payment_id': id,
            'phone_number': _phoneCtrl.text.trim(),
            'payment_method': _paymentMethod,
          },
        );
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: const Text('Mobile Money'),
            content: const Text(
              'Demande envoyée. Le parent doit valider sur son téléphone. '
              'Ensuite vous pouvez confirmer le paiement depuis la liste.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK')),
            ],
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isMm ? 'Paiement créé (en attente).' : 'Paiement enregistré.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Effectuer un paiement',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Parent (payeur) *',
                        border: OutlineInputBorder(),
                      ),
                      value: _parentUserId,
                      items: _parents.map((u) {
                        final id = u['id'];
                        final uid = id is int ? id : int.tryParse('$id');
                        if (uid == null) return null;
                        return DropdownMenuItem(value: uid, child: Text(_parentLabel(u)));
                      }).whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: (v) => setState(() {
                        _parentUserId = v;
                        _studentId = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Élève *',
                        border: OutlineInputBorder(),
                      ),
                      value: _studentId,
                      items: _filteredStudents.map((s) {
                        final id = s['id'];
                        final sid = id is int ? id : int.tryParse('$id');
                        if (sid == null) return null;
                        return DropdownMenuItem(value: sid, child: Text(_studentLabel(s)));
                      }).whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: (v) => setState(() => _studentId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Type de frais',
                        border: OutlineInputBorder(),
                      ),
                      value: _feeTypeId,
                      items: [
                        const DropdownMenuItem<int>(value: null, child: Text('— Optionnel —')),
                        ..._feeTypes.map((f) {
                          final id = f['id'];
                          final fid = id is int ? id : int.tryParse('$id');
                          if (fid == null) return null;
                          return DropdownMenuItem<int>(
                            value: fid,
                            child: Text('${f['name']} — ${f['amount']} ${f['currency'] ?? 'CDF'}'),
                          );
                        }).whereType<DropdownMenuItem<int>>(),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _feeTypeId = v;
                          if (v != null) {
                            for (final x in _feeTypes) {
                              if (x is Map && x['id'] == v) {
                                _amountCtrl.text = '${x['amount'] ?? ''}';
                                _currency = '${x['currency'] ?? 'CDF'}';
                                break;
                              }
                            }
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Montant *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (s) =>
                          s == null || s.trim().isEmpty ? 'Requis' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Devise *',
                        border: OutlineInputBorder(),
                      ),
                      value: _currency,
                      items: const [
                        DropdownMenuItem(value: 'CDF', child: Text('CDF')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? 'CDF'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Méthode de paiement *',
                        border: OutlineInputBorder(),
                      ),
                      value: _paymentMethod,
                      items: _methods
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(_methodLabels[m] ?? m),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _paymentMethod = v ?? 'CASH'),
                    ),
                    if (_isMm) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone du payeur *',
                          border: OutlineInputBorder(),
                          hintText: '+243…',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Numéro de référence',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    if (!_isMm)
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Statut',
                          border: OutlineInputBorder(),
                        ),
                        value: _status,
                        items: const [
                          DropdownMenuItem(value: 'COMPLETED', child: Text('Complété (avec reçu)')),
                          DropdownMenuItem(value: 'PENDING', child: Text('En attente')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'COMPLETED'),
                      ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Année scolaire',
                        border: OutlineInputBorder(),
                      ),
                      value: _academicYear,
                      items: _academicYears
                          .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                          .toList(),
                      onChanged: (v) => setState(() => _academicYear = v),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Créer le paiement'),
                    ),
                    TextButton(
                      onPressed: _submitting ? null : () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
