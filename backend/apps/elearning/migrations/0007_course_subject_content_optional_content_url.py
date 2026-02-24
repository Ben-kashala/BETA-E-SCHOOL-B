# Generated migration: subject/content optionnels, content_url ajouté, due_date retiré

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('elearning', '0006_assignment_submission_answer_grades'),
    ]

    operations = [
        migrations.AddField(
            model_name='course',
            name='content_url',
            field=models.URLField(blank=True, null=True, verbose_name='Lien vers le contenu (import)'),
        ),
        migrations.AlterField(
            model_name='course',
            name='content',
            field=models.TextField(blank=True, default='', verbose_name='Contenu'),
        ),
        migrations.AlterField(
            model_name='course',
            name='subject',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='courses', to='schools.subject', verbose_name='Matière'),
        ),
        migrations.RemoveField(
            model_name='course',
            name='due_date',
        ),
    ]
