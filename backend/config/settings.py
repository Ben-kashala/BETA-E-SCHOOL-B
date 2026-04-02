"""
Django settings for e-school.
"""
import os
from pathlib import Path
from datetime import timedelta
from decouple import config
import dj_database_url

# Build paths inside the project like this: BASE_DIR / 'subdir'.
BASE_DIR = Path(__file__).resolve().parent.parent

# SECURITY WARNING: Garder la clé sécret utiliser en production secrète!
SECRET_KEY = config('SECRET_KEY', default='django-insecure-change-me-in-production')

# SECURITY WARNING: ne pas exécuter avec debug activé en production!
# Sur Railway, on s'appuie en général sur les variables d'environnement pour forcer `DEBUG=False`.
DEBUG = config('DEBUG', default=True, cast=bool)

_allowed_hosts_raw = config('ALLOWED_HOSTS', default='localhost,127.0.0.1')
# Liste d'hôtes autorisés pour Django.
# En prod, il faut idéalement mettre votre domaine/hostname, sinon Django peut refuser les requêtes.
ALLOWED_HOSTS = [s.strip() for s in _allowed_hosts_raw.split(',') if s.strip()]
# Sur Railway (PORT défini), si ALLOWED_HOSTS n'a pas été personnalisé, accepter tout pour éviter DisallowedHost
if os.environ.get('PORT') and _allowed_hosts_raw == 'localhost,127.0.0.1':
    ALLOWED_HOSTS = ['*']

# URL de l'admin Django (en production sur Railway : définir DJANGO_ADMIN_URL à une valeur secrète)
# Ex. DJANGO_ADMIN_URL=secret-admin-xyz123 → https://votredomaine.com/secret-admin-xyz123/
# Objectif : réduire le risque d'attaques automatiques sur `/admin/`.
DJANGO_ADMIN_URL = config('DJANGO_ADMIN_URL', default='admin').strip().strip('/') or 'admin'

# Application definition
# Note : les applis locales sont chargées après les dépendances tierces.
# Vérifie que tes applis/middlewares restent dans le bon ordre si tu modifies la structure.
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    
    # Third party
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'django_filters',
    'drf_yasg',
    'phonenumber_field',
    'axes',  # Protection force brute sur l'admin Django
    
    # Local apps
    'apps.accounts.apps.AccountsConfig',
    'apps.schools',
    'apps.enrollment',
    'apps.academics',
    'apps.elearning',
    'apps.library',
    'apps.payments',
    'apps.communication',
    'apps.meetings',
    'apps.tutoring',
]

MIDDLEWARE = [
    # Middlewares "standards" Django / sécurité / performance
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'apps.accounts.middleware.AutoLogoutMiddleware',
    'apps.accounts.middleware.PlatformLockMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    # Custom middleware multi-tenant (important : il doit être exécuté avant les dépendances qui
    # utilisent `request`/`school` pour le filtrage des données)
    'apps.schools.middleware.TenantMiddleware',
    # Protection force brute admin (doit être en dernier pour capturer correctement les échecs)
    'axes.middleware.AxesMiddleware',
]

# Routage principal (mapping URL Django)
ROOT_URLCONF = 'config.urls'

# Templates : on charge les templates au niveau projet + templates dans chaque app (`APP_DIRS=True`)
TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

# WSGI = mode sync (utilisé par Gunicorn).
WSGI_APPLICATION = 'config.wsgi.application'

# Database - Railway fournit DATABASE_URL, sinon on utilise les variables individuelles
DATABASE_URL = config('DATABASE_URL', default=None)

