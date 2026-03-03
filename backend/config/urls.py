"""
URL configuration for e-school-management project.
"""
from django.contrib import admin
from django.http import HttpResponse
from django.urls import path, include, re_path
from django.conf import settings
from django.conf.urls.static import static
from django.views.generic import RedirectView
from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi

# Swagger/OpenAPI Schema
schema_view = get_schema_view(
    openapi.Info(
        title="E-School Management API",
        default_version='v1',
        description="API REST complète pour la plateforme scolaire digitale",
        terms_of_service="https://www.eschool.rdc/terms/",
        contact=openapi.Contact(email="contact@eschool.rdc"),
        license=openapi.License(name="Proprietary License"),
    ),
    public=True,
    permission_classes=(permissions.AllowAny,),
)

# URL de l'admin personnalisée (voir settings.DJANGO_ADMIN_URL, ex. secret-admin-xyz en prod)
_admin_path = getattr(settings, 'DJANGO_ADMIN_URL', 'admin').strip().strip('/') or 'admin'

def admin_redirect(request):
    """Redirection vers l'admin avec slash final"""
    from django.shortcuts import redirect
    return redirect(f'/{_admin_path}/', permanent=True)

def favicon_view(request):
    """Réponse vide pour /favicon.ico (évite 404/502 côté proxy)."""
    return HttpResponse(status=204)

urlpatterns = [
    path('favicon.ico', favicon_view),
    # Admin : avec slash final (obligatoire pour Django admin)
    path(f'{_admin_path}/', admin.site.urls),
    # Redirection sans slash → avec slash (ex. /africa-admin-xyw → /africa-admin-xyw/)
    path(_admin_path, admin_redirect),
    
    # API Documentation
    re_path(r'^swagger(?P<format>\.json|\.yaml)$', schema_view.without_ui(cache_timeout=0), name='schema-json'),
    path('swagger/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),
    path('redoc/', schema_view.with_ui('redoc', cache_timeout=0), name='schema-redoc'),
    
    # API Routes
    path('api/auth/', include('apps.accounts.urls')),
    path('api/accounts/', include('apps.accounts.urls')),  # Alias pour cohérence
    path('api/schools/', include('apps.schools.urls')),
    path('api/enrollment/', include('apps.enrollment.urls')),
    path('api/academics/', include('apps.academics.urls')),
    path('api/elearning/', include('apps.elearning.urls')),
    path('api/library/', include('apps.library.urls')),
    path('api/payments/', include('apps.payments.urls')),
    path('api/communication/', include('apps.communication.urls')),
    path('api/meetings/', include('apps.meetings.urls')),
    path('api/tutoring/', include('apps.tutoring.urls')),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)
