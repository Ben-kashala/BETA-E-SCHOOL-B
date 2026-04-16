import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../layout/accountant_responsive.dart';
import '../widgets/accountant_bottom_nav.dart';

/// Aligné sur `frontend/src/pages/accountant/Expenses.tsx`.
const _categoryLabels = {
  'SALARIES': 'Salaires',
  'MAINTENANCE': 'Entretien / Maintenance',
  'MATERIEL': 'Matériel pédagogique',
  'UTILITIES': 'Eau / Électricité / Internet',
  'EVENTS': 'Activités / Événements',
  'OTHER': 'Autre',
};

const _statusLabels = {
  'PENDING': 'En attente',
  'APPROVED': 'Approuvée',
  'PAID': 'Payée',
  'REJECTED': 'Rejetée',
};

const _paymentLabels = {
  'CASH': 'Espèces',
  'MOBILE_MONEY': 'Mobile Money',
  'MOBILE_MONEY_MPESA': 'M-Pesa',
  'MOBILE_MONEY_ORANGE': 'Orange Money',
  'MOBILE_MONEY_AIRTEL': 'Airtel Money',
  'BANK_TRANSFER': 'Virement bancaire',
  'CARD': 'Carte bancaire',
  'ONLINE': 'Paiement en ligne',
};

/// Visuel aligné sur le web (`Expenses.tsx`) — fond sombre type dashboard.
const Color _kWebBg = Color(0xFF1a223f);
const Color _kWebPanel = Color(0xFF252d4a);
const Color _kWebHeaderRow = Color(0xFF353f5c);
const Color _kWebTextMuted = Color(0xFFB0B8D4);

class AccountantExpensesPage extends ConsumerStatefulWidget {
  const AccountantExpensesPage({super.key});

  @override
  ConsumerState<AccountantExpensesPage> createState() => _AccountantExpensesPageState();
}

class _AccountantExpensesPageState extends ConsumerState<AccountantExpensesPage> {
  List<dynamic> _expenses = [];
  List<dynamic> _feeTypes = [];
  bool _loading = true;

