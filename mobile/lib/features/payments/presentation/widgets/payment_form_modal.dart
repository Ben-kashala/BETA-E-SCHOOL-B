import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../../core/network/api_service.dart';

class PaymentFormModal extends ConsumerStatefulWidget {
  final List<dynamic> children;
  final List<dynamic> feeTypes;
  final Function()? onSubmitted;

  const PaymentFormModal({
    super.key,
    required this.children,
    required this.feeTypes,
    this.onSubmitted,
  });

  @override
  ConsumerState<PaymentFormModal> createState() => _PaymentFormModalState();
}

class _PaymentFormModalState extends ConsumerState<PaymentFormModal> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedStudentId;
  int? _selectedFeeTypeId;
  double? _amount;
  String _currency = 'CDF';
  String _paymentMethod = 'CASH';
  String _description = '';
  String _referenceNumber = '';
  String? _academicYear;
  bool _isSubmitting = false;

  final List<String> _paymentMethods = [
    'CASH',
    'MOBILE_MONEY',
    'MOBILE_MONEY_MPESA',
    'MOBILE_MONEY_ORANGE',
    'MOBILE_MONEY_AIRTEL',
    'BANK_TRANSFER',
    'CARD',
    'ONLINE',
  ];

  final Map<String, String> _paymentMethodLabels = {
    'CASH': 'Espèces',
    'MOBILE_MONEY': 'Mobile Money',
    'MOBILE_MONEY_MPESA': 'M-Pesa',
    'MOBILE_MONEY_ORANGE': 'Orange Money',
    'MOBILE_MONEY_AIRTEL': 'Airtel Money',
    'BANK_TRANSFER': 'Virement bancaire',
    'CARD': 'Carte bancaire',
    'ONLINE': 'Paiement en ligne',
  };

  @override
  void initState() {
    super.initState();
    final currentYear = DateTime.now().year;
    _academicYear = '$currentYear-${currentYear + 1}';
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner un enfant')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final payload = {
        'student': _selectedStudentId,
        'amount': _amount,
        'currency': _currency,
        'payment_method': _paymentMethod,
        'description': _description,
        'reference_number': _referenceNumber,
        if (_selectedFeeTypeId != null) 'fee_type': _selectedFeeTypeId,
        if (_academicYear != null) 'academic_year': _academicYear,
      };

      await ApiService().post('/api/payments/payments/', data: payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement créé avec succès')),
        );
        widget.onSubmitted?.call();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  String _getChildName(dynamic child) {
    final identity = child['identity'] ?? child;
    final user = identity['user'] ?? {};
    final firstName = user['first_name'] ?? '';
    final lastName = user['last_name'] ?? '';
    final studentId = identity['student_id'] ?? '';
    return '${firstName} ${lastName}'.trim() + (studentId.isNotEmpty ? ' - $studentId' : '');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // En-tête
              AppBar(
                title: const Text('Nouveau paiement'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              // Contenu scrollable
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      // Enfant
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Enfant *',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedStudentId,
                        items: widget.children.map((child) {
                          final identity = child['identity'] ?? child;
                          final studentId = identity['id'];
                          return DropdownMenuItem<int>(
                            value: studentId as int,
                            child: Text(_getChildName(child)),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedStudentId = value),
                        validator: (value) => value == null ? 'Ce champ est requis' : null,
                      ),
                      const SizedBox(height: 16),
                      // Type de frais
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Type de frais',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedFeeTypeId,
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Aucun')),
                          ...widget.feeTypes.map((fee) {
                            return DropdownMenuItem<int>(
                              value: fee['id'] as int,
                              child: Text('${fee['name']} - ${fee['amount']} ${fee['currency'] ?? 'CDF'}'),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedFeeTypeId = value;
                            if (value != null && widget.feeTypes.isNotEmpty) {
                              final fee = widget.feeTypes.firstWhere((f) => f['id'] == value);
                              _amount = (fee['amount'] is num) ? fee['amount'].toDouble() : double.tryParse(fee['amount'].toString());
                              _currency = fee['currency'] ?? 'CDF';
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      // Montant
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Montant *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        initialValue: _amount?.toString(),
                        onChanged: (value) {
                          _amount = double.tryParse(value);
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Ce champ est requis';
                          if (double.tryParse(value) == null) return 'Montant invalide';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Devise
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Devise *',
                          border: OutlineInputBorder(),
                        ),
                        value: _currency,
                        items: const [
                          DropdownMenuItem(value: 'CDF', child: Text('CDF')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (value) => setState(() => _currency = value ?? 'CDF'),
                      ),
                      const SizedBox(height: 16),
                      // Méthode de paiement
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Méthode de paiement *',
                          border: OutlineInputBorder(),
                        ),
                        value: _paymentMethod,
                        items: _paymentMethods.map((method) {
                          return DropdownMenuItem(
                            value: method,
                            child: Text(_paymentMethodLabels[method] ?? method),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _paymentMethod = value ?? 'CASH'),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        onChanged: (value) => _description = value,
                      ),
                      const SizedBox(height: 16),
                      // Numéro de référence
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Numéro de référence',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _referenceNumber = value,
                      ),
                    ],
                  ),
                ),
              // Boutons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitPayment,
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Créer le paiement'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
