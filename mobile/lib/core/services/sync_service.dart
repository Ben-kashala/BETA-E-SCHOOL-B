import 'package:workmanager/workmanager.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database_service.dart';
import '../network/api_service.dart';
import '../network/connectivity_service.dart';
import 'dart:convert';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
  
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
    
    // Planifier la synchronisation périodique
    await Workmanager().registerPeriodicTask(
      'sync_task',
      'syncData',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  }

  static Future<void> _ensureBackgroundServicesInitialized() async {
    WidgetsFlutterBinding.ensureInitialized();
    final appDir = await getApplicationDocumentsDirectory();
    await DatabaseService.init(appDir.path);
    ApiService().init();
    await ConnectivityService().init();
  }
  
  static Future<void> syncPendingData() async {
    await _ensureBackgroundServicesInitialized();
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) return;
    
    final db = DatabaseService.database;
    final queue = await db.query(
      'sync_queue',
      where: 'synced_at IS NULL',
      orderBy: 'created_at ASC',
    );
    
    for (final item in queue) {
      try {
        await _syncItem(item);
        await db.update(
          'sync_queue',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      } catch (e) {
        // Incrémenter le compteur de retry
        final retryCount = (item['retry_count'] as int) + 1;
        if (retryCount >= 3) {
          // Marquer comme échoué après 3 tentatives
          await db.delete('sync_queue', where: 'id = ?', whereArgs: [item['id']]);
        } else {
          await db.update(
            'sync_queue',
            {'retry_count': retryCount},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }
    }
  }
  
  static Future<void> _syncItem(Map<String, dynamic> item) async {
    final tableName = item['table_name'] as String;
    final action = item['action'] as String;
    final data = jsonDecode(item['data'] as String);
    
    switch (tableName) {
      case 'assignments':
        if (action == 'submit') {
          await ApiService().post(
            '/api/elearning/assignments/${data['id']}/submit/',
            data: data,
          );
        }
        break;
      case 'enrollment':
        if (action == 'create') {
          await ApiService().post(
            '/api/enrollment/applications/',
            data: data,
          );
        }
        break;
      // Ajouter d'autres cas selon les besoins
    }
  }
  
  static Future<void> addToSyncQueue(
    String tableName,
    int recordId,
    String action,
    Map<String, dynamic> data,
  ) async {
    final db = DatabaseService.database;
    await db.insert('sync_queue', {
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'data': jsonEncode(data),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'retry_count': 0,
    });
  }
}

// Handler pour Workmanager (doit être top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await SyncService._ensureBackgroundServicesInitialized();
    if (task == 'syncData') {
      await SyncService.syncPendingData();
    }
    return Future.value(true);
  });
}
