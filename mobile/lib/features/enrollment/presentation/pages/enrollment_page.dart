import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/services/sync_service.dart';
import '../../../../core/providers/auth_provider.dart';

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
  // Adresse élève (structurée + libre)
  final _addressNumberController = TextEditingController();
  final _addressAvenueController = TextEditingController();
  final _addressQuarterController = TextEditingController();
  final _addressCommuneController = TextEditingController();
  final _addressCityController = TextEditingController();
  final _addressProvinceController = TextEditingController();
  final _addressCountryController = TextEditingController(text: 'RDC');
  final _addressController = TextEditingController();
  final _previousSchoolController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _parentPhoneController = TextEditingController();
  final _parentEmailController = TextEditingController();
  final _parentProfessionController = TextEditingController();
  // Adresse parent (structurée + libre)
  final _parentAddressNumberController = TextEditingController();
  final _parentAddressAvenueController = TextEditingController();
  final _parentAddressQuarterController = TextEditingController();
  final _parentAddressCommuneController = TextEditingController();
  final _parentAddressCityController = TextEditingController();
  final _parentAddressProvinceController = TextEditingController();
  final _parentAddressCountryController = TextEditingController(text: 'RDC');
  final _parentAddressController = TextEditingController();
  
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
    _prefillParentFromUser();
    _loadClassesForUserSchool();
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
    _addressNumberController.dispose();
    _addressAvenueController.dispose();
    _addressQuarterController.dispose();
    _addressCommuneController.dispose();
    _addressCityController.dispose();
    _addressProvinceController.dispose();
    _addressCountryController.dispose();
    _addressController.dispose();
    _previousSchoolController.dispose();
    _parentNameController.dispose();
    _motherNameController.dispose();
    _parentPhoneController.dispose();
    _parentEmailController.dispose();
    _parentProfessionController.dispose();
    _parentAddressNumberController.dispose();
    _parentAddressAvenueController.dispose();
    _parentAddressQuarterController.dispose();
    _parentAddressCommuneController.dispose();
    _parentAddressCityController.dispose();
    _parentAddressProvinceController.dispose();
    _parentAddressCountryController.dispose();
    _parentAddressController.dispose();
    super.dispose();
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

  void _prefillParentFromUser() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    // Nom complet du parent
    _parentNameController.text =
        '${user.firstName} ${user.lastName}'.trim();
    // Téléphone / email du parent
    if (user.phone != null && user.phone!.isNotEmpty) {
      _parentPhoneController.text = user.phone!;
      _phoneController.text = user.phone!;
    }
    if (user.email.isNotEmpty) {
      _parentEmailController.text = user.email;
      _emailController.text = user.email;
    }
    // Adresse approximative si disponible
    if (user.addressCity != null && user.addressCity!.isNotEmpty) {
      _parentAddressCityController.text = user.addressCity!;
      _addressCityController.text = user.addressCity!;
    }
    if (user.addressProvince != null && user.addressProvince!.isNotEmpty) {
      _parentAddressProvinceController.text = user.addressProvince!;
      _addressProvinceController.text = user.addressProvince!;
    }
    if (user.addressCountry != null && user.addressCountry!.isNotEmpty) {
      _parentAddressCountryController.text = user.addressCountry!;
      _addressCountryController.text = user.addressCountry!;
    }
    if (user.address != null && user.address!.isNotEmpty) {
      _parentAddressController.text = user.address!;
    }
  }

  Future<void> _loadClassesForUserSchool() async {
    try {
      final user = ref.read(authProvider).user;
      if (user == null || user.schoolCode == null) {
        return;
      }
      // On ne connaît pas l'id numérique de l'école côté mobile, mais l'API
      // accepte le code via l'en-tête X-School-Code déjà ajouté par ApiService.
      // Donc on peut charger toutes les classes de l'école courante.
      final response = await ApiService().get('/api/schools/classes/', useCache: false);
      setState(() {
        _classes = response.data as List<dynamic>;
      });
    } catch (e) {
      // Gérer l'erreur silencieusement
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
      // Reconstruire les adresses libres comme sur le web
      final addressParts = [
        _addressNumberController.text.trim().isNotEmpty ? 'N° ${_addressNumberController.text.trim()}' : '',
        _addressAvenueController.text.trim().isNotEmpty ? 'Av. ${_addressAvenueController.text.trim()}' : '',
        _addressQuarterController.text.trim().isNotEmpty ? 'Q. ${_addressQuarterController.text.trim()}' : '',
        _addressCommuneController.text.trim().isNotEmpty ? 'C. ${_addressCommuneController.text.trim()}' : '',
        _addressCityController.text.trim(),
        _addressProvinceController.text.trim(),
        _addressCountryController.text.trim(),
      ].where((e) => e.isNotEmpty).toList();

      final parentAddressParts = [
        _parentAddressNumberController.text.trim().isNotEmpty ? 'N° ${_parentAddressNumberController.text.trim()}' : '',
        _parentAddressAvenueController.text.trim().isNotEmpty ? 'Av. ${_parentAddressAvenueController.text.trim()}' : '',
        _parentAddressQuarterController.text.trim().isNotEmpty ? 'Q. ${_parentAddressQuarterController.text.trim()}' : '',
        _parentAddressCommuneController.text.trim().isNotEmpty ? 'C. ${_parentAddressCommuneController.text.trim()}' : '',
        _parentAddressCityController.text.trim(),
        _parentAddressProvinceController.text.trim(),
        _parentAddressCountryController.text.trim(),
      ].where((e) => e.isNotEmpty).toList();

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
        // Adresse élève structurée + libre
        'address_number': _addressNumberController.text.trim().isEmpty ? null : _addressNumberController.text.trim(),
        'address_avenue': _addressAvenueController.text.trim().isEmpty ? null : _addressAvenueController.text.trim(),
        'address_quarter': _addressQuarterController.text.trim().isEmpty ? null : _addressQuarterController.text.trim(),
        'address_commune': _addressCommuneController.text.trim().isEmpty ? null : _addressCommuneController.text.trim(),
        'address_city': _addressCityController.text.trim().isEmpty ? null : _addressCityController.text.trim(),
        'address_province': _addressProvinceController.text.trim().isEmpty ? null : _addressProvinceController.text.trim(),
        'address_country': _addressCountryController.text.trim().isEmpty ? null : _addressCountryController.text.trim(),
        'address': addressParts.isNotEmpty ? addressParts.join(', ') : _addressController.text.trim(),
        'previous_school': _previousSchoolController.text.trim().isEmpty ? null : _previousSchoolController.text.trim(),
        'requested_class': _selectedClass,
        'parent_name': _parentNameController.text.trim(),
        'mother_name': _motherNameController.text.trim().isEmpty ? null : _motherNameController.text.trim(),
        'parent_phone': _parentPhoneController.text.trim().isEmpty
            ? _phoneController.text.trim()
            : _parentPhoneController.text.trim(),
        'parent_email': _parentEmailController.text.trim().isEmpty
            ? _emailController.text.trim()
            : _parentEmailController.text.trim(),
        'parent_profession':
            _parentProfessionController.text.trim().isEmpty ? null : _parentProfessionController.text.trim(),
        // Adresse parent structurée + libre
        'parent_address_number': _parentAddressNumberController.text.trim().isEmpty
            ? null
            : _parentAddressNumberController.text.trim(),
        'parent_address_avenue': _parentAddressAvenueController.text.trim().isEmpty
            ? null
            : _parentAddressAvenueController.text.trim(),
        'parent_address_quarter': _parentAddressQuarterController.text.trim().isEmpty
            ? null
            : _parentAddressQuarterController.text.trim(),
        'parent_address_commune': _parentAddressCommuneController.text.trim().isEmpty
            ? null
            : _parentAddressCommuneController.text.trim(),
        'parent_address_city': _parentAddressCityController.text.trim().isEmpty
            ? null
            : _parentAddressCityController.text.trim(),
        'parent_address_province': _parentAddressProvinceController.text.trim().isEmpty
            ? null
            : _parentAddressProvinceController.text.trim(),
        'parent_address_country': _parentAddressCountryController.text.trim().isEmpty
            ? null
            : _parentAddressCountryController.text.trim(),
        'parent_address':
            parentAddressParts.isNotEmpty ? parentAddressParts.join(', ') : _parentAddressController.text.trim(),
        if (_selectedSchool != null) 'school': _selectedSchool,
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

      // Mettre à jour le profil parent avec les infos saisies (si connecté)
      try {
        final user = ref.read(authProvider).user;
        if (user != null) {
          final profileUpdate = {
            'first_name': user.firstName,
            'last_name': user.lastName,
            'phone': _parentPhoneController.text.trim().isNotEmpty
                ? _parentPhoneController.text.trim()
                : _phoneController.text.trim(),
            'email': _parentEmailController.text.trim().isNotEmpty
                ? _parentEmailController.text.trim()
                : _emailController.text.trim(),
            'address_number': _parentAddressNumberController.text.trim().isEmpty
                ? null
                : _parentAddressNumberController.text.trim(),
            'address_avenue': _parentAddressAvenueController.text.trim().isEmpty
                ? null
                : _parentAddressAvenueController.text.trim(),
            'address_quarter': _parentAddressQuarterController.text.trim().isEmpty
                ? null
                : _parentAddressQuarterController.text.trim(),
            'address_commune': _parentAddressCommuneController.text.trim().isEmpty
                ? null
                : _parentAddressCommuneController.text.trim(),
            'address_city': _parentAddressCityController.text.trim().isEmpty
                ? null
                : _parentAddressCityController.text.trim(),
            'address_province': _parentAddressProvinceController.text.trim().isEmpty
                ? null
                : _parentAddressProvinceController.text.trim(),
            'address_country': _parentAddressCountryController.text.trim().isEmpty
                ? null
                : _parentAddressCountryController.text.trim(),
            'address': parentAddressParts.isNotEmpty
                ? parentAddressParts.join(', ')
                : _parentAddressController.text.trim(),
          };
          await ApiService().patch('/api/auth/users/me/', data: profileUpdate);
        }
      } catch (_) {
        // On ignore les erreurs de mise à jour de profil pour ne pas bloquer la soumission
      }

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
                'Adresse de l\'élève',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressNumberController,
                decoration: const InputDecoration(
                  labelText: 'Numéro',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressAvenueController,
                decoration: const InputDecoration(
                  labelText: 'Avenue',
                  prefixIcon: Icon(Icons.route),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressQuarterController,
                decoration: const InputDecoration(
                  labelText: 'Quartier',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCommuneController,
                decoration: const InputDecoration(
                  labelText: 'Commune',
                  prefixIcon: Icon(Icons.apartment),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCityController,
                decoration: const InputDecoration(
                  labelText: 'Ville *',
                  prefixIcon: Icon(Icons.location_city_outlined),
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
                controller: _addressProvinceController,
                decoration: const InputDecoration(
                  labelText: 'Province *',
                  prefixIcon: Icon(Icons.map),
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
                controller: _addressCountryController,
                decoration: const InputDecoration(
                  labelText: 'Pays *',
                  prefixIcon: Icon(Icons.public),
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
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse (libre)',
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _previousSchoolController,
                decoration: const InputDecoration(
                  labelText: 'École fréquentée précédemment',
                  prefixIcon: Icon(Icons.school_outlined),
                ),
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
                controller: _parentPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Téléphone du parent *',
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
                controller: _parentEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email du parent *',
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
                controller: _parentProfessionController,
                decoration: const InputDecoration(
                  labelText: 'Profession du parent',
                  prefixIcon: Icon(Icons.work_outline),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Adresse du parent / tuteur',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressNumberController,
                decoration: const InputDecoration(
                  labelText: 'Numéro',
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressAvenueController,
                decoration: const InputDecoration(
                  labelText: 'Avenue',
                  prefixIcon: Icon(Icons.route),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressQuarterController,
                decoration: const InputDecoration(
                  labelText: 'Quartier',
                  prefixIcon: Icon(Icons.location_city),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressCommuneController,
                decoration: const InputDecoration(
                  labelText: 'Commune',
                  prefixIcon: Icon(Icons.apartment),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressCityController,
                decoration: const InputDecoration(
                  labelText: 'Ville',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressProvinceController,
                decoration: const InputDecoration(
                  labelText: 'Province',
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressCountryController,
                decoration: const InputDecoration(
                  labelText: 'Pays',
                  prefixIcon: Icon(Icons.public),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _parentAddressController,
                decoration: const InputDecoration(
                  labelText: 'Adresse (libre)',
                  prefixIcon: Icon(Icons.location_on),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'Sélection de l\'école',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Icon(Icons.school, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'École : votre école actuelle (définie dans votre compte)',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedClass,
                decoration: const InputDecoration(
                  labelText: 'Classe *',
                  prefixIcon: Icon(Icons.class_),
                ),
                items: _classes.map((classItem) {
                  final name = (classItem['name'] ?? '') as String;
                  final level = (classItem['level'] ?? '') as String;
                  final label = level.isNotEmpty ? '$name ($level)' : name;
                  return DropdownMenuItem(
                    value: classItem['id'].toString(),
                    child: Text(label),
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
