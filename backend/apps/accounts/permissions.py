"""
Permission DRF : lorsque la plateforme est verrouillée, seul le superadmin peut accéder à l'API.
Appliquée à chaque requête authentifiée (mobile, frontend).
"""
from rest_framework import permissions


class PlatformLockPermission(permissions.BasePermission):
    """
    Si la plateforme est verrouillée, seul le superadmin protégé peut accéder.
    Les requêtes non authentifiées sont autorisées (pour la page de login, etc.).
    """
    message = 'La plateforme est temporairement indisponible.'

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return True  # La vue gère elle-même (ex. AllowAny pour login)
        try:
            from .models import PlatformSettings
            ps = PlatformSettings.get_singleton()
            if not ps.is_platform_locked:
                return True
            if getattr(request.user, 'is_protected_superadmin', False):
                return True
            return False
        except Exception:
            return True  # En cas d'erreur (migration non appliquée), ne pas bloquer
