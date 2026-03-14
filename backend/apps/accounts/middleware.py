from django.conf import settings
from django.contrib.auth import logout
from django.shortcuts import redirect
from django.contrib import messages
from django.utils import timezone


class AutoLogoutMiddleware:
    """
    Déconnecte automatiquement l'utilisateur après une période d'inactivité.
    La durée est définie par le paramètre AUTO_LOGOUT_DELAY (en secondes).
    """

    def __init__(self, get_response):
        self.get_response = get_response
        self.timeout = getattr(settings, "AUTO_LOGOUT_DELAY", 30 * 60)

    def __call__(self, request):
        if request.user.is_authenticated:
            now = timezone.now()
            last_activity = request.session.get("last_activity_ts")

            if last_activity is not None:
                elapsed = now.timestamp() - float(last_activity)
                if elapsed > self.timeout:
                    logout(request)
                    # On flush la session pour repartir proprement
                    request.session.flush()
            # Si l'utilisateur est encore authentifié, on met à jour l'horodatage
            if request.user.is_authenticated:
                request.session["last_activity_ts"] = now.timestamp()

        response = self.get_response(request)
        return response


class PlatformLockMiddleware:
    """
    Lorsque la plateforme est verrouillée (paramètre superadmin), seul le superadmin
    peut accéder à l'admin Django. Les autres utilisateurs connectés sont déconnectés
    et redirigés vers la page de login avec un message.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        admin_path = getattr(settings, 'DJANGO_ADMIN_URL', 'admin').strip().strip('/') or 'admin'
        prefix = f'/{admin_path}/'
        is_admin_url = request.path.startswith(prefix)
        is_admin_login = request.path.rstrip('/').endswith(f'{admin_path}/login') or request.path.rstrip('/').endswith('login')

        if is_admin_url and not is_admin_login and request.user.is_authenticated:
            try:
                from .models import PlatformSettings
                ps = PlatformSettings.get_singleton()
                if ps.is_platform_locked and not getattr(request.user, 'is_protected_superadmin', False):
                    logout(request)
                    request.session.flush()
                    msg = ps.locked_message or 'La plateforme est temporairement indisponible. Seul le superadmin peut se connecter.'
                    messages.error(request, msg)
                    return redirect(f'/{admin_path}/login/?next={request.path}')
            except Exception:
                pass

        return self.get_response(request)

