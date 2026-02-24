import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/widgets/form_builder.dart';

class TeacherQuizCreatePage extends ConsumerStatefulWidget {
  const TeacherQuizCreatePage({super.key});

  @override
  ConsumerState<TeacherQuizCreatePage> createState() => _TeacherQuizCreatePageState();
}

class _TeacherQuizCreatePageState extends ConsumerState<TeacherQuizCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  List<dynamic> _subjects = [];
  List<dynamic> _classes = [];
  int? _selectedSubjectId;
  int? _selectedClassId;
  DateTime? _startDate;
  DateTime? _endDate;
  int _totalPoints = 20;
  int? _timeLimit;
  bool _isPublished = false;
  bool _allowMultipleAttempts = false;
  int _maxAttempts = 1;
  bool _isLoading = false;
  bool _dataLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _dataLoading = true);
    try {
      final [subjectsRes, classesRes] = await Future.wait([
        ApiService().get('/api/schools/subjects/'),
        ApiService().get('/api/schools/classes/'),
      ]);

      setState(() {
        _subjects = subjectsRes.data is List 
            ? subjectsRes.data 
            : (subjectsRes.data['results'] ?? []);
        _classes = classesRes.data is List 
            ? classesRes.data 
            : (classesRes.data['results'] ?? []);
        _dataLoading = false;
      });
    } catch (e) {
      setState(() => _dataLoading = false);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSubjectId == null || _selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une matière et une classe')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final currentYear = DateTime.now().year;
      final academicYear = '$currentYear-${currentYear + 1}';

      await ApiService().post('/api/elearning/quizzes/', data: {
        'title': _titleController.text,
        'description': _descriptionController.text,
        'subject': _selectedSubjectId,
        'school_class': _selectedClassId,
        'academic_year': academicYear,
        'start_date': _startDate?.toIso8601String(),
        'end_date': _endDate?.toIso8601String(),
        'total_points': _totalPoints,
        'time_limit': _timeLimit,
        'is_published': _isPublished,
        'allow_multiple_attempts': _allowMultipleAttempts,
        'max_attempts': _maxAttempts,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quiz créé avec succès')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dataLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nouveau Quiz')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau Quiz'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormBuilder.buildTextField(
                label: 'Titre',
                controller: _titleController,
                required: true,
              ),
              FormBuilder.buildTextField(
                label: 'Description',
                controller: _descriptionController,
                maxLines: 3,
              ),
              FormBuilder.buildDropdown<int>(
                label: 'Matière',
                value: _selectedSubjectId,
                items: _subjects.map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,
                  child: Text(s['name'] ?? 'Matière'),
                )).toList(),
                onChanged: (value) => setState(() => _selectedSubjectId = value),
                required: true,
              ),
              FormBuilder.buildDropdown<int>(
                label: 'Classe',
                value: _selectedClassId,
                items: _classes.map((c) => DropdownMenuItem<int>(
                  value: c['id'] as int,
                  child: Text(c['name'] ?? 'Classe'),
                )).toList(),
                onChanged: (value) => setState(() => _selectedClassId = value),
                required: true,
              ),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _startDate = date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date de début *',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(_startDate != null 
                      ? DateFormat('dd/MM/yyyy').format(_startDate!)
                      : 'Sélectionner une date'),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? (_startDate ?? DateTime.now()),
                    firstDate: _startDate ?? DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() => _endDate = date);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date de fin *',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(_endDate != null 
                      ? DateFormat('dd/MM/yyyy').format(_endDate!)
                      : 'Sélectionner une date'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _totalPoints.toString(),
                decoration: const InputDecoration(
                  labelText: 'Points totaux',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _totalPoints = int.tryParse(value) ?? 20;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _timeLimit?.toString(),
                decoration: const InputDecoration(
                  labelText: 'Durée (minutes, optionnel)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _timeLimit = int.tryParse(value);
                },
              ),
              const SizedBox(height: 16),
              FormBuilder.buildSwitch(
                label: 'Publier immédiatement',
                value: _isPublished,
                onChanged: (value) => setState(() => _isPublished = value),
              ),
              FormBuilder.buildSwitch(
                label: 'Autoriser plusieurs tentatives',
                value: _allowMultipleAttempts,
                onChanged: (value) => setState(() => _allowMultipleAttempts = value),
              ),
              if (_allowMultipleAttempts) ...[
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _maxAttempts.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Nombre maximum de tentatives',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    _maxAttempts = int.tryParse(value) ?? 1;
                  },
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Créer le quiz'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
