import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import '../../features/auth/domain/models/user_model.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../database/hive_service.dart';
import '../network/api_service.dart';

class AuthState {
  final bool isAuthenticated;
  final UserModel? user;
  final bool isLoading;
  final String? error;

  AuthState({
    this.isAuthenticated = false,
    this.user,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    UserModel? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _authRepository;
  final _storage = const FlutterSecureStorage();

  AuthNotifier(this._authRepository) : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final token = await _storage.read(key: 'access_token');
    if (token != null) {
      try {
        final user = await _authRepository.getCurrentUser();
        state = state.copyWith(
          isAuthenticated: true,
          user: user,
        );
      } catch (e) {
        await logout();
      }
    }
  }

  /// Retourne (success, messageErreur). En cas d'échec, [messageErreur] contient le message à afficher.
  Future<(bool, String?)> login(String username, String password) async {
    print('🔑 [AuthProvider] Début du login pour: $username');
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await _authRepository.login(username, password);
      print('✅ [AuthProvider] Login réussi, sauvegarde des tokens...');
      
      await _storage.write(key: 'access_token', value: result.accessToken);
      await _storage.write(key: 'refresh_token', value: result.refreshToken);
      if (result.user.schoolCode != null) {
        await _storage.write(key: 'school_code', value: result.user.schoolCode!);
      }
      await HiveService.clearCache();
      
      print('✅ [AuthProvider] Tokens sauvegardés, mise à jour de l\'état...');
      state = state.copyWith(
        isAuthenticated: true,
        user: result.user,
        isLoading: false,
        error: null,
      );
      print('✅ [AuthProvider] État mis à jour: isAuthenticated=${state.isAuthenticated}, user=${state.user?.email ?? state.user?.username}');
      return (true, null);
    } catch (e, stackTrace) {
      print('❌ [AuthProvider] Erreur lors du login: $e');
      print('📚 [AuthProvider] Stack trace: $stackTrace');
      String message = ApiService.parseDioError(e)
          .replaceFirst(RegExp(r'^Exception:?\s*'), '')
          .trim();

      // Fallback intelligent seulement si on n'a pas de message lisible.
      if (message.isEmpty ||
          message.contains('validateStatus') ||
          message.contains('Client error')) {
        if (e is DioException) {
          final code = e.response?.statusCode;
          if (code == 400 || code == 401) {
            message =
                'Identifiant ou mot de passe incorrect. Veuillez réessayer.';
          } else if (code == 403) {
            message = 'Votre compte est désactivé ou bloqué.';
          } else {
            message = 'Connexion impossible. Veuillez réessayer.';
          }
        } else {
          message = 'Connexion impossible. Veuillez réessayer.';
        }
      }
      state = state.copyWith(
        isLoading: false,
        error: message,
      );
      return (false, message);
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
    await HiveService.clearCache();
    state = AuthState();
  }

  Future<void> refreshUser() async {
    try {
      final user = await _authRepository.getCurrentUser();
      state = state.copyWith(user: user);
    } catch (e) {
      // Ignorer les erreurs silencieusement
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
