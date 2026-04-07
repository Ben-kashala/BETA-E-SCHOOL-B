import 'package:flutter/material.dart';

import 'attendance_week_chart_widget.dart';

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
          AttendanceWeekChartWidget(attendanceData: attendanceData),
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
      final dynamic subj = grade['subject'];
      final String subject = subj is Map
          ? (subj['name'] ?? 'Autre').toString()
          : (subj?.toString() ?? 'Autre');
      final score = (grade['score'] is num)
          ? (grade['score'] as num).toDouble()
          : double.tryParse('${grade['score'] ?? 0}') ?? 0.0;
      final totalPoints = (grade['total_points'] is num)
          ? (grade['total_points'] as num).toDouble()
          : double.tryParse('${grade['total_points'] ?? 1}') ?? 1.0;
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
