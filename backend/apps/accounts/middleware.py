from django.conf import settings
from django.contrib.auth import logout
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

