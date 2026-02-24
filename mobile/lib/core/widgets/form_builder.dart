import 'package:flutter/material.dart';

class FormBuilder {
  static Widget buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
    int? maxLines,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboardType,
        maxLines: maxLines ?? 1,
        validator: validator ?? (required ? (v) => v?.isEmpty ?? true ? 'Ce champ est requis' : null : null),
      ),
    );
  }

  static Widget buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required Function(T?) onChanged,
    bool required = false,
    String? Function(T?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          border: const OutlineInputBorder(),
        ),
        items: items,
        onChanged: onChanged,
        validator: validator ?? (required ? (v) => v == null ? 'Ce champ est requis' : null : null),
      ),
    );
  }

  static Widget buildDatePicker({
    required BuildContext context,
    required String label,
    required DateTime? value,
    required Function(DateTime?) onChanged,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
          );
          onChanged(date);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label + (required ? ' *' : ''),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          child: Text(
            value != null 
                ? '${value.day}/${value.month}/${value.year}'
                : 'Sélectionner une date',
          ),
        ),
      ),
    );
  }

  static Widget buildTimePicker({
    required BuildContext context,
    required String label,
    required TimeOfDay? value,
    required Function(TimeOfDay?) onChanged,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: value ?? TimeOfDay.now(),
          );
          onChanged(time);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label + (required ? ' *' : ''),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.access_time),
          ),
          child: Text(
            value != null 
                ? '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'
                : 'Sélectionner une heure',
          ),
        ),
      ),
    );
  }

  static Widget buildSwitch({
    required String label,
    required bool value,
    required Function(bool) onChanged,
    String? subtitle,
  }) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  static Widget buildCheckbox({
    required String label,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return CheckboxListTile(
      title: Text(label),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
    );
  }

  static Widget buildFilePicker({
    required String label,
    required String? fileName,
    required Function() onPick,
    Function()? onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.attach_file),
                  label: Text(fileName ?? 'Sélectionner un fichier'),
                ),
              ),
              if (fileName != null && onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
