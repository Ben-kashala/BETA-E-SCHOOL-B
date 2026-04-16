import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../layout/accountant_responsive.dart';
import '../widgets/accountant_bottom_nav.dart';

const _sourceLabels = {
  'PAYMENT': 'Paiement parent',
  'EXPENSE': 'Dépense',
  'ADJUSTMENT': 'Ajustement',
  'OTHER': 'Autre',
};

const _defaultCurrencies = ['CDF', 'USD'];

/// Aligné visuellement sur le web (`frontend/src/pages/accountant/Caisse.tsx`) — thème sombre type dashboard.
const Color _kWebBg = Color(0xFF1a223f);
const Color _kWebPanel = Color(0xFF252d4a);
const Color _kWebHeaderRow = Color(0xFF353f5c);
const Color _kWebTextMuted = Color(0xFFB0B8D4);
const Color _kInGreen = Color(0xFF4CAF50);
const Color _kOutRed = Color(0xFFE57373);
const Color _kDocBlue = Color(0xFF64B5F6);

class AccountantCaissePage extends ConsumerStatefulWidget {
  const AccountantCaissePage({super.key});

  @override
  ConsumerState<AccountantCaissePage> createState() => _AccountantCaissePageState();
}

class _AccountantCaissePageState extends ConsumerState<AccountantCaissePage> {
  List<dynamic> _movements = [];
  List<dynamic> _balance = [];
  bool _loading = true;
  String? _errorMessage;

  static String _fmt(num n) => NumberFormat('#,##0.00', 'fr_FR').format(n);

