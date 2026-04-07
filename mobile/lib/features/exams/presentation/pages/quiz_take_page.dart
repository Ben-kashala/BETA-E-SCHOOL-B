import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../../../core/network/api_service.dart';
import '../../../../core/theme/app_theme.dart';

class QuizTakePage extends ConsumerStatefulWidget {
  final int quizId;
  final int attemptId;

  const QuizTakePage({
    super.key,
    required this.quizId,
    required this.attemptId,
  });

  @override
  ConsumerState<QuizTakePage> createState() => _QuizTakePageState();
}

/// Réponses API JSON : bool / 0 / 1 / "true" — évite les incohérences avec RadioListTile<bool>.
bool? _parseBoolAnswer(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
  }
  return null;
}

String _answerString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  return v.toString();
}

class _QuizTakePageState extends ConsumerState<QuizTakePage> {
  Map<String, dynamic>? _quiz;
  List<dynamic> _questions = [];
  final Map<int, dynamic> _answers = {};
  int _currentQuestionIndex = 0;
  bool _isLoading = true;
  bool _isSubmitting = false;
  int _remainingSeconds = 0;
  Timer? _timer;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuiz() async {
    setState(() => _isLoading = true);
    try {
      // Charger le quiz
      final quizResponse = await ApiService().get('/api/elearning/quizzes/${widget.quizId}/');
      setState(() {
        _quiz = quizResponse.data as Map<String, dynamic>;
      });

      // Charger les questions
      final questionsResponse = await ApiService().get('/api/elearning/quizzes/${widget.quizId}/questions/');
      setState(() {
        _questions = questionsResponse.data is List 
            ? questionsResponse.data 
            : (questionsResponse.data['results'] ?? []);
      });

      // Démarrer le timer si nécessaire
      final timeLimit = _quiz?['time_limit'];
      if (timeLimit != null && timeLimit > 0) {
        _remainingSeconds = timeLimit * 60; // Convertir en secondes
        _startTime = DateTime.now();
        _startTimer();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _submitQuiz(autoSubmit: true);
      }
    });
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _submitQuiz({bool autoSubmit = false}) async {
    if (autoSubmit) {
      // Afficher une alerte si auto-submit
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Temps écoulé'),
            content: const Text('Le temps imparti est écoulé. Votre quiz sera soumis automatiquement.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    setState(() => _isSubmitting = true);
    _timer?.cancel();

    try {
      // Préparer les réponses
      final answersList = _answers.entries.map((entry) {
        return {
          'question': entry.key,
          'answer': entry.value,
        };
      }).toList();

      // Soumettre le quiz
      await ApiService().post(
        '/api/elearning/quiz-attempts/${widget.attemptId}/submit/',
        data: {
          'answers': answersList,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quiz soumis avec succès')),
        );
        context.go('/exams/${widget.quizId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la soumission: $e')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showSubmitConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Soumettre le quiz'),
        content: const Text('Êtes-vous sûr de vouloir soumettre votre quiz ? Vous ne pourrez plus modifier vos réponses.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _submitQuiz();
            },
            child: const Text('Soumettre'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionWidget(dynamic question) {
    final questionId = question['id'] as int;
    final questionType = question['question_type'] as String? ?? 'TEXT';
    final questionText = question['question_text'] ?? 'Question';
    final currentAnswer = _answers[questionId];

    switch (questionType) {
      case 'SINGLE_CHOICE':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              questionText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...['A', 'B', 'C', 'D'].map((option) {
              final optionKey = 'option_${option.toLowerCase()}';
              final optionValue = question[optionKey];
              if (optionValue == null || optionValue.toString().isEmpty) {
                return const SizedBox.shrink();
              }
              return RadioListTile<String>(
                title: Text(optionValue),
                value: option,
                groupValue: currentAnswer == null ? null : _answerString(currentAnswer),
                onChanged: (value) {
                  setState(() {
                    _answers[questionId] = value!;
                  });
                },
              );
            }),
          ],
        );

      case 'MULTIPLE_CHOICE':
        final caStr = _answerString(currentAnswer);
        final selectedAnswers =
            caStr.split(',').where((a) => a.isNotEmpty).toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              questionText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...['A', 'B', 'C', 'D'].map((option) {
              final optionKey = 'option_${option.toLowerCase()}';
              final optionValue = question[optionKey];
              if (optionValue == null || optionValue.toString().isEmpty) {
                return const SizedBox.shrink();
              }
              return CheckboxListTile(
                title: Text(optionValue),
                value: selectedAnswers.contains(option),
                onChanged: (checked) {
                  setState(() {
                    final newAnswers = selectedAnswers.toSet();
                    if (checked == true) {
                      newAnswers.add(option);
                    } else {
                      newAnswers.remove(option);
                    }
                    _answers[questionId] = newAnswers.join(',');
                  });
                },
              );
            }),
          ],
        );

      case 'TRUE_FALSE':
        final tfGroup = _parseBoolAnswer(currentAnswer);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              questionText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            RadioListTile<bool>(
              title: const Text('Vrai'),
              value: true,
              groupValue: tfGroup,
              onChanged: (value) {
                setState(() {
                  _answers[questionId] = true;
                });
              },
            ),
            RadioListTile<bool>(
              title: const Text('Faux'),
              value: false,
              groupValue: tfGroup,
              onChanged: (value) {
                setState(() {
                  _answers[questionId] = false;
                });
              },
            ),
          ],
        );

      case 'NUMBER':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              questionText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Entrez un nombre',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(
                text: currentAnswer?.toString() ?? '',
              ),
              onChanged: (value) {
                _answers[questionId] = value;
              },
            ),
          ],
        );

      default: // TEXT, SHORT_ANSWER, ESSAY
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              questionText,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              maxLines: questionType == 'ESSAY' ? 10 : 3,
              decoration: InputDecoration(
                hintText: questionType == 'ESSAY' 
                    ? 'Rédigez votre réponse...'
                    : 'Entrez votre réponse',
                border: const OutlineInputBorder(),
              ),
              controller: TextEditingController(
                text: currentAnswer?.toString() ?? '',
              ),
              onChanged: (value) {
                _answers[questionId] = value;
              },
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quiz')),
        body: const Center(child: Text('Aucune question disponible')),
      );
    }

    final currentQuestion = _questions[_currentQuestionIndex];
    final totalQuestions = _questions.length;
    final progress = (_currentQuestionIndex + 1) / totalQuestions;

    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Quitter le quiz'),
            content: const Text('Êtes-vous sûr de vouloir quitter ? Votre progression sera perdue.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Quitter'),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_quiz?['title'] ?? 'Quiz'),
          actions: [
            // Timer
            if (_remainingSeconds > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _remainingSeconds < 300 ? Colors.red : Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatTime(_remainingSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Barre de progression
            LinearProgressIndicator(value: progress),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${_currentQuestionIndex + 1} sur $totalQuestions'),
                  Text('${(_answers.length / totalQuestions * 100).toStringAsFixed(0)}% complété'),
                ],
              ),
            ),
            // Question actuelle
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: _buildQuestionWidget(currentQuestion),
              ),
            ),
            // Navigation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: _currentQuestionIndex == 0 ? null : () {
                      setState(() {
                        _currentQuestionIndex--;
                      });
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Précédent'),
                  ),
                  if (_currentQuestionIndex < totalQuestions - 1)
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentQuestionIndex++;
                        });
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Suivant'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _showSubmitConfirmation,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isSubmitting ? 'Soumission...' : 'Soumettre'),
                    ),
                ],
              ),
            ),
          ],
        ),
        // Liste des questions (drawer)
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: Theme.of(context).primaryColor),
                child: const Text(
                  'Questions',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
              ..._questions.asMap().entries.map((entry) {
                final index = entry.key;
                final question = entry.value;
                final questionId = question['id'] as int;
                final isAnswered = _answers.containsKey(questionId);
                final isCurrent = index == _currentQuestionIndex;
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? AppTheme.avatarBackgroundColor
                        : isAnswered
                            ? Colors.green
                            : Colors.grey,
                    foregroundColor: isCurrent
                        ? AppTheme.onAvatarBackgroundColor
                        : Colors.white,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: isCurrent
                            ? AppTheme.onAvatarBackgroundColor
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  title: Text(
                    question['question_text'] ?? 'Question ${index + 1}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isAnswered ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () {
                    setState(() {
                      _currentQuestionIndex = index;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
