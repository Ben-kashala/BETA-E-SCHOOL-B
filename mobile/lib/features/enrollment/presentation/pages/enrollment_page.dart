import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/sync_service.dart';

class EnrollmentPage extends ConsumerStatefulWidget {
  const EnrollmentPage({super.key});

  @override
  ConsumerState<EnrollmentPage> createState() => _EnrollmentPageState();
}

class _EnrollmentPageState extends ConsumerState<EnrollmentPage> {
  final _formKey = GlobalKey<FormState>();
  final _studentNameController = TextEditingController();
  final _studentSurnameController = TextEditingController();
  final _studentMiddleNameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  
  String? _selectedSchool;
  String? _selectedClass;
  String? _selectedGender;
  DateTime? _birthDate;
  String? _selectedDocumentPath;
  bool _isSubmitting = false;
  
  List<dynamic> _schools = [];
  List<dynamic> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  @override
  void dispose() {
    _studentNameController.dispose();
    _studentSurnameController.dispose();
    _studentMiddleNameController.dispose();
    _birthDateController.dispose();
    _placeOfBirthController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _parentNameController.dispose();
    _motherNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSchools() async {
    try {
      final response = await ApiService().get('/api/schools/');
      setState(() {
        _schools = response.data as List<dynamic>;
      });
    } catch (e) {
      // Gérer l'erreur
    }
  }

  Future<void> _loadClasses(String schoolId) async {
    try {
      final response = await ApiService().get('/api/schools/classes/', queryParameters: {
        'school': schoolId,
      });
      setState(() {
        _classes = response.data as List<dynamic>;
      });
    } catch (e) {
      // Gérer l'erreur
    }
  }

  Future<void> _selectDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null) {
      setState(() {
        _selectedDocumentPath = result.files.single.path;
      });
    }
  }

  Future<void> _selectBirthDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (date != null) {
      setState(() {
        _birthDate = date;
        _birthDateController.text = '${date.day}/${date.month}/${date.year}';
      });
    }
  }

  Future<void> _submitEnrollment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final now = DateTime.now();
      final academicYear = '${now.year}-${now.year + 1}';
      final data = {
        'academic_year': academicYear,
        'first_name': _studentNameController.text.trim(),
        'last_name': _studentSurnameController.text.trim(),
        'middle_name': _studentMiddleNameController.text.trim().isEmpty ? null : _studentMiddleNameController.text.trim(),
        'date_of_birth': _birthDate?.toIso8601String(),
        'gender': _selectedGender,
        'place_of_birth': _placeOfBirthController.text.trim().isEmpty ? '' : _placeOfBirthController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'address': _addressController.text.trim(),
        'requested_class': _selectedClass,
        'parent_name': _parentNameController.text.trim(),
        'mother_name': _motherNameController.text.trim().isEmpty ? null : _motherNameController.text.trim(),
        'parent_phone': _phoneController.text.trim(),
        'parent_email': _emailController.text.trim(),
      };

      // Ajouter à la queue de synchronisation
      await SyncService.addToSyncQueue(
        'enrollment',
        0,
        'create',
        data,
      );

      // Essayer de synchroniser immédiatement
      await SyncService.syncPendingData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Demande d\'inscription soumise avec succès'),
            backgroundColor: Colors.green,
          ),
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
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewPadding.bottom + 24;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inscription'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Informations de l\'élève',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _studentNameController,
                decoration: const InputDecoration(
                  labelText: 'Prénom *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _studentSurnameController,
                decoration: const InputDecoration(
                  labelText: 'Nom *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _studentMiddleNameController,
                decoration: const InputDecoration(
                  labelText: 'Postnom',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _birthDateController,
                decoration: const InputDecoration(
                  labelText: 'Date de naissance *',
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: _selectBirthDate,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Genre *',
                  prefixIcon: Icon(Icons.person),
                ),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculin')),
                  DropdownMenuItem(value: 'F', child: Text('Féminin')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _placeOfBirthController,
                decoration: const InputDecoration(
                  labelText: 'Lieu de naissance *',
                  prefixIcon: Icon(Icons.place),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Informations du parent / tuteur',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du parent *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _motherNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom de la mère',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Informations de contact',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone *',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Champ requis';
                  }
                  if (!value.contains('@')) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse',
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'Sélection de l\'école',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedSchool,
                decoration: const InputDecoration(
                  labelText: 'École *',
                  prefixIcon: Icon(Icons.school),
                ),
                items: _schools.map((school) {
                  return DropdownMenuItem(
                    value: school['id'].toString(),
                    child: Text(school['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSchool = value;
                    _selectedClass = null;
                  });
                  if (value != null) {
                    _loadClasses(value);
                  }
                },
                validator: (value) {
                  if (value == null) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Classe *',
                  prefixIcon: Icon(Icons.class_),
                ),
                items: _classes.map((classItem) {
                  return DropdownMenuItem(
                    value: classItem['id'].toString(),
                    child: Text(classItem['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedClass = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Champ requis';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.attach_file),
                label: const Text('Joindre un document'),
                onPressed: _selectDocument,
              ),
              if (_selectedDocumentPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Document sélectionné: ${_selectedDocumentPath!.split('/').last}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitEnrollment,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Soumettre la demande'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
