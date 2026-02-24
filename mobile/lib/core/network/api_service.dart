import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';
import 'connectivity_service.dart';
import '../database/hive_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  
  late Dio _dio;
  final _storage = const FlutterSecureStorage();
  
  String get baseUrl => _dio.options.baseUrl;

  Future<String?> getToken() async => _storage.read(key: 'access_token');

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
    final cacheKey = 'api_${path}_${queryParameters?.toString()}';
    
    // Vérifier le cache si activé
    if (useCache) {
      final cached = HiveService.getCachedData<Map<String, dynamic>>(cacheKey);
      if (cached != null) {
        return Response(
          data: cached as T,
          statusCode: 200,
          requestOptions: RequestOptions(path: path),
        );
      }
    }
    
    // Vérifier la connectivité
    final isConnected = await ConnectivityService.isConnected();
    if (!isConnected) {
      // Retourner les données du cache même si expirées
      final cached = HiveService.getCachedData<Map<String, dynamic>>(cacheKey);
      if (cached != null) {
        return Response(
          data: cached as T,
          statusCode: 200,
          requestOptions: RequestOptions(path: path),
        );
      }
      throw DioException(
        requestOptions: RequestOptions(path: path),
        error: 'No internet connection',
        type: DioExceptionType.connectionError,
      );
    }
    
    try {
      final response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
      );
      
      // Mettre en cache si succès
      if (useCache && response.statusCode == 200) {
        await HiveService.cacheData(
          cacheKey,
          response.data,
          expiration: cacheExpiration ?? AppConfig.cacheExpiration,
        );
      }
      
      return response;
    } catch (e) {
      // En cas d'erreur, retourner le cache si disponible
      if (useCache) {
        final cached = HiveService.getCachedData<Map<String, dynamic>>(cacheKey);
        if (cached != null) {
          return Response(
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
