import 'package:flutter/material.dart';

/// Graphique en barres empilées « présences par semaine » (légende + barres + tap détail).
class AttendanceWeekChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> attendanceData;

  const AttendanceWeekChartWidget({
    super.key,
    required this.attendanceData,
  });

  static const double _barMaxHeight = 160;

  @override
  Widget build(BuildContext context) {
    if (attendanceData.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildLegendItem(context, 'Présents', Colors.green),
                _buildLegendItem(context, 'Absents', Colors.red),
                _buildLegendItem(context, 'En retard', Colors.orange),
                _buildLegendItem(context, 'Excusés', Colors.blue),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              children: [
                // Ligne des barres seule : même hauteur et même base pour toutes les semaines
                // (les libellés sont dessous pour éviter le décalage dû à « Partielle »).
                SizedBox(
                  height: _barMaxHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: attendanceData.map((week) {
                      final present = (week['present'] as num?)?.toInt() ?? 0;
                      final absent = (week['absent'] as num?)?.toInt() ?? 0;
                      final late = (week['late'] as num?)?.toInt() ?? 0;
                      final excused = (week['excused'] as num?)?.toInt() ?? 0;
                      final total = (week['total'] as num?)?.toInt() ?? 1;
                      final label = week['label'] as String? ?? '';
                      final isPartialWeek = total > 0 && total < 5;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () => _showWeekDetail(
                              context,
                              label,
                              present,
                              absent,
                              late,
                              excused,
                              total,
                              isPartialWeek,
                            ),
                            child: SizedBox(
                              height: _barMaxHeight,
                              child: total > 0
                                  ? _stackedBar(
                                      isDark: isDark,
                                      totalPx: _barMaxHeight.round(),
                                      excused: excused,
                                      late: late,
                                      absent: absent,
                                      present: present,
                                      total: total,
                                    )
                                  : Container(
                                      height: _barMaxHeight,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey
                                            : Colors.grey[300]!,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: attendanceData.map((week) {
                    final label = week['label'] as String? ?? '';
                    final total = (week['total'] as num?)?.toInt() ?? 1;
                    final isPartialWeek = total > 0 && total < 5;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (isPartialWeek)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Partielle',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 9,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Appuyez sur une barre pour voir le détail',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barre pleine hauteur `totalPx`, empilement sans espace ; arrondis uniquement en haut / bas de la pile.
  /// Ordre visuel (haut → bas) : excusés, retard, absents, présents. Seuls les comptages > 0 reçoivent des pixels.
  Widget _stackedBar({
    required bool isDark,
    required int totalPx,
    required int excused,
    required int late,
    required int absent,
    required int present,
    required int total,
  }) {
    if (total <= 0) {
      return const SizedBox.shrink();
    }

    final raw = <({int count, Color color})>[
      (count: excused, color: Colors.blue),
      (count: late, color: Colors.orange),
      (count: absent, color: Colors.red),
      (count: present, color: Colors.green),
    ];
    final items = raw.where((e) => e.count > 0).toList();

    if (items.isEmpty) {
      return Container(
        height: totalPx.toDouble(),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey : Colors.grey[300]!,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    // Hauteurs entières, somme = totalPx ; le reste sur le dernier segment affiché (bas de la pile).
    final heights = <int>[];
    var used = 0;
    for (var i = 0; i < items.length; i++) {
      if (i < items.length - 1) {
        final h = (items[i].count * totalPx) ~/ total;
        heights.add(h);
        used += h;
      } else {
        heights.add(totalPx - used);
      }
    }

    final n = items.length;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: List<Widget>.generate(n, (i) {
        final borderRadius = n == 1
            ? BorderRadius.circular(6)
            : BorderRadius.only(
                topLeft: i == 0 ? const Radius.circular(6) : Radius.zero,
                topRight: i == 0 ? const Radius.circular(6) : Radius.zero,
                bottomLeft: i == n - 1 ? const Radius.circular(6) : Radius.zero,
                bottomRight:
                    i == n - 1 ? const Radius.circular(6) : Radius.zero,
              );
        return SizedBox(
          height: heights[i].toDouble(),
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: items[i].color,
              borderRadius: borderRadius,
            ),
          ),
        );
      }),
    );
  }

  void _showWeekDetail(
    BuildContext context,
    String label,
    int present,
    int absent,
    int late,
    int excused,
    int total,
    bool isPartialWeek,
  ) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isPartialWeek) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Semaine partielle',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _detailRow(ctx, 'Présents', present, Colors.green),
              _detailRow(ctx, 'Absents', absent, Colors.red),
              _detailRow(ctx, 'En retard', late, Colors.orange),
              _detailRow(ctx, 'Excusés', excused, Colors.blue),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: theme.textTheme.titleSmall),
                  Text(
                    '$total jour${total > 1 ? 's' : ''}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    BuildContext context,
    String label,
    int value,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.bodyMedium),
            ],
          ),
          Text(
            '$value',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