  List<dynamic> _list(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService().get('/api/payments/expenses/', useCache: false),
        ApiService().get('/api/payments/fee-types/', useCache: false),
      ]);
      if (!mounted) return;
      setState(() {
        _expenses = _list(results[0].data);
        _feeTypes = _list(results[1].data);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patchStatus(dynamic idRaw, String status) async {
    final id = idRaw is int ? idRaw : int.tryParse('$idRaw');
    if (id == null) return;
    try {
      await ApiService().patch('/api/payments/expenses/$id/', data: {'status': status});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Statut mis à jour')));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.parseDioError(e))));
      }
    }
  }

  static String _fmt(num n) => NumberFormat('#,##0.00', 'fr_FR').format(n);

  TextStyle _thStyleFor(BuildContext context) => TextStyle(
        fontSize: AccountantResponsive.isCompact(context) ? 10 : 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.35,
        color: _kWebTextMuted,
      );

  double _bodyFont(BuildContext context) => AccountantResponsive.isCompact(context) ? 11.5 : 13;

  Widget _statusBadge(String? status) {
    final s = status ?? '';
    final label = _statusLabels[s] ?? s;
    late Color bg;
    late Color fg;
    switch (s) {
      case 'PAID':
        bg = const Color(0xFF2E7D32);
        fg = Colors.white;
        break;
      case 'APPROVED':
        bg = const Color(0xFF1565C0);
        fg = Colors.white;
        break;
      case 'PENDING':
        bg = const Color(0xFFF9A825);
        fg = const Color(0xFF1a223f);
        break;
      case 'REJECTED':
        bg = const Color(0xFFC62828);
        fg = Colors.white;
        break;
      default:
        bg = Colors.blueGrey.shade700;
        fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _expenseDateStr(dynamic exp) {
    try {
      if (exp['expense_date'] != null) {
        final d = DateTime.parse(exp['expense_date'].toString());
        return DateFormat('d MMM yyyy', 'fr_FR').format(d);
      }
    } catch (_) {}
    return '—';
  }

  void _openCreate() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ExpenseFormSheet(
        feeTypes: _feeTypes,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  void _openEdit(dynamic exp) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ExpenseFormSheet(
        feeTypes: _feeTypes,
        existing: exp,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(authProvider).user?.role == 'ADMIN';

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
      ),
      child: Scaffold(
        backgroundColor: _kWebBg,
        appBar: AppBar(
          title: Text(
            'Gestion des Dépenses',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: AccountantResponsive.appBarTitleFontSize(context)),
          ),
          actions: [
            if (AccountantResponsive.widthOf(context) < 360)
              IconButton(
                tooltip: 'Nouvelle dépense',
                onPressed: _loading ? null : _openCreate,
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
                  onPressed: _loading ? null : _openCreate,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(
                    AccountantResponsive.widthOf(context) < 420 ? 'Dépense' : 'Nouvelle dépense',
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
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: AccountantResponsive.pageInsets(context, top: 16, bottomExtra: 24),
                  children: [
                    _expensesTableBlock(context, isAdmin),
                  ],
                ),
              ),
        bottomNavigationBar: const AccountantBottomNav(),
      ),
    );
  }

  Widget _th(BuildContext context, String label) {
    final h = AccountantResponsive.cellPaddingH(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(h, 12, h, 12),
      child: Text(label, style: _thStyleFor(context)),
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

  Widget _expensesTableBlock(BuildContext context, bool isAdmin) {
    if (_expenses.isEmpty) {
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
            'Aucune dépense',
            style: TextStyle(color: _kWebTextMuted),
          ),
        ),
      );
    }

    final tableMinW = AccountantResponsive.tableScrollInnerWidth(
      context,
      minScrollWidth: AccountantResponsive.expensesTableMinWidth(context),
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
              0: FlexColumnWidth(2.0),
              1: FlexColumnWidth(1.5),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.35),
              4: FlexColumnWidth(1.25),
              5: FlexColumnWidth(1.0),
              6: FlexColumnWidth(1.0),
              7: FlexColumnWidth(1.6),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: _kWebHeaderRow),
                children: [
                  _th(context, 'LIBELLÉ'),
                  _th(context, 'CATÉGORIE'),
                  _th(context, 'MONTANT'),
                  _th(context, 'TYPE PAIEMENT'),
                  _th(context, 'IMPUTÉ AU'),
                  _th(context, 'STATUT'),
                  _th(context, 'DATE'),
                  _th(context, 'ACTIONS'),
                ],
              ),
              ..._expenses.map((exp) => _expenseRow(context, exp, isAdmin)),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _expenseRow(BuildContext context, dynamic exp, bool isAdmin) {
    final status = exp['status']?.toString() ?? '';
    final cat = exp['category']?.toString() ?? '';
    final pm = exp['payment_method']?.toString() ?? '';
    final amt = double.tryParse('${exp['amount'] ?? 0}') ?? 0;
    final cur = exp['currency']?.toString() ?? 'CDF';
    final title = exp['title']?.toString() ?? '—';
    final impute = exp['deduct_from_fee_type_name']?.toString();
    final fs = _bodyFont(context);
    final fsMuted = fs - 0.5;

    return TableRow(
      children: [
        _td(
          context,
          Text(
            title,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fs),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _td(
          context,
          Text(
            _categoryLabels[cat] ?? cat,
            style: TextStyle(color: _kWebTextMuted, fontSize: fsMuted),
          ),
        ),
        _td(
          context,
          Text(
            '${_fmt(amt)} $cur',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fs),
          ),
        ),
        _td(
          context,
          Text(
            _paymentLabels[pm] ?? pm,
            style: TextStyle(color: _kWebTextMuted, fontSize: fsMuted),
          ),
        ),
        _td(
          context,
          Text(
            impute != null && impute.isNotEmpty ? impute : '—',
            style: TextStyle(color: _kWebTextMuted, fontSize: fsMuted),
          ),
        ),
        _td(context, Align(alignment: Alignment.centerLeft, child: _statusBadge(status))),
        _td(
          context,
          Text(
            _expenseDateStr(exp),
            style: TextStyle(color: _kWebTextMuted, fontSize: fsMuted),
          ),
        ),
        _td(context, _actionsCell(exp, status, isAdmin)),
      ],
    );
  }

  Widget _actionsCell(dynamic exp, String status, bool isAdmin) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (status == 'PENDING')
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF64B5F6),
              ),
              onPressed: () => _openEdit(exp),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Modifier', style: TextStyle(fontSize: 12)),
            ),
          if (status == 'PENDING' && isAdmin) ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF81C784),
              ),
              onPressed: () => _patchStatus(exp['id'], 'APPROVED'),
              child: const Text('Approuver', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFFE57373),
              ),
              onPressed: () => _patchStatus(exp['id'], 'REJECTED'),
              child: const Text('Rejeter', style: TextStyle(fontSize: 12)),
            ),
          ],
          if (status == 'APPROVED')
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: const Color(0xFF64B5F6),
              ),
              onPressed: () => _patchStatus(exp['id'], 'PAID'),
              child: const Text('Marquer payée', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _ExpenseFormSheet extends StatefulWidget {
  const _ExpenseFormSheet({required this.feeTypes, required this.onSaved, this.existing});

  final List<dynamic> feeTypes;
  final dynamic existing;
  final VoidCallback onSaved;

  @override
  State<_ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<_ExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late final TextEditingController _desc;
  late final TextEditingController _ref;
  String _category = 'OTHER';
  String _currency = 'CDF';
  String _paymentMethod = 'CASH';
  int? _deductFeeTypeId;
  DateTime? _expenseDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e != null ? '${e['title'] ?? ''}' : '');
    _amount = TextEditingController(text: e != null ? '${e['amount'] ?? ''}' : '');
    _desc = TextEditingController(text: e != null ? '${e['description'] ?? ''}' : '');
    _ref = TextEditingController(text: e != null ? '${e['reference'] ?? ''}' : '');
    if (e != null) {
      _category = '${e['category'] ?? 'OTHER'}';
      _currency = '${e['currency'] ?? 'CDF'}';
      _paymentMethod = '${e['payment_method'] ?? 'CASH'}';
      final dft = e['deduct_from_fee_type'];
      if (dft is int) _deductFeeTypeId = dft;
      if (dft is num) _deductFeeTypeId = dft.toInt();
      try {
        if (e['expense_date'] != null) {
          _expenseDate = DateTime.parse(e['expense_date'].toString());
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _desc.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final isEdit = widget.existing != null;
    if (isEdit && widget.existing['status'] != 'PENDING') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seules les dépenses en attente peuvent être modifiées')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final data = {
        'title': _title.text.trim(),
        'category': _category,
        'amount': _amount.text.trim().replaceFirst(',', '.'),
        'currency': _currency,
        'payment_method': _paymentMethod,
        'deduct_from_fee_type': _deductFeeTypeId,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'reference': _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        'expense_date': _expenseDate != null
            ? DateFormat('yyyy-MM-dd').format(_expenseDate!)
            : null,
      };

      if (isEdit) {
        await ApiService().patch('/api/payments/expenses/${widget.existing['id']}/', data: data);
      } else {
        await ApiService().post('/api/payments/expenses/', data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Dépense modifiée' : 'Dépense enregistrée')),
        );
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ApiService.parseDioError(e))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Modifier la dépense' : 'Nouvelle dépense',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Libellé *', border: OutlineInputBorder()),
                validator: (s) => s == null || s.trim().isEmpty ? 'Requis' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Catégorie', border: OutlineInputBorder()),
                value: _category,
                items: _categoryLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'OTHER'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      decoration: const InputDecoration(labelText: 'Montant *', border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (s) {
                        if (s == null || s.trim().isEmpty) return 'Requis';
                        if (double.tryParse(s.replaceFirst(',', '.')) == null) return 'Invalide';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Devise', border: OutlineInputBorder()),
                      value: _currency,
                      items: const [
                        DropdownMenuItem(value: 'CDF', child: Text('CDF')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                      ],
                      onChanged: (v) => setState(() => _currency = v ?? 'CDF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Type de paiement',
                  border: OutlineInputBorder(),
                  helperText: 'Déductible en caisse selon ce type.',
                ),
                value: _paymentMethod,
                items: _paymentLabels.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) => setState(() => _paymentMethod = v ?? 'CASH'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Imputé au type de frais',
                  border: OutlineInputBorder(),
                  helperText: 'Type de frais dont sera déduite cette dépense (optionnel).',
                ),
                value: _deductFeeTypeId,
                items: [
                  const DropdownMenuItem<int>(value: null, child: Text('— Aucun —')),
                  ...widget.feeTypes.map((ft) {
                    final id = ft['id'];
                    final fid = id is int ? id : int.tryParse('$id');
                    if (fid == null) return null;
                    final cur = ft['currency'] != null ? ' (${ft['currency']})' : '';
                    return DropdownMenuItem<int>(
                      value: fid,
                      child: Text('${ft['name']}$cur'),
                    );
                  }).whereType<DropdownMenuItem<int>>(),
                ],
                onChanged: (v) => setState(() => _deductFeeTypeId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ref,
                decoration: const InputDecoration(labelText: 'Référence', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  _expenseDate != null ? DateFormat('dd/MM/yyyy').format(_expenseDate!) : 'Non renseignée',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () async {
                    final now = DateTime.now();
                    final p = await showDatePicker(
                      context: context,
                      initialDate: _expenseDate ?? now,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (p != null) setState(() => _expenseDate = p);
                  },
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Enregistrer' : 'Créer'),
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
