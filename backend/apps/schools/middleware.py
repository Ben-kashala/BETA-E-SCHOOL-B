"""
Middleware for multi-tenant support
"""
from django.http import JsonResponse
from .models import School


class TenantMiddleware:
    """
    Middleware to set the current school (tenant) based on request headers or subdomain
    """
    def __init__(self, get_response):
        self.get_response = get_response
    
    def __call__(self, request):
        # Get school from header (X-School-Code) or subdomain
        school_code = request.headers.get('X-School-Code') or request.GET.get('school_code')
        
        if school_code:
            try:
                school = School.objects.get(code=school_code, is_active=True)
                user = getattr(request, 'user', None)
                # Contrôle anti-spoofing du tenant :
                # un utilisateur authentifié "lié à une école" ne peut pas forcer un autre code école.
                # Exceptions :
                # - superuser / superadmin protégé
                # - promoteur (multi-écoles)
                if user and getattr(user, 'is_authenticated', False):
                    is_super = bool(
                        getattr(user, 'is_superuser', False)
                        or getattr(user, 'is_protected_superadmin', False)
                    )
                    is_promoter = bool(getattr(user, 'is_promoter', False))
                    user_school_id = getattr(user, 'school_id', None)
                    requested_school_id = getattr(school, 'id', None)

                    if user_school_id and not (is_super or is_promoter):
                        if requested_school_id != user_school_id:
                            return JsonResponse(
                                {
                                    'detail': (
                                        "En-tête X-School-Code invalide pour l'utilisateur authentifié."
                                    )
                                },
                                status=403,
                            )

                request.school = school
            except School.DoesNotExist:
                request.school = None
        else:
            request.school = None
        
        response = self.get_response(request)
        return response
