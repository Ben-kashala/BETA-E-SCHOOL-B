from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    CustomTokenObtainPairView, UserViewSet,
    TeacherViewSet, ParentViewSet, StudentViewSet,
    bulletin_pdf_download, platform_settings,
)

router = DefaultRouter()
router.register(r'users', UserViewSet, basename='user')
router.register(r'teachers', TeacherViewSet, basename='teacher')
router.register(r'parents', ParentViewSet, basename='parent')
router.register(r'students', StudentViewSet, basename='student')

urlpatterns = [
    path('login/', CustomTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('platform-settings/', platform_settings, name='platform-settings'),
    # Route explicite pour bulletin_pdf (prioritaire sur le routeur pour éviter 404)
    path('students/<int:pk>/bulletin_pdf/', bulletin_pdf_download, name='student-bulletin-pdf'),
    path('', include(router.urls)),
]
