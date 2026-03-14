import 'package:flutter/material.dart';
import '../../../../core/network/api_service.dart';

class TeacherQuizDetailPage extends StatefulWidget {
  final int quizId;

  const TeacherQuizDetailPage({super.key, required this.quizId});

  @override
  State<TeacherQuizDetailPage> createState() => _TeacherQuizDetailPageState();
}

class _TeacherQuizDetailPageState extends State<TeacherQuizDetailPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _quiz;
  List<dynamic> _questions = [];
  List<dynamic> _attempts = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        ApiService().get('/api/elearning/quizzes/${widget.quizId}/'),
        ApiService().get('/api/elearning/quizzes/${widget.quizId}/questions/'),
        ApiService().get(
          '/api/elearning/quiz-attempts/',
          queryParameters: {'quiz': widget.quizId},
        ),
      ]);
      final quiz = Map<String, dynamic>.from(responses[0].data as Map);
      final qData = responses[1].data;
      final aData = responses[2].data;
      setState(() {
        _quiz = quiz;
        _questions = qData is List ? qData : (qData['results'] ?? []);
        _attempts = aData is List ? aData : (aData['results'] ?? []);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _quiz = null;
        _questions = [];
        _attempts = [];
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
          final isChoice = type == 'SINGLE_CHOICE' ||
              type == 'MULTIPLE_CHOICE' ||
              type == 'TRUE_FALSE';
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
                        DropdownMenuItem(
                            value: 'TRUE_FALSE', child: Text('Vrai/Faux')),
                        DropdownMenuItem(
                            value: 'SHORT_ANSWER',
                            child: Text('Réponse courte')),
                        DropdownMenuItem(
                            value: 'ESSAY', child: Text('Dissertation')),
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
                              '/api/elearning/quiz-questions/${question['id']}/',
                              data: payload,
                            );
                          } else {
                            await ApiService().post(
                              '/api/elearning/quizzes/${widget.quizId}/questions/',
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
      await ApiService().delete('/api/elearning/quiz-questions/$questionId/');
      if (!mounted) return;
      await _loadAll();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible.')),
      );
    }
  }

  Future<void> _gradeAttempt(
    Map<String, dynamic> attempt, {
    int? currentIndex,
  }) async {
    final answers = (attempt['answers'] as List?) ?? [];
    final pointsCtrls = <int, TextEditingController>{};
    final feedbackCtrls = <int, TextEditingController>{};
    for (final a in answers) {
      final id = a['id'] as int;
      pointsCtrls[id] =
          TextEditingController(text: '${a['points_earned'] ?? 0}');
      feedbackCtrls[id] =
          TextEditingController(text: '${a['teacher_feedback'] ?? ''}');
    }
    bool saving = false;

    final hasNext = currentIndex != null && currentIndex + 1 < _attempts.length;
    final nextAttemptId = hasNext ? _attempts[currentIndex + 1]['id'] : null;

    Future<void> submitGrade({
      required BuildContext ctx,
      required StateSetter setLocal,
      required bool openNext,
    }) async {
      final payload = {
        'answers': answers.map((a) {
          final id = a['id'] as int;
          return {
            'id': id,
            'points_earned': double.tryParse(
                  pointsCtrls[id]!.text.trim().replaceAll(',', '.'),
                ) ??
                a['points_earned'] ??
                0,
            'teacher_feedback': feedbackCtrls[id]!.text.trim(),
          };
        }).toList(),
      };
      setLocal(() => saving = true);
      try {
        await ApiService().post(
          '/api/elearning/quiz-attempts/${attempt['id']}/teacher_grade/',
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
        if (!mounted || !openNext || nextAttemptId == null) {
          return;
        }
        final nextIndex = _attempts.indexWhere(
          (a) => (a as Map)['id'] == nextAttemptId,
        );
        if (nextIndex != -1) {
          final nextAttempt =
              Map<String, dynamic>.from(_attempts[nextIndex] as Map);
          await _gradeAttempt(nextAttempt, currentIndex: nextIndex);
        }
      } catch (_) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Notation impossible pour cette tentative.'),
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
          double maxPointsForAnswer(Map<String, dynamic> answer) {
            final questionId = answer['question'];
            for (final q in _questions) {
              if (q['id'] == questionId) {
                return double.tryParse(
                        '${q['points'] ?? 0}'.replaceAll(',', '.')) ??
                    0;
              }
            }
            return 0;
          }

          void applyAutoCurrent() {
            for (final a in answers) {
              final id = a['id'] as int;
              pointsCtrls[id]?.text = '${a['points_earned'] ?? 0}';
              feedbackCtrls[id]?.text = '${a['teacher_feedback'] ?? ''}';
            }
          }

          void applyAllMax() {
            for (final a in answers) {
              final id = a['id'] as int;
              final maxPts = maxPointsForAnswer(Map<String, dynamic>.from(a));
              pointsCtrls[id]?.text = maxPts.toString();
            }
          }

          void applyAllZero() {
            for (final a in answers) {
              final id = a['id'] as int;
              pointsCtrls[id]?.text = '0';
            }
          }

          void applyCommentToAll(String message) {
            for (final a in answers) {
              final id = a['id'] as int;
              feedbackCtrls[id]?.text = message;
            }
          }

          final pos = (currentIndex ?? 0) + 1;
          final total = _attempts.length;
          return AlertDialog(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Noter la tentative'),
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
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Élève: ${attempt['student_name'] ?? attempt['student_id'] ?? '-'}',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    if (answers.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => setLocal(applyAutoCurrent),
                            child: const Text('Auto (actuel)'),
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
                    if (answers.isNotEmpty) const SizedBox(height: 10),
                    if (answers.isEmpty)
                      const Text('Aucune réponse disponible.')
                    else
                      ...answers.map((a) {
                        final id = a['id'] as int;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${a['question_text'] ?? 'Question'}'),
                                const SizedBox(height: 4),
                                Text(
                                    'Réponse: ${a['answer_text'] ?? '(vide)'}'),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: pointsCtrls[id],
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Points',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: feedbackCtrls[id],
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

    for (final c in pointsCtrls.values) {
      c.dispose();
    }
    for (final c in feedbackCtrls.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail quiz'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _quiz == null
              ? const Center(child: Text('Impossible de charger ce quiz.'))
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
                                _quiz!['title']?.toString() ?? 'Quiz',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(_quiz!['description']?.toString() ?? ''),
                              const SizedBox(height: 8),
                              Text(
                                'Statut: ${_quiz!['is_published'] == true ? 'Publié' : 'Brouillon'}',
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
                        'Tentatives (${_attempts.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_attempts.isEmpty)
                        const Card(
                            child: ListTile(title: Text('Aucune tentative.')))
                      else
                        ..._attempts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final attempt =
                              Map<String, dynamic>.from(entry.value as Map);
                          return Card(
                            child: ListTile(
                              title: Text(
                                  '${attempt['student_name'] ?? attempt['student_id'] ?? 'Élève'}'),
                              subtitle: Text(
                                'Score: ${attempt['score'] ?? '-'}  •  Réussi: ${attempt['is_passed'] == true ? 'Oui' : 'Non'}',
                              ),
                              trailing: const Icon(Icons.rate_review_outlined),
                              onTap: () =>
                                  _gradeAttempt(attempt, currentIndex: index),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