  List<dynamic> _list(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['results'] is List) return data['results'] as List;
    return [];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        ApiService().get('/api/payments/caisse/operations/', useCache: false),
        ApiService().get('/api/payments/caisse/balance/', useCache: false),
      ]);
      if (!mounted) return;
      setState(() {
        _movements = _list(results[0].data);
        final b = results[1].data;
        _balance = b is List ? b : <dynamic>[];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = ApiService.parseDioError(e);
      });
    }
  }

  Future<void> _generateVouchers() async {
    try {
      final res = await ApiService().post<Map<String, dynamic>>(
        '/api/payments/caisse/generate-missing-vouchers/',
      );
      if (!mounted) return;
      final msg = res.data?['message']?.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Demande traitée')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.parseDioError(e))),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> get _balanceRows {
    if (_balance.isNotEmpty) {
      return _balance.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return _defaultCurrencies
        .map((c) => {
              'currency': c,
              'total_in': 0,
              'total_out': 0,
              'balance': 0,
            })
        .toList();
  }

  void _showAddMovement() {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String movementType = 'IN';
    String currency = 'CDF';
    PlatformFile? picked;
    bool busy = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) {
          final bottom = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nouveau mouvement (ajustement)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                      value: movementType,
                      items: const [
                        DropdownMenuItem(value: 'IN', child: Text('Entrée')),
                        DropdownMenuItem(value: 'OUT', child: Text('Sortie')),
                      ],
                      onChanged: (v) => setLocal(() => movementType = v ?? 'IN'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: amountCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Montant *',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: (s) {
                              if (s == null || s.trim().isEmpty) return 'Requis';
                              final n = double.tryParse(s.replaceFirst(',', '.'));
                              if (n == null || n <= 0) return 'Montant invalide';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            decoration: const InputDecoration(labelText: 'Devise', border: OutlineInputBorder()),
                            value: currency,
                            items: const [
                              DropdownMenuItem(value: 'CDF', child: Text('CDF')),
                              DropdownMenuItem(value: 'USD', child: Text('USD')),
                            ],
                            onChanged: (v) => setLocal(() => currency = v ?? 'CDF'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (optionnel)',
                        border: OutlineInputBorder(),
                        hintText: 'Ex. Ouverture de caisse, Ajustement…',
                      ),
                      maxLength: 255,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              final r = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                              );
                              if (r != null && r.files.isNotEmpty) {
                                setLocal(() => picked = r.files.first);
                              }
                            },
                      icon: const Icon(Icons.attach_file),
                      label: Text(picked?.name ?? 'Bon d\'entrée/sortie (PDF, JPG, PNG)'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setLocal(() => busy = true);
                              try {
                                final map = <String, dynamic>{
                                  'movement_type': movementType,
                                  'amount': amountCtrl.text.trim().replaceFirst(',', '.'),
                                  'currency': currency,
                                };
                                final d = descCtrl.text.trim();
                                if (d.isNotEmpty) map['description'] = d;
                                if (picked != null && picked!.path != null) {
                                  map['document'] = await MultipartFile.fromFile(
                                    picked!.path!,
                                    filename: picked!.name,
                                  );
                                }
                                final fd = FormData.fromMap(map);
                                await ApiService().post('/api/payments/caisse/', data: fd);
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Mouvement enregistré')),
                                  );
                                  _load();
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text(ApiService.parseDioError(e))),
                                  );
                                }
                              } finally {
                                if (context.mounted) setLocal(() => busy = false);
                              }
                            },
                      child: busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(ctx),
                      child: const Text('Annuler'),
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

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final u = Uri.tryParse(url);
    if (u != null && await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  void _showDetail(dynamic m) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kWebPanel,
        title: const Text('Détails de l\'opération', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailLine('Date', _formatOpDate(m['created_at'])),
              _detailLine('Origine', '${_sourceLabels[m['source']] ?? m['source'] ?? '—'}'),
              _detailLine('Montant',
                  '${m['movement_type'] == 'OUT' ? '-' : '+'}${_fmt(double.tryParse('${m['amount'] ?? 0}') ?? 0)} ${m['currency'] ?? ''}'),
              if (m['fee_type_name'] != null)
                _detailLine('Type(s) de frais', '${m['fee_type_name']}'),
              if (m['document_url'] != null)
                TextButton.icon(
                  onPressed: () => _openUrl(m['document_url']?.toString()),
                  icon: const Icon(Icons.download, color: _kDocBlue),
                  label: const Text('Télécharger le document', style: TextStyle(color: _kDocBlue)),
                ),
              _detailLine('Description', '${m['description'] ?? '—'}'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  String _formatOpDate(dynamic v) {
    if (v == null) return '—';
    try {
      final d = DateTime.parse(v.toString());
      return DateFormat('d MMM yyyy HH:mm', 'fr_FR').format(d);
    } catch (_) {
      return '—';
    }
  }

  Widget _detailLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: _kWebTextMuted)),
          Text(v, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  TextStyle _thStyleFor(BuildContext context) => TextStyle(
        fontSize: AccountantResponsive.isCompact(context) ? 10 : 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.35,
        color: _kWebTextMuted,
      );

  double _rowFont(BuildContext context) => AccountantResponsive.isCompact(context) ? 11 : 12;

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
            fontSize: AccountantResponsive.appBarTitleFontSize(context) + 1,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: _kWebBg,
        appBar: AppBar(
          title: Text(
            'Caisse',
            style: TextStyle(fontSize: AccountantResponsive.appBarTitleFontSize(context) + 1),
          ),
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
                    Text(
                      'Entrées et sorties des montants (paiements reçus, dépenses payées, ajustements).',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: _kWebTextMuted),
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage != null) _errorBanner(),
                    const SizedBox(height: 8),
                    _balanceSection(context),
                    const SizedBox(height: 24),
                    _movementsHeader(context),
                    const SizedBox(height: 12),
                    _movementsTableBlock(context),
                  ],
                ),
              ),
        bottomNavigationBar: const AccountantBottomNav(),
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Impossible de charger la caisse',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFCDD2)),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Color(0xFFFFCDD2), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Vérifiez que vous êtes bien comptable ou admin et associé à une école.',
            style: TextStyle(color: Colors.red.shade200, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _balanceSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kWebPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solde par devise',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final fullWidthCards = c.maxWidth < 420;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _balanceRows.map((b) {
                  final cur = b['currency']?.toString() ?? '';
                  final bal = double.tryParse('${b['balance'] ?? 0}') ?? 0;
                  final tin = double.tryParse('${b['total_in'] ?? 0}') ?? 0;
                  final tout = double.tryParse('${b['total_out'] ?? 0}') ?? 0;
                  return SizedBox(
                    width: fullWidthCards ? c.maxWidth : 200,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _kWebHeaderRow.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cur,
                            style: TextStyle(
                              color: _kWebTextMuted,
                              fontSize: AccountantResponsive.isCompact(context) ? 12 : 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_fmt(bal)} $cur',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: AccountantResponsive.isCompact(context) ? 16 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Entrées: ${_fmt(tin)} — Sorties: ${_fmt(tout)}',
                            style: const TextStyle(color: _kWebTextMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _movementsHeader(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        final tiny = constraints.maxWidth < 380;
        final title = Text(
          'Mouvements',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: AccountantResponsive.bodyTitleFontSize(context),
              ),
        );
        final genBtn = OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white30),
            padding: EdgeInsets.symmetric(
              horizontal: tiny ? 8 : 12,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _generateVouchers,
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Text(
            tiny ? 'Bons manquants' : 'Générer les bons manquants',
            style: const TextStyle(fontSize: 12),
          ),
        );
        final addBtn = FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.moduleButtonColor,
            foregroundColor: AppTheme.onAvatarBackgroundColor,
            padding: EdgeInsets.symmetric(horizontal: tiny ? 8 : 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _showAddMovement,
          icon: const Icon(Icons.add, size: 20),
          label: Text(
            tiny ? 'Ajouter' : 'Ajouter un mouvement',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 12),
              genBtn,
              const SizedBox(height: 8),
              addBtn,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    genBtn,
                    const SizedBox(width: 8),
                    addBtn,
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _movementsTableBlock(BuildContext context) {
    if (_movements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kWebPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Column(
          children: [
            Text(
              'Aucun mouvement',
              style: TextStyle(color: _kWebTextMuted, fontSize: 15),
            ),
            SizedBox(height: 8),
            Text(
              'Les montants apparaîtront après validation de paiements, paiement de dépenses ou ajout d\'un ajustement.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kWebTextMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final tableMinW = AccountantResponsive.tableScrollInnerWidth(
      context,
      minScrollWidth: AccountantResponsive.caisseTableMinWidth(context),
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
              0: FlexColumnWidth(1.6),
              1: FlexColumnWidth(1.15),
              2: FlexColumnWidth(1.35),
              3: FlexColumnWidth(1.05),
              4: FlexColumnWidth(0.65),
              5: FlexColumnWidth(1.35),
              6: FlexColumnWidth(1.0),
              7: FlexColumnWidth(1.75),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: _kWebHeaderRow),
                children: [
                  _th(context, 'DATE'),
                  _th(context, 'TYPE'),
                  _th(context, 'ORIGINE'),
                  _th(context, 'MONTANT'),
                  _th(context, 'DEVISE'),
                  _th(context, 'TYPE(S) DE FRAIS'),
                  _th(context, 'DOCUMENT'),
                  _th(context, 'DESCRIPTION'),
                ],
              ),
              ..._movements.map((m) => _movementRow(context, m)),
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
      child: Text(label, style: _thStyleFor(context)),
    );
  }

  TableRow _movementRow(BuildContext context, dynamic m) {
    final isIn = m['movement_type'] == 'IN';
    final typeColor = isIn ? _kInGreen : _kOutRed;
    final amt = double.tryParse('${m['amount'] ?? 0}') ?? 0;
    final sign = isIn ? '+' : '-';
    final docUrl = m['document_url']?.toString();
    final fs = _rowFont(context);
    final iconSz = AccountantResponsive.isCompact(context) ? 16.0 : 18.0;

    return TableRow(
      children: [
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Text(
              _formatOpDate(m['created_at']),
              style: TextStyle(color: Colors.white70, fontSize: fs),
            ),
          ),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isIn ? Icons.arrow_circle_down : Icons.arrow_circle_up,
                  size: iconSz,
                  color: typeColor,
                ),
                const SizedBox(width: 6),
                Text(
                  isIn ? 'Entrée' : 'Sortie',
                  style: TextStyle(color: typeColor, fontWeight: FontWeight.w600, fontSize: fs),
                ),
              ],
            ),
          ),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Text(
              '${_sourceLabels[m['source']] ?? m['source'] ?? '—'}',
              style: TextStyle(color: Colors.white70, fontSize: fs),
            ),
          ),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$sign${_fmt(amt)}',
                style: TextStyle(color: typeColor, fontWeight: FontWeight.w600, fontSize: fs),
              ),
            ),
          ),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Text('${m['currency'] ?? ''}', style: TextStyle(color: Colors.white70, fontSize: fs)),
          ),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Text(
              m['fee_type_name'] != null && '${m['fee_type_name']}'.isNotEmpty ? '${m['fee_type_name']}' : '—',
              style: TextStyle(color: Colors.white70, fontSize: fs),
            ),
          ),
        ),
        _td(
          context,
          docUrl != null && docUrl.isNotEmpty
              ? TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openUrl(docUrl),
                  icon: Icon(Icons.description_outlined, size: AccountantResponsive.isCompact(context) ? 14 : 16, color: _kDocBlue),
                  label: Text('Voir', style: TextStyle(color: _kDocBlue, fontWeight: FontWeight.w600, fontSize: fs)),
                )
              : Text('—', style: TextStyle(color: _kWebTextMuted, fontSize: fs)),
        ),
        _td(
          context,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showDetail(m),
            child: Text(
              m['description']?.toString().isNotEmpty == true ? '${m['description']}' : '—',
              style: TextStyle(color: Colors.white70, fontSize: fs),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
}
