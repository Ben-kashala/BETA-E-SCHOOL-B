import 'package:hive_flutter/hive_flutter.dart';

class HiveService {
  static const String _cacheBoxName = 'cache';
  static const String _settingsBoxName = 'settings';
  
  static late Box _cacheBox;
  static late Box _settingsBox;
  
  static Future<void> init() async {
    _cacheBox = await Hive.openBox(_cacheBoxName);
    _settingsBox = await Hive.openBox(_settingsBoxName);
  }
  
  // Cache Operations
  static Future<void> cacheData(String key, dynamic value, {Duration? expiration}) async {
    final data = {
      'value': value,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'expiration': expiration?.inMilliseconds,
    };
    await _cacheBox.put(key, data);
  }
  
  static T? getCachedData<T>(String key) {
    final data = _cacheBox.get(key);
    if (data == null) return null;
    
    final ts = data['timestamp'];
    final timestamp = ts is int ? ts : (ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0);
    final expRaw = data['expiration'];
    final int? expiration = expRaw == null
        ? null
        : (expRaw is int ? expRaw : (expRaw is num ? expRaw.toInt() : int.tryParse('$expRaw')));
    
    if (expiration != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - timestamp > expiration) {
        _cacheBox.delete(key);
        return null;
      }
    }
    
    final val = data['value'];
    if (val == null) return null;
    // Évite les cast invalides (ex. double stocké alors que T=bool) qui crashent au scroll/rebuild.
    if (val is T) return val as T;
    return null;
  }
  
  static Future<void> clearCache() async {
    await _cacheBox.clear();
  }
  
  static Future<void> removeCache(String key) async {
    await _cacheBox.delete(key);
  }
  
  // Settings Operations
  static Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }
  
  static T? getSetting<T>(String key, {T? defaultValue}) {
    final v = _settingsBox.get(key, defaultValue: defaultValue);
    if (v == null) return null;
    if (v is T) return v as T;
    return defaultValue;
  }
  
  static Future<void> clearSettings() async {
    await _settingsBox.clear();
  }
  
  // Cleanup expired cache
  static Future<void> cleanupExpiredCache() async {
    final keys = _cacheBox.keys.toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (final key in keys) {
      final data = _cacheBox.get(key);
      if (data != null) {
        final ts = data['timestamp'];
        final timestamp = ts is int ? ts : (ts is num ? ts.toInt() : int.tryParse('$ts') ?? 0);
        final expRaw = data['expiration'];
        final int? expiration = expRaw == null
            ? null
            : (expRaw is int ? expRaw : (expRaw is num ? expRaw.toInt() : int.tryParse('$expRaw')));
        if (expiration != null && now - timestamp > expiration) {
          await _cacheBox.delete(key);
        }
      }
    }
  }
}
