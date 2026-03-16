class AppConfig {
  // API Configuration
  // En production : flutter build apk --dart-define=API_BASE_URL=https://e-school.up.railway.app/
  // Sinon utilise la valeur par défaut (développement)
  // Note: baseUrl ne doit PAS contenir /api car tous les endpoints dans le code commencent par /api/
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://e-school.up.railway.app',
  );
  static const String apiVersion = 'v1';
  static const Duration apiTimeout = Duration(seconds: 30);
  
  // Cache Configuration
  static const Duration cacheExpiration = Duration(hours: 24);
  static const int maxCacheSize = 100 * 1024 * 1024; // 100 MB
  
  // Offline Configuration
  static const Duration syncInterval = Duration(minutes: 15);
  static const int maxRetryAttempts = 3;
  static const Duration retryDelay = Duration(seconds: 5);
  
  // Download Configuration
  static const String downloadPath = 'downloads';
  static const int maxConcurrentDownloads = 3;
  
  // Security
  static const String encryptionKey = String.fromEnvironment(
    'ENCRYPTION_KEY',
    defaultValue: 'eschool_mobile_key',
  );
  static const int tokenRefreshThreshold = 300; // 5 minutes avant expiration
  
  // UI Configuration
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 12.0;
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // Data Optimization
  static const bool enableImageCompression = true;
  static const int imageQuality = 80;
  static const int thumbnailSize = 200;
  
  // Notification Configuration
  static const String notificationChannelId = 'eschool_channel';
  static const String notificationChannelName = 'E-School Notifications';
}
