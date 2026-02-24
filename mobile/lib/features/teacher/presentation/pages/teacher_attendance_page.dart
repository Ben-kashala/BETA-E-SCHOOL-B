import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_service.dart';

class TeacherAttendancePage extends ConsumerStatefulWidget {
  const TeacherAttendancePage({super.key});

  @override
  ConsumerState<TeacherAttendancePage> createState() => _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends ConsumerState<TeacherAttendancePage> {
  List<dynamic> _classes = [];
  int? _selectedClassId;
  List<dynamic> _students = [];
  Map<int, String> _attendanceStatus = {}; // studentId -> status
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/schools/classes/my_titular/');
      setState(() {
        _classes = response.data is List ? response.data : (response.data['results'] ?? []);
        if (_classes.isNotEmpty) {
          _selectedClassId = _classes[0]['id'];
          _loadStudents();
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedClassId == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().get('/api/accounts/students/', queryParameters: {
        'school_class': _selectedClassId.toString(),
      });
      setState(() {
        _students = response.data is List ? response.data : (response.data['results'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAttendance() async {
    if (_selectedClassId == null || _attendanceStatus.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      final dateStr = _selectedDate.toIso8601String().split('T')[0];
      for (var entry in _attendanceStatus.entries) {
        await ApiService().post('/api/academics/attendance/', data: {
          'student': entry.key,
          'school_class': _selectedClassId,
          'date': dateStr,
          'status': entry.value,
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Présences enregistrées')),
        );
        setState(() => _attendanceStatus = {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Présences'),
      ),
      body: _isLoading && _classes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _classes.isEmpty
              ? const Center(child: Text('Aucune classe assignée'))
              : Column(
                  children: [
                    // Sélection classe et date
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<int>(
                              value: _selectedClassId,
                              decoration: const InputDecoration(labelText: 'Classe'),
                              items: _classes.map((c) => DropdownMenuItem<int>(
                                value: c['id'] as int,
                                child: Text(c['name'] ?? 'Classe'),
                              )).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedClassId = value;
                                  _attendanceStatus = {};
                                });
                                _loadStudents();
                              },
                            ),
                            const SizedBox(height: 16),
                            InkWell(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (date != null) {
                                  setState(() => _selectedDate = date);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(labelText: 'Date'),
                                child: Text(_selectedDate.toLocal().toString().split(' ')[0]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Liste des élèves
                    Expanded(
                      child: _students.isEmpty
                          ? const Center(child: Text('Aucun élève dans cette classe'))
                          : ListView.builder(
                              itemCount: _students.length,
                              itemBuilder: (context, index) {
                                final student = _students[index];
                                final studentId = student['id'];
                                final status = _attendanceStatus[studentId] ?? 'PRESENT';
                                final name = student['user'] != null
                                    ? '${student['user']['first_name']} ${student['user']['last_name']}'
                                    : student['user_name'] ?? 'Élève';
                                
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  child: ListTile(
                                    title: Text(name),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildStatusButton('PRESENT', status, studentId, Colors.green),
                                        const SizedBox(width: 4),
                                        _buildStatusButton('ABSENT', status, studentId, Colors.red),
                                        const SizedBox(width: 4),
                                        _buildStatusButton('LATE', status, studentId, Colors.orange),
                                        const SizedBox(width: 4),
                                        _buildStatusButton('EXCUSED', status, studentId, Colors.blue),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Bouton sauvegarder
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: _attendanceStatus.isEmpty ? null : _saveAttendance,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        child: const Text('Enregistrer les présences'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatusButton(String status, String currentStatus, int studentId, Color color) {
    final isSelected = currentStatus == status;
    return InkWell(
      onTap: () {
        setState(() {
          _attendanceStatus[studentId] = status;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey[200],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          status == 'PRESENT' ? Icons.check :
          status == 'ABSENT' ? Icons.close :
          status == 'LATE' ? Icons.schedule :
          Icons.info,
          color: isSelected ? Colors.white : Colors.grey[600],
          size: 20,
        ),
      ),
    );
  }
}