def convert_railway_internal_to_public(database_url):
    """
    Convertit l'URL interne Railway (postgres.railway.internal) en URL publique.
    
    IMPORTANT : En production sur Railway, l'URL interne fonctionne parfaitement.
    Cette conversion est uniquement pour le développement local avec 'railway run'.
    
    Méthodes de conversion (par ordre de priorité) :
    1. Si RAILWAY_PUBLIC_DATABASE_URL est défini, l'utiliser directement
    2. Si RAILWAY_PUBLIC_HOSTNAME est défini, remplacer le hostname dans l'URL
    3. Si POSTGRES_URL (variable Railway alternative) existe et est publique, l'utiliser
    4. Sinon, retourner l'URL originale (erreur de connexion attendue en local)
    """
    # Si aucune URL n'est fournie, on renvoie tel quel (le code retournera ensuite l'autre branche DATABASES).
    if not database_url:
        return database_url
    
    # Détecter si on est sur Railway (production) via les variables d'environnement Railway
    railway_env = os.environ.get('RAILWAY_ENVIRONMENT')
    railway_deployment_id = os.environ.get('RAILWAY_DEPLOYMENT_ID')
    port = os.environ.get('PORT')  # Railway définit toujours PORT
    
    # Si on est sur Railway (production), utiliser l'URL telle quelle
    if (railway_env or railway_deployment_id) and port:
        # On est sur Railway en production, l'URL interne est correcte
        return database_url
    
    # Si l'URL contient l'hostname interne Railway (et qu'on n'est pas en production Railway)
    if 'postgres.railway.internal' in database_url:
        # Méthode 1 : URL publique complète fournie (depuis .env ou variables Railway)
        public_url = config('RAILWAY_PUBLIC_DATABASE_URL', default=None)
        if public_url and 'postgres.railway.internal' not in public_url:
            return public_url
        
        # Méthode 2 : Vérifier POSTGRES_URL (variable alternative Railway)
        postgres_url = config('POSTGRES_URL', default=None)
        if postgres_url and 'postgres.railway.internal' not in postgres_url:
            return postgres_url
        
        # Méthode 3 : Hostname public fourni, remplacer dans l'URL
        public_hostname = config('RAILWAY_PUBLIC_HOSTNAME', default=None)
        if public_hostname:
            import re
            # Remplacer postgres.railway.internal par l'hostname public
            converted_url = re.sub(
                r'@postgres\.railway\.internal',
                f'@{public_hostname}',
                database_url
            )
            return converted_url
        
        # Méthode 4 : Aucune conversion disponible
        # En local, cela causera une erreur de connexion
        # L'utilisateur doit obtenir l'URL publique depuis Railway
        if DEBUG:
            import warnings
            warnings.warn(
                "DATABASE_URL contient 'postgres.railway.internal' (URL interne Railway).\n"
                "Pour se connecter depuis votre machine locale avec 'railway run', vous devez :\n"
                "1. Obtenir l'URL publique depuis Railway Dashboard → PostgreSQL → Connect → Public Network\n"
                "2. Ajouter RAILWAY_PUBLIC_DATABASE_URL dans les variables Railway (pas dans .env local)\n"
                "   Ou définir RAILWAY_PUBLIC_HOSTNAME avec l'hostname public\n"
                "Voir CONFIGURER_DATABASE_URL_PUBLIQUE.md pour plus d'informations.",
                UserWarning
            )
    
    return database_url

if DATABASE_URL:
    # Convertir l'URL interne en URL publique si nécessaire
    DATABASE_URL = convert_railway_internal_to_public(DATABASE_URL)
    DATABASES = {
        'default': dj_database_url.parse(DATABASE_URL, conn_max_age=600, conn_health_checks=True)
    }
else:
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': config('DB_NAME', default='eschool_db'),
            'USER': config('DB_USER', default='postgres'),
            'PASSWORD': config('DB_PASSWORD', default='postgres'),
            'HOST': config('DB_HOST', default='localhost'),
            'PORT': config('DB_PORT', default='5432'),
        }
    }

# For development, use SQLite
# En dev, si `USE_SQLITE=True`, on remplace la config DB par SQLite.
# En prod (Railway), n'active pas cette option.
if DEBUG and config('USE_SQLITE', default=False, cast=bool):
    DATABASES = {
        'default': {
            'ENGINE': 'django.db.backends.sqlite3',
            'NAME': BASE_DIR / 'db.sqlite3',
        }
    }

# Password validation
AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
    },
]

# Internationalisation
# Paramètres i18n (langue + timezone).
# `TIME_ZONE` est fixée à 'Africa/Kinshasa' pour coller au contexte de votre plateforme.
LANGUAGE_CODE = 'fr-fr'
TIME_ZONE = 'Africa/Kinshasa'
USE_I18N = True
USE_TZ = True

# Static files (CSS, JavaScript, Images)
# `STATIC_ROOT` est le dossier de sortie pour `collectstatic`.
# WhiteNoise sert ensuite à servir les fichiers statiques directement via Gunicorn.
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STORAGES = {
    'default': {
        'BACKEND': 'django.core.files.storage.FileSystemStorage',
    },
    'staticfiles': {
        'BACKEND': 'whitenoise.storage.CompressedStaticFilesStorage',
    },
}

