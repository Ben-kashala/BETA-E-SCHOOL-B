import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../core/network/api_service.dart';

class TeacherAssignmentDetailPage extends StatefulWidget {
  final int assignmentId;

  const TeacherAssignmentDetailPage({super.key, required this.assignmentId});

  @override
  State<TeacherAssignmentDetailPage> createState() =>
      _TeacherAssignmentDetailPageState();
}

class _TeacherAssignmentDetailPageState
    extends State<TeacherAssignmentDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _assignment;
  List<dynamic> _questions = [];
  List<dynamic> _submissions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        ApiService().get('/api/elearning/assignments/${widget.assignmentId}/'),
        ApiService().get(
            '/api/elearning/assignments/${widget.assignmentId}/questions/'),
        ApiService().get(
          '/api/elearning/submissions/',
          queryParameters: {'assignment': widget.assignmentId},
        ),
      ]);
      final assignment = Map<String, dynamic>.from(responses[0].data as Map);
      final qData = responses[1].data;
      final sData = responses[2].data;

      setState(() {
        _assignment = assignment;
        _questions = qData is List ? qData : (qData['results'] ?? []);
        _submissions = sData is List ? sData : (sData['results'] ?? []);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assignment = null;
        _questions = [];
        _submissions = [];
        _isLoading = false;
      });
    }
  }

  Future<void> _openQuestionForm({Map<String, dynamic>? question}) async {
    final isEditing = question != null;
    final questionCtrl =
        TextEditingController(text: '${question?['question_text'] ?? ''}');
    final pointsCtrl =
        TextEditingController(text: '${question?['points'] ?? '1'}');
    final orderCtrl =
        TextEditingController(text: '${question?['order'] ?? '0'}');
    final answerCtrl =
        TextEditingController(text: '${question?['correct_answer'] ?? ''}');
    final optionACtrl =
        TextEditingController(text: '${question?['option_a'] ?? ''}');
    final optionBCtrl =
        TextEditingController(text: '${question?['option_b'] ?? ''}');
    final optionCCtrl =
        TextEditingController(text: '${question?['option_c'] ?? ''}');
    final optionDCtrl =
        TextEditingController(text: '${question?['option_d'] ?? ''}');
    String type = '${question?['question_type'] ?? 'SINGLE_CHOICE'}';
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isChoice = type == 'SINGLE_CHOICE' || type == 'MULTIPLE_CHOICE';
          return AlertDialog(
            title:
                Text(isEditing ? 'Modifier la question' : 'Nouvelle question'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: const [
                        DropdownMenuItem(
                            value: 'SINGLE_CHOICE',
                            child: Text('Choix unique')),
                        DropdownMenuItem(
                            value: 'MULTIPLE_CHOICE',
                            child: Text('Choix multiple')),
                        DropdownMenuItem(value: 'TEXT', child: Text('Texte')),
                        DropdownMenuItem(
                            value: 'NUMBER', child: Text('Nombre')),
                      ],
                      onChanged: (v) =>
                          setLocal(() => type = v ?? 'SINGLE_CHOICE'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: questionCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Question'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pointsCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Points'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: orderCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Ordre'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (isChoice) ...[
                      TextField(
                        controller: optionACtrl,
                        decoration:
                            const InputDecoration(labelText: 'Option A'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: optionBCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Option B'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: optionCCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Option C'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: optionDCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Option D'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: answerCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Réponse correcte'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (questionCtrl.text.trim().isEmpty) {
                          return;
                        }
                        final payload = <String, dynamic>{
                          'question_text': questionCtrl.text.trim(),
                          'question_type': type,
                          'points': double.tryParse(
                                pointsCtrl.text.trim().replaceAll(',', '.'),
                              ) ??
                              1,
                          'order': int.tryParse(orderCtrl.text.trim()) ?? 0,
                          'correct_answer': answerCtrl.text.trim(),
                        };
                        if (isChoice) {
                          payload['option_a'] = optionACtrl.text.trim();
                          payload['option_b'] = optionBCtrl.text.trim();
                          payload['option_c'] = optionCCtrl.text.trim();
                          payload['option_d'] = optionDCtrl.text.trim();
                        }

                        setLocal(() => saving = true);
                        try {
                          if (isEditing) {
                            await ApiService().patch(
                              '/api/elearning/assignment-questions/${question['id']}/',
                              data: payload,
                            );
                          } else {
                            await ApiService().post(
                              '/api/elearning/assignments/${widget.assignmentId}/questions/',
                              data: payload,
                            );
                          }
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          await _loadAll();
                        } catch (_) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Impossible d’enregistrer la question.')),
                            );
                          }
                        } finally {
                          if (ctx.mounted) setLocal(() => saving = false);
                        }
                      },
                child: Text(saving ? '...' : 'Enregistrer'),
              ),
            ],
          );
        },
      ),
    );

    questionCtrl.dispose();
    pointsCtrl.dispose();
    orderCtrl.dispose();
    answerCtrl.dispose();
    optionACtrl.dispose();
    optionBCtrl.dispose();
    optionCCtrl.dispose();
    optionDCtrl.dispose();
  }

  Future<void> _deleteQuestion(int questionId) async {
    try {
      await ApiService()
          .delete('/api/elearning/assignment-questions/$questionId/');
      if (!mounted) return;
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible.')),
      );
    }
  }

  Future<void> _gradeSubmission(
    Map<String, dynamic> submission, {
    int? currentIndex,
  }) async {
    final feedbackCtrl =
        TextEditingController(text: '${submission['feedback'] ?? ''}');
    final scoreCtrl =
        TextEditingController(text: '${submission['score'] ?? ''}');
    final answerGrades =
        (submission['answer_grades'] as Map?)?.cast<String, dynamic>() ?? {};
    final answersMap = <dynamic, dynamic>{};
    try {
      final raw = submission['submission_text'];
      if (raw is String && raw.trim().isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map) {
          answersMap.addAll(parsed.cast<String, dynamic>());
        }
      }
    } catch (_) {}

    final pointsByQuestion = <int, TextEditingController>{};
    final fbByQuestion = <int, TextEditingController>{};
    for (final q in _questions) {
      final qid = q['id'] as int;
      final existing = answerGrades['$qid'];
      pointsByQuestion[qid] = TextEditingController(
        text: '${existing?['points_earned'] ?? 0}',
      );
      fbByQuestion[qid] = TextEditingController(
        text: '${existing?['teacher_feedback'] ?? ''}',
      );
    }
    bool saving = false;

    final hasNext =
        currentIndex != null && currentIndex + 1 < _submissions.length;
    final nextSubmissionId =
        hasNext ? _submissions[currentIndex + 1]['id'] : null;

    Future<void> submitGrade({
      required BuildContext ctx,
      required StateSetter setLocal,
      required bool openNext,
    }) async {
      final payload = <String, dynamic>{
        'feedback': feedbackCtrl.text.trim(),
      };
      if (_questions.isEmpty) {
        payload['score'] = double.tryParse(
              scoreCtrl.text.trim().replaceAll(',', '.'),
            ) ??
            0;
      } else {
        payload['answers'] = _questions.map((q) {
          final qid = q['id'] as int;
          return {
            'question_id': qid,
            'points_earned': double.tryParse(
                  pointsByQuestion[qid]!.text.trim().replaceAll(',', '.'),
                ) ??
                0,
            'teacher_feedback': fbByQuestion[qid]!.text.trim(),
          };
        }).toList();
      }

      setLocal(() => saving = true);
      try {
        await ApiService().post(
          '/api/elearning/submissions/${submission['id']}/grade/',
          data: payload,
        );
        if (!ctx.mounted) {
          return;
        }
        Navigator.of(ctx).pop();
        if (!mounted) {
          return;
        }
        await _loadAll();
        if (!mounted || !openNext || nextSubmissionId == null) {
          return;
        }
        final nextIndex = _submissions.indexWhere(
          (s) => (s as Map)['id'] == nextSubmissionId,
        );
        if (nextIndex != -1) {
          final nextSubmission =
              Map<String, dynamic>.from(_submissions[nextIndex] as Map);
          await _gradeSubmission(nextSubmission, currentIndex: nextIndex);
        }
      } catch (_) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Notation impossible pour cette soumission.'),
            ),
          );
        }
      } finally {
        if (ctx.mounted) {
          setLocal(() => saving = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          double maxPointsForQuestion(dynamic q) {
            return double.tryParse(
                    '${q['points'] ?? 0}'.replaceAll(',', '.')) ??
                0;
          }

          final maxTotalScore = double.tryParse(
                '${_assignment?['total_points'] ?? 20}'.replaceAll(',', '.'),
              ) ??
              20;

          void applyAllMax() {
            for (final q in _questions) {
              final qid = q['id'] as int;
              pointsByQuestion[qid]?.text = maxPointsForQuestion(q).toString();
            }
          }

          void applyAllZero() {
            for (final q in _questions) {
              final qid = q['id'] as int;
              pointsByQuestion[qid]?.text = '0';
            }
          }

          void applyAutoFromExisting() {
            for (final q in _questions) {
              final qid = q['id'] as int;
              final existing = answerGrades['$qid'];
              pointsByQuestion[qid]?.text =
                  '${existing?['points_earned'] ?? 0}';
              fbByQuestion[qid]?.text =
                  '${existing?['teacher_feedback'] ?? ''}';
            }
          }

          void applyCommentToAll(String message) {
            for (final q in _questions) {
              final qid = q['id'] as int;
              fbByQuestion[qid]?.text = message;
            }
          }

          final pos = (currentIndex ?? 0) + 1;
          final total = _submissions.length;
          return AlertDialog(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Noter la soumission'),
                const SizedBox(height: 4),
                Text(
                  '$pos / $total',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Élève: ${submission['student_name'] ?? submission['student_id'] ?? '-'}',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    if (_questions.isEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () =>
                                setLocal(() => scoreCtrl.text = '0'),
                            child: const Text('Score 0'),
                          ),
                          OutlinedButton(
                            onPressed: () => setLocal(() =>
                                scoreCtrl.text = maxTotalScore.toString()),
                            child: const Text('Score max'),
                          ),
                          OutlinedButton(
                            onPressed: () => setLocal(() => scoreCtrl.text =
                                (maxTotalScore / 2).toStringAsFixed(1)),
                            child: const Text('Score 50%'),
                          ),
                        ],
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => setLocal(applyAutoFromExisting),
                            child: const Text('Auto (existant)'),
                          ),
                          OutlinedButton(
                            onPressed: () => setLocal(applyAllMax),
                            child: const Text('Tout au max'),
                          ),
                          OutlinedButton(
                            onPressed: () => setLocal(applyAllZero),
                            child: const Text('Tout à 0'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                setLocal(() => applyCommentToAll('Correct.')),
                            child: const Text('Commentaire: Correct'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                setLocal(() => applyCommentToAll('Partiel.')),
                            child: const Text('Commentaire: Partiel'),
                          ),
                          OutlinedButton(
                            onPressed: () =>
                                setLocal(() => applyCommentToAll('À revoir.')),
                            child: const Text('Commentaire: À revoir'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (_questions.isEmpty)
                      TextField(
                        controller: scoreCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Note globale',
                          hintText: 'Ex: 15.5',
                        ),
                      )
                    else
                      ..._questions.map((q) {
                        final qid = q['id'] as int;
                        final answer =
                            answersMap['$qid'] ?? answersMap[qid] ?? '(vide)';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${q['question_text']}'),
                                const SizedBox(height: 4),
                                Text('Réponse: $answer'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: pointsByQuestion[qid],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Points',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: fbByQuestion[qid],
                                        decoration: const InputDecoration(
                                          labelText: 'Commentaire',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                    TextField(
                      controller: feedbackCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Commentaire général',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuler'),
              ),
              if (hasNext)
                OutlinedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          await submitGrade(
                            ctx: ctx,
                            setLocal: setLocal,
                            openNext: true,
                          );
                        },
                  child: Text(saving ? '...' : 'Sauver et suivant'),
                ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        await submitGrade(
                          ctx: ctx,
                          setLocal: setLocal,
                          openNext: false,
                        );
                      },
                child: Text(saving ? '...' : 'Enregistrer'),
              ),
            ],
          );
        },
      ),
    );

    feedbackCtrl.dispose();
    scoreCtrl.dispose();
    for (final c in pointsByQuestion.values) {
      c.dispose();
    }
    for (final c in fbByQuestion.values) {
      c.dispose();
    }
  }

  Future<void> _allowResubmit(int submissionId) async {
    try {
      await ApiService()
          .post('/api/elearning/submissions/$submissionId/allow_resubmit/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouvelle soumission autorisée.')),
      );
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action impossible.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail devoir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignment == null
              ? const Center(child: Text('Impossible de charger ce devoir.'))
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _assignment!['title']?.toString() ?? 'Devoir',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(_assignment!['description']?.toString() ??
                                  ''),
                              const SizedBox(height: 8),
                              Text(
                                'Statut: ${_assignment!['is_published'] == true ? 'Publié' : 'Brouillon'}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Questions (${_questions.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: () => _openQuestionForm(),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_questions.isEmpty)
                        const Card(
                            child: ListTile(title: Text('Aucune question.')))
                      else
                        ..._questions.map((q) => Card(
                              child: ListTile(
                                title: Text(q['question_text']?.toString() ??
                                    'Question'),
                                subtitle: Text(
                                  '${q['question_type']} • ${q['points'] ?? 0} pts',
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _openQuestionForm(
                                        question:
                                            Map<String, dynamic>.from(q as Map),
                                      );
                                    } else if (value == 'delete') {
                                      await _deleteQuestion(q['id'] as int);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'edit', child: Text('Modifier')),
                                    PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Supprimer')),
                                  ],
                                ),
                              ),
                            )),
                      const SizedBox(height: 12),
                      Text(
                        'Soumissions (${_submissions.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_submissions.isEmpty)
                        const Card(
                            child: ListTile(title: Text('Aucune soumission.')))
                      else
                        ..._submissions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final sub =
                              Map<String, dynamic>.from(entry.value as Map);
                          return Card(
                            child: ListTile(
                              title: Text(
                                  '${sub['student_name'] ?? sub['student_id'] ?? 'Élève'}'),
                              subtitle: Text(
                                'Statut: ${sub['status'] ?? '-'}  •  Score: ${sub['score'] ?? '-'}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'grade') {
                                    await _gradeSubmission(
                                      sub,
                                      currentIndex: index,
                                    );
                                  } else if (value == 'resubmit') {
                                    await _allowResubmit(sub['id'] as int);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'grade', child: Text('Noter')),
                                  PopupMenuItem(
                                    value: 'resubmit',
                                    child:
                                        Text('Autoriser nouvelle soumission'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
