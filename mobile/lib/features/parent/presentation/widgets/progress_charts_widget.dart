import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProgressChartsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> attendanceData;
  final List<Map<String, dynamic>> gradesData;
  final double? averageScore;

  const ProgressChartsWidget({
    super.key,
    required this.attendanceData,
    required this.gradesData,
    this.averageScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Graphique de présence
        if (attendanceData.isNotEmpty) ...[
          Text(
            'Présences par semaine',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildAttendanceChart(context),
          const SizedBox(height: 24),
        ],
        // Graphique des notes
        if (gradesData.isNotEmpty) ...[
          Text(
            'Évolution des notes',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildGradesChart(context),
          const SizedBox(height: 24),
        ],
        // Moyenne générale
        if (averageScore != null) ...[
          Card(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text(
                        'Moyenne générale',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        averageScore!.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  _buildScoreIndicator(context, averageScore!),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  static const double _barMaxHeight = 160;

  Widget _buildAttendanceChart(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Légende
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
            // Barres empilées (une barre par semaine)
            SizedBox(
              height: _barMaxHeight + 36,
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
                        onTap: () => _showWeekDetail(context, label, present, absent, late, excused, total, isPartialWeek),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // Barre empilée verticale
                            SizedBox(
                              height: _barMaxHeight,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (total > 0) ...[
                                    _stackSegment(_barMaxHeight * (excused / total).clamp(0.0, 1.0), Colors.blue),
                                    _stackSegment(_barMaxHeight * (late / total).clamp(0.0, 1.0), Colors.orange),
                                    _stackSegment(_barMaxHeight * (absent / total).clamp(0.0, 1.0), Colors.red),
                                    _stackSegment(_barMaxHeight * (present / total).clamp(0.0, 1.0), Colors.green),
                                  ] else
                                    Container(
                                      height: _barMaxHeight,
                                      decoration: BoxDecoration(
                                        color: (isDark ? Colors.grey : Colors.grey[300])!,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
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
                    ),
                  );
                }).toList(),
              ),
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

  Widget _stackSegment(double heightPx, Color color) {
    if (heightPx <= 0) return const SizedBox.shrink();
    return SizedBox(
      height: heightPx,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

  Widget _detailRow(BuildContext context, String label, int value, Color color) {
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

  Widget _buildGradesChart(BuildContext context) {
    if (gradesData.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Aucune note disponible',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    // Grouper par matière
    final Map<String, List<double>> gradesBySubject = {};
    for (var grade in gradesData) {
      final subject = grade['subject']?['name'] ?? 'Autre';
      final score = grade['score'] ?? 0.0;
      final totalPoints = grade['total_points'] ?? 1.0;
      final percentage = (score / totalPoints) * 20; // Convertir sur 20
      
      if (!gradesBySubject.containsKey(subject)) {
        gradesBySubject[subject] = [];
      }
      gradesBySubject[subject]!.add(percentage);
    }

    final theme = Theme.of(context);
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: gradesBySubject.entries.map((entry) {
            final subject = entry.key;
            final grades = entry.value;
            final average = grades.reduce((a, b) => a + b) / grades.length;
            final color = average >= 10 ? Colors.green : Colors.red;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      subject,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: LinearProgressIndicator(
                      value: average / 20,
                      backgroundColor: surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    average.toStringAsFixed(1),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
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

  Widget _buildScoreIndicator(BuildContext context, double score) {
    final theme = Theme.of(context);
    final percentage = (score / 20) * 100;
    Color color;
    if (percentage >= 75) {
      color = Colors.green;
    } else if (percentage >= 50) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: percentage / 100,
              strokeWidth: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