# Media files
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# Default primary key field type
# Type de clé primaire par défaut pour les modèles Django.
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# Custom User Model
# Modèle utilisateur personnalisé (obligatoire si tu as `accounts.User`).
AUTH_USER_MODEL = 'accounts.User'

# Backends d'authentification (axes en premier pour bloquer les IP/utilisateurs après trop d'échecs)
AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesStandaloneBackend',
    'django.contrib.auth.backends.ModelBackend',
]

# django-axes : limitation des tentatives de connexion (admin Django)
AXES_FAILURE_LIMIT = 5  # 5 échecs = blocage
AXES_COOLOFF_TIME = 1   # 1 heure de blocage
# Paramètres de verrouillage : par couple (utilisateur + IP) - remplace AXES_LOCK_OUT_BY_COMBINATION_USER_AND_IP
AXES_LOCKOUT_PARAMETERS = ['username', 'ip_address']
AXES_ONLY_ADMIN_SITE = True  # uniquement sur l'admin Django (pas sur l'API JWT)
AXES_ENABLE_ACCESS_FAILURE_LOG = True  # log des échecs
# Note: AXES_USE_USER_AGENT est déprécié, supprimé (ne pas inclure 'user_agent' dans AXES_LOCKOUT_PARAMETERS)

# REST Framework
# Configuration DRF :
# - authentification : JWT
# - permission : vérifie d'abord le verrouillage "platform lock", puis exige l'utilisateur authentifié
# - pagination et filtres standards
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'apps.accounts.permissions.PlatformLockPermission',  # Vérifie le verrouillage avant tout
        'rest_framework.permissions.IsAuthenticated',
    ),
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 20,
    'DEFAULT_FILTER_BACKENDS': (
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ),
}

# JWT Settings
# Durées de vie des tokens JWT.
# - Access : 24h
# - Refresh : 7 jours
# Attention : la rotation du refresh token change le comportement côté client.
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=24),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=7),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
}

# CORS Settings — frontend (React) peut appeler l'API depuis ces origines
# En production : définir CORS_ALLOWED_ORIGINS ou laisser la valeur par défaut (e-school.africaits.com + localhost)
# Si tu changes l'URL front (React/Vite), pense à mettre à jour les origines.
CORS_ALLOWED_ORIGINS = config(
    'CORS_ALLOWED_ORIGINS',
    default='http://localhost:3000,http://localhost:8081,https://e-school.africaits.com,http://e-school.africaits.com',
    cast=lambda v: [s.strip() for s in v.split(',') if s.strip()]
)
CORS_ALLOW_CREDENTIALS = True
# Headers explicitement autorisés (utile avec certains navigateurs / environnements).
CORS_ALLOW_HEADERS = [
    'accept',
    'accept-encoding',
    'authorization',
    'content-type',
    'dnt',
    'origin',
    'user-agent',
    'x-csrftoken',
    'x-requested-with',
    'x-school-code',  # Header personnalisé pour le multi-tenant
]

# CSRF Settings - Required for Django Admin in production (Django 4+ : inclure le schéma https://)
# Sur Railway, définir dans Variables : CSRF_TRUSTED_ORIGINS=https://votre-app.up.railway.app,https://e-school.africaits.com
# Utilisé pour les requêtes CSRF vers l'admin (et potentiellement d'autres vues dépendant de CSRF).
CSRF_TRUSTED_ORIGINS = config(
    'CSRF_TRUSTED_ORIGINS',
    default='http://localhost:3000,http://localhost:8081,https://e-school.africaits.com,http://e-school.africaits.com',
    cast=lambda v: [s.strip() for s in v.split(',') if s.strip()]
)

# Derrière un proxy (Railway, etc.) : Django doit faire confiance au header X-Forwarded-Proto pour HTTPS
# Si ce header n'est pas correctement géré, tu peux avoir des soucis de cookies sécurisés et de redirections.
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')

# Session Settings - Important pour Django Admin
# Ces paramètres visent surtout l'admin : cookies sécurisés, durée, etc.
SESSION_COOKIE_SECURE = not DEBUG  # True en production (HTTPS uniquement)
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = 'Lax'
SESSION_SAVE_EVERY_REQUEST = True
AUTO_LOGOUT_DELAY = 30 * 60  # 30 minutes d'inactivité pour l'admin

