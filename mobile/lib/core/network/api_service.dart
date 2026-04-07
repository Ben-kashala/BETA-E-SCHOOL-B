import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import 'connectivity_service.dart';
import '../database/hive_service.dart';

/// Message lisible depuis une erreur Dio (JSON, corps binaire, etc.).
/// Fonction top-level pour un usage fiable depuis tout import de ce fichier.
String dioErrorMessage(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map) {
      // Clés courantes API DRF / backend custom
      final preferredKeys = [
        'non_field_errors',
        'error',
        'detail',
        'message',
        'username',
        'password',
      ];
      for (final k in preferredKeys) {
        final v = d[k];
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
      // Fallback: première erreur trouvée dans la map
      for (final entry in d.entries) {
        final v = entry.value;
        if (v is List && v.isNotEmpty) return v.first.toString();
        if (v != null && v.toString().trim().isNotEmpty) return v.toString();
      }
    }
    if (d is List<int>) {
      try {
        final m = jsonDecode(utf8.decode(d));
        if (m is Map && (m['error'] != null || m['detail'] != null)) {
          return (m['error'] ?? m['detail']).toString();
        }
      } catch (_) {}
    }
    if (d is String && d.isNotEmpty) {
      try {
        final m = jsonDecode(d);
        if (m is Map && m['error'] != null) return m['error'].toString();
      } catch (_) {}
    }
    final msg = e.message ?? 'Erreur réseau';
    if (msg.contains('validateStatus')) {
      final c = e.response?.statusCode;
      return 'Erreur serveur${c != null ? ' ($c)' : ''}. Réessayez ou contactez l’école.';
    }
    return msg;
  }
  return e.toString();
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  late Dio _dio;
  final _storage = const FlutterSecureStorage();
  
  String get baseUrl => _dio.options.baseUrl;

  Future<String?> getToken() async => _storage.read(key: 'access_token');

  /// En-têtes pour requêtes Dio « brutes » (PDF, etc.) qui ne passent pas par [_dio].
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await _storage.read(key: 'access_token');
    final schoolCode = await _storage.read(key: 'school_code');
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (schoolCode != null) 'X-School-Code': schoolCode,
    };
  }

  /// Alias de [dioErrorMessage] pour compatibilité avec l’existant.
  static String parseDioError(Object e) => dioErrorMessage(e);

  static bool _looksLikePdf(List<int> data) =>
      data.length >= 5 &&
      data[0] == 0x25 &&
      data[1] == 0x50 &&
      data[2] == 0x44 &&
      data[3] == 0x46 &&
      data[4] == 0x2d;

  static String? _messageFromResponseBytes(List<int> data) {
    if (data.isEmpty) return null;
    try {
      final m = jsonDecode(utf8.decode(data));
      if (m is Map) {
        final o = m['error'] ?? m['detail'] ?? m['message'];
        if (o != null) return o.toString();
      }
    } catch (_) {}
    final s = utf8.decode(data, allowMalformed: true).trim();
    if (s.length < 600 && !s.toLowerCase().contains('<!doctype')) {
      return s;
    }
    return null;
  }

  /// GET binaire authentifié sans lever [DioException] sur HTTP 4xx/5xx (lecture du corps d’erreur).
  Future<Uint8List> downloadAuthenticatedBinary(String path) async {
    assert(path.startsWith('/'), 'path doit commencer par /');
    final headers = await getAuthHeaders();
    final root = _dio.options.baseUrl.replaceAll(RegExp(r'/$'), '');
    final url = '$root$path';
    final dio = Dio(
      BaseOptions(
        validateStatus: (_) => true,
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
      ),
    );
    final res = await dio.get<List<int>>(
      url,
      options: Options(
        headers: {
          ...headers,
          'Accept': 'application/pdf, application/json;q=0.9, */*;q=0.8',
        },
        responseType: ResponseType.bytes,
      ),
    );
    final code = res.statusCode ?? 0;
    final data = res.data;
    if (code >= 200 && code < 300 && data != null && data.isNotEmpty) {
      if (_looksLikePdf(data)) {
        return Uint8List.fromList(data);
      }
      final err = _messageFromResponseBytes(data);
      throw Exception(err ?? 'Le serveur n’a pas renvoyé un PDF valide');
    }
    final err = (data != null && data.isNotEmpty)
        ? (_messageFromResponseBytes(data) ?? 'Erreur serveur ($code)')
        : 'Erreur serveur ($code)';
    throw Exception(err);
  }

  /// Clé de cache isolée par établissement pour éviter de mélanger les données entre écoles.
  Future<String> _cacheKey(String path, Map<String, dynamic>? queryParameters) async {
    final school = await _storage.read(key: 'school_code') ?? '';
    return 'api_${school}_${path}_${queryParameters?.toString()}';
  }

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.apiTimeout,
      receiveTimeout: AppConfig.apiTimeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Intercepteur pour ajouter le token
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        final schoolCode = await _storage.read(key: 'school_code');
        
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        
        if (schoolCode != null) {
          options.headers['X-School-Code'] = schoolCode;
        }
        
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Token expiré, essayer de rafraîchir
          final refreshed = await _refreshToken();
          if (refreshed) {
            // Réessayer la requête
            final opts = error.requestOptions;
            final token = await _storage.read(key: 'access_token');
            opts.headers['Authorization'] = 'Bearer $token';
            final response = await _dio.fetch(opts);
            return handler.resolve(response);
          }
        }
        return handler.next(error);
      },
    ));
  }
  
  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;
      
      final response = await _dio.post(
        '/api/auth/token/refresh/',
        data: {'refresh': refreshToken},
      );
      
      await _storage.write(key: 'access_token', value: response.data['access']);
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Méthode générique pour les requêtes avec cache
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool useCache = true,
    Duration? cacheExpiration,
  }) async {
    final cacheKey = await _cacheKey(path, queryParameters);

    final isConnected = await ConnectivityService.isConnected();

    // Hors ligne : uniquement le cache (pas de requête réseau).
    if (!isConnected) {
      if (useCache) {
        final cached = HiveService.getCachedData<dynamic>(cacheKey);
        if (cached != null) {
          return Response<T>(
            data: cached as T,
            statusCode: 200,
            requestOptions: RequestOptions(path: path),
          );
        }
      }
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }

    // En ligne : toujours interroger l'API en premier (le cache ne doit pas masquer des données à jour).
    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
      );

      if (useCache && response.statusCode == 200 && response.data != null) {
        await HiveService.cacheData(
          cacheKey,
          response.data,
          expiration: cacheExpiration ?? AppConfig.cacheExpiration,
        );
      }

      return response;
    } catch (e) {
      if (useCache) {
        final cached = HiveService.getCachedData<dynamic>(cacheKey);
        if (cached != null) {
          return Response<T>(
            data: cached as T,
            statusCode: 200,
            requestOptions: RequestOptions(path: path),
          );
        }
      }
      rethrow;
    }
  }
  
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    print('🌐 [ApiService] POST ${_dio.options.baseUrl}$path');
    print('🌐 [ApiService] Data: $data');
    
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      print('❌ [ApiService] Pas de connexion internet');
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    try {
      final response = await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
      );
      print('✅ [ApiService] Réponse ${response.statusCode}: ${response.data}');
      return response;
    } catch (e) {
      if (e is DioException) {
        print('❌ [ApiService] Erreur Dio: ${e.type}');
        print('❌ [ApiService] Status: ${e.response?.statusCode}');
        print('❌ [ApiService] Message: ${e.response?.data}');
        print('❌ [ApiService] Error: ${e.message}');
      } else {
        print('❌ [ApiService] Erreur: $e');
      }
      rethrow;
    }
  }
  
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    return await _dio.patch<T>(
      path,
      data: data,
      queryParameters: queryParameters,
    );
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    return await _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
    );
  }
  
  Future<Response<T>> delete<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    return await _dio.delete<T>(
      path,
      queryParameters: queryParameters,
    );
  }
  
  // Upload de fichier avec progression
  Future<Response<T>> uploadFile<T>(
    String path,
    String filePath, {
    String fileKey = 'file',
    ProgressCallback? onSendProgress,
  }) async {
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    final formData = FormData.fromMap({
      fileKey: await MultipartFile.fromFile(filePath),
    });
    
    return await _dio.post<T>(
      path,
      data: formData,
      onSendProgress: onSendProgress,
    );
  }
  
  // Download de fichier avec progression
  Future<void> downloadFile(
    String url,
    String savePath, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      throw DioException(
        requestOptions: RequestOptions(path: url),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
