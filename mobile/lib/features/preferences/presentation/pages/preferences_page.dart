import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/preferences/preferences_service.dart';

class PreferencesPage extends ConsumerStatefulWidget {
  const PreferencesPage({super.key});

  @override
  ConsumerState<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends ConsumerState<PreferencesPage> {
  String _theme = 'system';
  String _language = 'fr';
  bool _notificationsEnabled = true;
  bool _offlineMode = false;
  bool _autoSync = true;
  double _fontSize = 14.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    _theme = await PreferencesService.getTheme() ?? 'system';
    _language = await PreferencesService.getLanguage() ?? 'fr';
    _notificationsEnabled = await PreferencesService.getNotificationsEnabled();
    _offlineMode = await PreferencesService.getOfflineMode();
    _autoSync = await PreferencesService.getAutoSync();
    _fontSize = await PreferencesService.getFontSize();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Préférences')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Préférences'),
      ),
      body: ListView(
        children: [
          // Apparence
          _buildSection(
            title: 'Apparence',
            children: [
              ListTile(
                title: const Text('Thème'),
                subtitle: Text(_theme == 'system' 
                    ? 'Système' 
                    : _theme == 'light' 
                        ? 'Clair' 
                        : 'Sombre'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Choisir le thème'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            title: const Text('Système'),
                            value: 'system',
                            groupValue: _theme,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _theme = value);
                              PreferencesService.setTheme(value);
                              Navigator.of(context).pop();
                            },
                          ),
                          RadioListTile<String>(
                            title: const Text('Clair'),
                            value: 'light',
                            groupValue: _theme,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _theme = value);
                              PreferencesService.setTheme(value);
                              Navigator.of(context).pop();
                            },
                          ),
                          RadioListTile<String>(
                            title: const Text('Sombre'),
                            value: 'dark',
                            groupValue: _theme,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _theme = value);
                              PreferencesService.setTheme(value);
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                title: const Text('Taille de police'),
                subtitle: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 20,
                  divisions: 8,
                  label: _fontSize.toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _fontSize = value;
                      PreferencesService.setFontSize(value);
                    });
                  },
                ),
              ),
            ],
          ),
          // Langue
          _buildSection(
            title: 'Langue',
            children: [
              ListTile(
                title: const Text('Langue'),
                subtitle: Text(_language == 'fr' ? 'Français' : 'Anglais'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Choisir la langue'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadioListTile<String>(
                            title: const Text('Français'),
                            value: 'fr',
                            groupValue: _language,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _language = value);
                              PreferencesService.setLanguage(value);
                              Navigator.of(context).pop();
                            },
                          ),
                          RadioListTile<String>(
                            title: const Text('Anglais'),
                            value: 'en',
                            groupValue: _language,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _language = value);
                              PreferencesService.setLanguage(value);
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // Notifications
          _buildSection(
            title: 'Notifications',
            children: [
              SwitchListTile(
                title: const Text('Activer les notifications'),
                subtitle: const Text('Recevoir des notifications push'),
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                    PreferencesService.setNotificationsEnabled(value);
                  });
                },
              ),
            ],
          ),
          // Synchronisation
          _buildSection(
            title: 'Synchronisation',
            children: [
              SwitchListTile(
                title: const Text('Mode hors ligne'),
                subtitle: const Text('Utiliser les données en cache'),
                value: _offlineMode,
                onChanged: (value) {
                  setState(() {
                    _offlineMode = value;
                    PreferencesService.setOfflineMode(value);
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Synchronisation automatique'),
                subtitle: const Text('Synchroniser automatiquement les données'),
                value: _autoSync,
                onChanged: (value) {
                  setState(() {
                    _autoSync = value;
                    PreferencesService.setAutoSync(value);
                  });
                },
              ),
            ],
          ),
          // Actions
          _buildSection(
            title: 'Actions',
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Effacer le cache'),
                subtitle: const Text('Supprimer toutes les données en cache'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Effacer le cache'),
                      content: const Text('Êtes-vous sûr de vouloir effacer toutes les données en cache ?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            // TODO: Effacer le cache
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cache effacé')),
                            );
                          },
                          child: const Text('Effacer'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}