# CSRF Cookie Settings
# Dans ton projet, vous choisissez d'exposer le token CSRF à JS (cookie accessible).
# Vérifie la compatibilité côté front (React).
CSRF_COOKIE_SECURE = not DEBUG  # True en production (HTTPS uniquement)
CSRF_COOKIE_HTTPONLY = False  # False pour permettre JavaScript d'accéder au token
CSRF_USE_SESSIONS = False  # Utiliser les cookies CSRF (pas les sessions)

# File Upload Settings
# Limites de taille (en mémoire) pour les uploads.
FILE_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB
DATA_UPLOAD_MAX_MEMORY_SIZE = 10 * 1024 * 1024  # 10MB

# Configuration Celery (pour les tâches async)
CELERY_BROKER_URL = config('CELERY_BROKER_URL', default='redis://localhost:6379/0')
CELERY_RESULT_BACKEND = config('CELERY_RESULT_BACKEND', default='redis://localhost:6379/0')

# Payment — Mobile Money (Airtel, Orange, M-Pesa). Clés API globales (jamais hardcodées).
# Chaque école configure son numéro de réception dans SchoolPaymentMethod (admin).
AIRTEL_API_KEY = config('AIRTEL_API_KEY', default='')
AIRTEL_API_SECRET = config('AIRTEL_API_SECRET', default='')
AIRTEL_CALLBACK_URL = config('AIRTEL_CALLBACK_URL', default='')
AIRTEL_API_BASE_URL = config('AIRTEL_API_BASE_URL', default='')

ORANGE_API_KEY = config('ORANGE_API_KEY', default='')
ORANGE_API_SECRET = config('ORANGE_API_SECRET', default='')
ORANGE_CALLBACK_URL = config('ORANGE_CALLBACK_URL', default='')
ORANGE_API_BASE_URL = config('ORANGE_API_BASE_URL', default='')

MPESA_API_KEY = config('MPESA_API_KEY', default='')
MPESA_API_SECRET = config('MPESA_API_SECRET', default='')
MPESA_CALLBACK_URL = config('MPESA_CALLBACK_URL', default='')
MPESA_API_BASE_URL = config('MPESA_API_BASE_URL', default='')

# URL du frontend (redirections, liens dans les mails)
FRONTEND_URL = config('FRONTEND_URL', default='http://localhost:5173')

# SMS/WhatsApp (Twilio)
# Paramètres Twilio : à injecter via variables d'environnement (pas en dur).
TWILIO_ACCOUNT_SID = config('TWILIO_ACCOUNT_SID', default='')
TWILIO_AUTH_TOKEN = config('TWILIO_AUTH_TOKEN', default='')
TWILIO_PHONE_NUMBER = config('TWILIO_PHONE_NUMBER', default='')

# Email Configuration
# Ici vous privilégiez par défaut l'email en "console" (pratique en dev).
# En prod, configure EMAIL_HOST/EMAIL_HOST_PASSWORD + `EMAIL_BACKEND` adapté.
EMAIL_BACKEND = config('EMAIL_BACKEND', default='django.core.mail.backends.console.EmailBackend')
EMAIL_HOST = config('EMAIL_HOST', default='smtp.gmail.com')
EMAIL_PORT = config('EMAIL_PORT', default=587, cast=int)
EMAIL_USE_TLS = config('EMAIL_USE_TLS', default=True, cast=bool)
EMAIL_HOST_USER = config('EMAIL_HOST_USER', default='')
EMAIL_HOST_PASSWORD = config('EMAIL_HOST_PASSWORD', default='')
DEFAULT_FROM_EMAIL = config('DEFAULT_FROM_EMAIL', default='noreply@eschool.rdc')

# Mots de passe par défaut pour les parents et élèves
DEFAULT_PARENT_PASSWORD = config('DEFAULT_PARENT_PASSWORD', default='Parent@@')
DEFAULT_STUDENT_PASSWORD = config('DEFAULT_STUDENT_PASSWORD', default='Eleve@@')

# Logging
# Configuration de logging : vous surchargerez probablement depuis `config/logging_config.py`.
LOGGING_CONFIG = None
import logging.config
from .logging_config import LOGGING
logging.config.dictConfig(LOGGING)
