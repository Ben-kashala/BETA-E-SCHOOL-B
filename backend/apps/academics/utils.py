"""
Utility functions for academics (PDF generation, class ranking, etc.)
"""
import os
from decimal import Decimal
from io import BytesIO
from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db.models import Q
from reportlab.lib.pagesizes import letter, A4
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer, Image
from reportlab.lib.styles import getSampleStyleSheet
from .models import ReportCard, Grade, GradeBulletin
from apps.accounts.models import Student
from apps.schools.models import SchoolClass, ClassSubject, StudentClassEnrollment


def get_class_ranking_map(school_class, academic_year):
    """
    Pour une classe et une année, retourne { student_id: {'rank': int, 'percentage': float} }.
    Utilisé pour enrichir l'historique des classes et la génération du bulletin PDF.
    """
    if not school_class or not (academic_year or '').strip():
        return {}
    ac_year = (academic_year or '').strip()
    class_subjects = ClassSubject.objects.filter(school_class=school_class).select_related('subject')
    max_per_subject = {cs.subject_id: (cs.period_max or 20) * 8 for cs in class_subjects}
    subject_ids = list(max_per_subject.keys())
    total_max = sum(max_per_subject.values()) or 1
    enrollment_ids = set(StudentClassEnrollment.objects.filter(
        school_class=school_class
    ).values_list('student_id', flat=True).distinct())
    bulletin_ids = set(GradeBulletin.objects.filter(
        school_class=school_class, academic_year=ac_year
    ).values_list('student_id', flat=True).distinct())
    student_ids = list(enrollment_ids | bulletin_ids)
    if not student_ids:
        return {}
    students = Student.objects.filter(id__in=student_ids).select_related('user')
    bulletins = GradeBulletin.objects.filter(
        student__in=students,
        academic_year=ac_year,
        subject_id__in=subject_ids,
    ).filter(Q(school_class=school_class) | Q(school_class__isnull=True)).select_related('student', 'subject')
    by_student = {}
    for b in bulletins:
        sid = b.student_id
        if sid not in by_student:
            by_student[sid] = {}
        by_student[sid][b.subject_id] = (b.total_general or Decimal('0'))
    rows = []
    for s in students:
        pts = sum(by_student.get(s.id, {}).values())
        pct = (float(pts) / total_max * 100) if total_max else 0
        name = (s.user.get_full_name() or s.user.username) if s.user else f'Élève #{s.id}'
        rows.append({'student_id': s.id, 'student_name': name, 'percentage': round(pct, 2)})
    rows.sort(key=lambda x: (-sum(by_student.get(x['student_id'], {}).values()), x['student_name']))
    for i, r in enumerate(rows, 1):
        r['rank'] = i
    return {r['student_id']: {'rank': r['rank'], 'percentage': r['percentage']} for r in rows}


def _build_bulletin_header_with_logos(story, styles, logo_width=1.15 * inch, logo_height=0.75 * inch, spacer_after=0.06 * inch):
    """
    Ajoute l'en-tête RDC avec le drapeau à gauche et les armoiries à droite,
    comme sur le bulletin officiel (format compact une page).
    """
    from reportlab.lib.styles import ParagraphStyle
    small_title = ParagraphStyle(
        name="BulletinTitle",
        parent=styles["Title"],
        fontSize=9,
        leading=11,
        spaceAfter=0,
    )
    title_text = (
        "<b>REPUBLIQUE DEMOCRATIQUE DU CONGO<br/>"
        "MINISTERE DE L'ENSEIGNEMENT PRIMAIRE, SECONDAIRE ET PROFESSIONNEL</b>"
    )
    title = Paragraph(title_text, small_title)

    static_root = getattr(settings, "STATIC_ROOT", None) or os.path.join(settings.BASE_DIR, "static")
    bulletins_dir = os.path.join(static_root, "bulletins")

    def _first_existing(*candidates):
        for name in candidates:
            path = os.path.join(bulletins_dir, name)
            if os.path.exists(path):
                return path
        return None

    left_path = _first_existing("rdc_flag.png", "Drapeau.png")
    right_path = _first_existing("rdc_arms.png", "Armoirie.png")

    def _img_or_spacer(path, w, h):
        if path and os.path.exists(path):
            return Image(path, width=w, height=h)
        return Spacer(w, h)

    left_img = _img_or_spacer(left_path, logo_width, logo_height)
    right_img = _img_or_spacer(right_path, logo_width, logo_height)

    header_table = Table(
        [[left_img, title, right_img]],
        colWidths=[logo_width, None, logo_width],
    )
    header_table.setStyle(
        TableStyle(
            [
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (0, 0), (0, 0), "LEFT"),
                ("ALIGN", (1, 0), (1, 0), "CENTER"),
                ("ALIGN", (2, 0), (2, 0), "RIGHT"),
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
            ]
        )
    )
    story.append(header_table)
    story.append(Spacer(1, spacer_after))


def generate_bulletin_grade_pdf(student, school_class, academic_year):
    """
    Génère le bulletin PDF (notes RDC) pour un élève, une classe et une année.
    Retourne un BytesIO (à envoyer en téléchargement, non enregistré).
    """
    ac_year = (academic_year or "").strip()
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []

    # En-tête officiel avec logos
    school = getattr(student.user, "school", None)
    school_name = getattr(school, "name", None) or "-"
    _build_bulletin_header_with_logos(story, styles)

    resolved_class = school_class or getattr(student, "school_class", None)
    class_name = resolved_class.name if resolved_class else "N/A"
    header = f"<b>BULLETIN DE LA {class_name}</b> &nbsp;&nbsp; <b>ANNÉE SCOLAIRE :</b> {ac_year}"
    story.append(Paragraph(header, styles["Heading3"]))
    story.append(Spacer(1, 0.1 * inch))

    info = f"""
    <b>École:</b> {school_name}<br/>
    <b>Élève:</b> {student.user.get_full_name() if student.user else 'N/A'} &nbsp;&nbsp;
    <b>Matricule:</b> {getattr(student, 'student_id', '') or '-'} &nbsp;&nbsp;
    <b>Classe:</b> {class_name}
    """
    story.append(Paragraph(info, styles["Normal"]))
    story.append(Spacer(1, 0.25 * inch))

    # Tableau des notes (GradeBulletin pour cette classe et année)
    grades_qs = GradeBulletin.objects.filter(
        student=student,
        academic_year=ac_year,
    ).filter(Q(school_class=resolved_class) | Q(school_class__isnull=True)).select_related("subject")

    headers = [
        'BRANCHES',
        '1ère P.', '2ème P.', 'EXAM.', 'TOT. S1',
        '3ème P.', '4ème P.', 'EXAM.', 'TOT. S2',
        'T.G.', 'Repêch. %'
    ]
    headers = headers
    data = [headers]

    # Regroupement par domaine à partir de ClassSubject pour cette classe
    class_subjects = []
    if resolved_class:
        class_subjects = list(
            ClassSubject.objects.filter(school_class=resolved_class).select_related("subject")
        )
    cs_by_subject_id = {cs.subject_id: cs for cs in class_subjects}

    domains = {}
    for g in grades_qs:
        subj = g.subject
        if not subj:
            continue
        cs = cs_by_subject_id.get(subj.id)
        domain_label = (getattr(cs, "domain", None) or "AUTRES").upper()
        domains.setdefault(domain_label, []).append((g, cs))

    def _grade_value(grade_obj, field, default="-"):
        v = getattr(grade_obj, field, None)
        if v is not None and v != "":
            try:
                return str(Decimal(str(v)).quantize(Decimal("0.01")))
            except Exception:
                return default
        return default

    # Tri des matières dans chaque domaine par note de base (period_max) décroissante
    for dom, items in domains.items():
        items.sort(
            key=lambda tpl: getattr(tpl[1], "period_max", getattr(tpl[0].subject, "period_max", 20)),
            reverse=True,
        )

    def _domain_weight(items):
        total = 0
        for _, cs in items:
            base = getattr(cs, "period_max", None)
            if base is None and cs and hasattr(cs, "subject"):
                base = getattr(cs.subject, "period_max", 20)
            if base is None:
                base = 20
            total += int(base)
        return total

    sorted_domains = sorted(domains.items(), key=lambda kv: _domain_weight(kv[1]), reverse=True)

    if sorted_domains:
        for dom, items in sorted_domains:
            # Ligne de domaine
            data.append([dom] + [""] * (len(headers) - 1))
            for g, cs in items:
                data.append(
                    [
                        g.subject.name if g.subject else "-",
                        _grade_value(g, "s1_p1"),
                        _grade_value(g, "s1_p2"),
                        _grade_value(g, "s1_exam"),
                        _grade_value(g, "total_s1"),
                        _grade_value(g, "s2_p3"),
                        _grade_value(g, "s2_p4"),
                        _grade_value(g, "s2_exam"),
                        _grade_value(g, "total_s2"),
                        _grade_value(g, "total_general"),
                        _grade_value(g, "reclamation_score"),
                    ]
                )
    else:
        # Repli : comportement d'origine, simple liste de matières
        for g in grades_qs.order_by("subject__name"):
            data.append(
                [
                    g.subject.name if g.subject else "-",
                    _grade_value(g, "s1_p1"),
                    _grade_value(g, "s1_p2"),
                    _grade_value(g, "s1_exam"),
                    _grade_value(g, "total_s1"),
                    _grade_value(g, "s2_p3"),
                    _grade_value(g, "s2_p4"),
                    _grade_value(g, "s2_exam"),
                    _grade_value(g, "total_s2"),
                    _grade_value(g, "total_general"),
                    _grade_value(g, "reclamation_score"),
                ]
            )

    if len(data) <= 1:
        # Aucun domaine / matière : on garde le modèle brouillon avec quelques lignes vides
        for _ in range(6):
            data.append([""] * len(headers))

    col_widths = [1.4 * inch] + [0.5 * inch] * 10
    table = Table(data, colWidths=col_widths)
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.grey),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.whitesmoke),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 8),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
            ]
        )
    )
    story.append(table)

    story.append(Spacer(1, 0.2*inch))
    # Place et Pourcentage (depuis le classement)
    ranking = get_class_ranking_map(school_class, ac_year).get(student.id, {})
    rank = ranking.get('rank')
    pct = ranking.get('percentage')
    place = f"{rank}" if rank is not None else '-'
    pct_str = f"{pct} %" if pct is not None else '-'
    story.append(Paragraph(
        f"<b>Place:</b> {place} &nbsp;&nbsp; <b>Pourcentage:</b> {pct_str}",
        styles['Normal']
    ))

    doc.build(story)
    buffer.seek(0)
    return buffer


def generate_bulletin_rdc_pdf(report_card):
    """
    Génère le bulletin au format officiel RDC (une page), conforme au modèle fourni :
    2 semestres, 4 périodes (Trav. journaliers), 2 examens, TOT. S1/S2, T.G., repêchage ;
    MAXIMA GÉNÉRAUX, TOTAUX, POURCENTAGE, PLACE, APPLICATION, CONDUITE, décisions.
    """
    from decimal import Decimal
    from reportlab.lib.styles import ParagraphStyle
    buffer = BytesIO()
    # Une seule page, marges réduites pour tenir comme le modèle officiel
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=0.35 * inch,
        rightMargin=0.35 * inch,
        topMargin=0.35 * inch,
        bottomMargin=0.35 * inch,
    )
    styles = getSampleStyleSheet()
    style_compact = ParagraphStyle(name="Compact", parent=styles["Normal"], fontSize=7, leading=8, spaceAfter=0)
    style_heading_compact = ParagraphStyle(name="HeadingCompact", parent=styles["Heading3"], fontSize=8, leading=10, spaceAfter=0)
    story = []

    student = report_card.student
    school = getattr(student.user, "school", None)
    school_name = getattr(school, "name", None) or "-"
    province = getattr(school, "province", None) or "-"
    city = getattr(school, "city", None) or "-"
    commune = getattr(school, "commune", None) or "-"
    code_ecole = getattr(school, "code", None) or "-"

    # En-tête officiel RDC avec logos (format compact)
    _build_bulletin_header_with_logos(story, styles)

    # Identité école / élève — grille comme modèle officiel
    user = student.user
    full_name = user.get_full_name()
    sex = getattr(student, "gender", None)
    if not sex and hasattr(user, "gender"):
        sex = getattr(user, "gender")
    if sex == "M":
        sex_label = "M"
    elif sex == "F":
        sex_label = "F"
    else:
        sex_label = "-"
    place_of_birth = getattr(student, "place_of_birth", None) or "-"
    dob = getattr(user, "date_of_birth", None)
    dob_str = dob.strftime("%d/%m/%Y") if dob else "-"

    classe_name = student.school_class.name if student.school_class else "CLASSE"

    info_data = [
        ["N° ID.", "", "", "", "", ""],
        ["PROVINCE EDUCATIONNELLE :", province, "", "", "", ""],
        ["VILLE :", city, "ELEVE :", full_name, "SEXE :", sex_label],
        ["COMMUNE /TER (1) :", commune, "NE (E) A :", place_of_birth, "LE :", dob_str],
        ["ECOLE :", school_name, "CLASSE :", classe_name, "", ""],
        ["CODE :", code_ecole, "N° PERM. :", student.student_id or "-", "", ""],
    ]
    col_widths_info = [1.5 * inch, 2.4 * inch, 1.0 * inch, 1.8 * inch, 0.75 * inch, 1.0 * inch]
    info_table = Table(info_data, colWidths=col_widths_info)
    info_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
            ]
        )
    )
    story.append(info_table)
    story.append(Spacer(1, 0.06 * inch))

    # Ligne "BULLETIN DE LA ... ANNÉE SCOLAIRE ..."
    header_text = f"BULLETIN DE LA {classe_name} &nbsp;&nbsp; ANNÉE SCOLAIRE : {report_card.academic_year}"
    story.append(Paragraph(f"<b>{header_text}</b>", style_heading_compact))
    story.append(Spacer(1, 0.06 * inch))

    # Tableau des notes (GradeBulletin) regroupé par domaine et trié par note de base
    grades_qs = GradeBulletin.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
    ).select_related("subject", "school_class")

    # Classe utilisée pour retrouver les domaines/note de base
    resolved_class = student.school_class
    class_subjects = []
    if resolved_class:
        class_subjects = list(
            ClassSubject.objects.filter(school_class=resolved_class).select_related("subject")
        )
    cs_by_subject_id = {cs.subject_id: cs for cs in class_subjects}

    # En-têtes multi-lignes comme sur le modèle officiel
    col_labels = [
        "BRANCHES",
        "1ère P.", "2ème P.", "EXAM.", "TOT. S1",
        "3ème P.", "4ème P.", "EXAM.", "TOT. S2",
        "T.G.", "Repêch. %",
    ]
    data = []
    # Ligne 1 : titres de blocs
    data.append(
        [
            "BRANCHES",
            "PREMIER SEMESTRE", "", "", "",
            "SECOND SEMESTRE", "", "", "",
            "TOTAL GENERAL",
            "EXAMEN DE REPECHAGE",
        ]
    )
    # Ligne 2 : MAX / TRAVAUX JOURNAL / MAX EXAM / TOTAL
    data.append(
        [
            "",
            "MAX.", "TRAVAUX JOURNAL.", "MAX. EXAM.", "TOTAL",
            "MAX.", "TRAVAUX JOURNAL.", "MAX. EXAM.", "TOTAL",
            "",
            "%",
        ]
    )
    # Ligne 3 : 1ère P., 2ème P., EXAM, TOT S1, 3ème, 4ème, EXAM, TOT S2, T.G., Sign. Prof.
    data.append(
        [
            "",
            "1ère P.", "2ème P.", "EXAM.", "TOT. S1",
            "3ème P.", "4ème P.", "EXAM.", "TOT. S2",
            "T.G.",
            "Sign. Prof.",
        ]
    )

    def _grade_value(g, field, default="-"):
        v = getattr(g, field, None)
        if v is not None and v != "":
            try:
                return str(Decimal(str(v)).quantize(Decimal("0.01")))
            except Exception:
                return default
        return default

    # Regroupement par domaine
    domains = {}
    for g in grades_qs:
        subj = g.subject
        if not subj:
            continue
        cs = cs_by_subject_id.get(subj.id)
        domain_label = (getattr(cs, "domain", None) or "AUTRES").upper()
        domains.setdefault(domain_label, []).append((g, cs))

    # Tri des matières dans chaque domaine par note de base décroissante
    for dom, items in domains.items():
        items.sort(
            key=lambda tpl: getattr(tpl[1], "period_max", getattr(tpl[0].subject, "period_max", 20)),
            reverse=True,
        )

    def _domain_weight(items):
        total = 0
        for _, cs in items:
            base = getattr(cs, "period_max", None)
            if base is None and cs and hasattr(cs, "subject"):
                base = getattr(cs.subject, "period_max", 20)
            if base is None:
                base = 20
            total += int(base)
        return total

    sorted_domains = sorted(domains.items(), key=lambda kv: _domain_weight(kv[1]), reverse=True)

    if sorted_domains:
        for dom, items in sorted_domains:
            data.append([dom] + [""] * (len(col_labels) - 1))
            for g, cs in items:
                data.append(
                    [
                        g.subject.name if g.subject else "-",
                        _grade_value(g, "s1_p1"),
                        _grade_value(g, "s1_p2"),
                        _grade_value(g, "s1_exam"),
                        _grade_value(g, "total_s1"),
                        _grade_value(g, "s2_p3"),
                        _grade_value(g, "s2_p4"),
                        _grade_value(g, "s2_exam"),
                        _grade_value(g, "total_s2"),
                        _grade_value(g, "total_general"),
                        _grade_value(g, "reclamation_score"),
                    ]
                )
    else:
        # Repli : tableau simple ordonné par matière
        for g in grades_qs.order_by("subject__name"):
            data.append(
                [
                    g.subject.name if g.subject else "-",
                    _grade_value(g, "s1_p1"),
                    _grade_value(g, "s1_p2"),
                    _grade_value(g, "s1_exam"),
                    _grade_value(g, "total_s1"),
                    _grade_value(g, "s2_p3"),
                    _grade_value(g, "s2_p4"),
                    _grade_value(g, "s2_exam"),
                    _grade_value(g, "total_s2"),
                    _grade_value(g, "total_general"),
                    _grade_value(g, "reclamation_score"),
                ]
            )

    if len(data) <= 3:
        for _ in range(8):
            data.append([""] * len(col_labels))
    else:
        # Limiter à 12 lignes de matières + 3 en-têtes pour tenir sur une page
        max_data_rows = 12
        if len(data) > 3 + max_data_rows:
            data = data[: 3 + max_data_rows]

    col_widths = [1.5 * inch] + [0.48 * inch] * 10
    table = Table(data, colWidths=col_widths)
    table.setStyle(
        TableStyle(
            [
                ("SPAN", (0, 0), (0, 2)),
                ("SPAN", (1, 0), (4, 0)),
                ("SPAN", (5, 0), (8, 0)),
                ("SPAN", (9, 0), (9, 1)),
                ("BACKGROUND", (0, 0), (-1, 2), colors.grey),
                ("TEXTCOLOR", (0, 0), (-1, 2), colors.whitesmoke),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("FONTNAME", (0, 0), (-1, 2), "Helvetica-Bold"),
                ("FONTSIZE", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
            ]
        )
    )
    story.append(table)

    # Bloc MAXIMA GÉNÉRAUX / TOTAUX / POURCENTAGE / PLACE / APPLICATION / CONDUITE / SIGNATURE (modèle officiel)
    story.append(Spacer(1, 0.06 * inch))
    app = report_card.application if report_card.application is not None else ""
    cond = report_card.conduite if report_card.conduite is not None else ""
    place_txt = f"{report_card.rank or ''} / {report_card.total_students or ''}".strip(" /")
    # Pourcentage approximé : moyenne /20 → %
    pct_txt = ""
    if report_card.average_score is not None:
        try:
            pct_val = float(report_card.average_score) * 5.0
            pct_txt = f"{pct_val:.2f} %"
        except Exception:
            pct_txt = ""

    # Tableau pied de page : MAXIMA GÉNÉRAUX, TOTAUX, POURCENTAGE, PLACE, APPLICATION, CONDUITE, SIGNATURE (modèle officiel)
    footer_data = [
        ["MAXIMA GENERAUX"] + [""] * 11,
        ["TOTAUX"] + [""] * 11,
        ["POURCENTAGE"] + [str(pct_txt)] + [""] * 10,
        ["PLACE / NBRE D'ELEVES"] + [str(place_txt)] + [""] * 10,
        ["APPLICATION"] + [str(app)] + [""] * 10,
        ["CONDUITE"] + [str(cond)] + [""] * 10,
        ["SIGNATURE"] + [""] * 11,
    ]
    footer_table = Table(
        footer_data,
        colWidths=[1.65 * inch] + [0.32 * inch] * 11,
    )
    footer_table.setStyle(
        TableStyle(
            [
                ("GRID", (0, 0), (-1, -1), 0.5, colors.black),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
                ("FONTSIZE", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 2),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("BACKGROUND", (0, 0), (-1, 0), colors.whitesmoke),
            ]
        )
    )
    story.append(footer_table)

    story.append(Spacer(1, 0.05 * inch))

    rep_matiere = report_card.reclamation_subject.name if report_card.reclamation_subject else "........................................................"
    rep_line = (
        "L'élève ne pourra passer dans la classe supérieure s'il n'a subi avec succès "
        f"un examen de repêchage en {rep_matiere}(1)"
    )
    story.append(Paragraph(f"- {rep_line}", style_compact))
    story.append(Paragraph("- L'élève passe dans la classe supérieure (1)", style_compact))
    story.append(Paragraph("- L'élève double la classe (1)", style_compact))
    story.append(Spacer(1, 0.04 * inch))

    sig_city = city or "........................................"
    sig_table = Table(
        [
            ["", "", "", ""],
            [
                "Signature de l'élève",
                "Sceau de l'Ecole",
                f"Fait à {sig_city}, le ....../....../20......",
                "Chef d'Etablissement",
            ],
        ],
        colWidths=[2.0 * inch, 1.8 * inch, 2.6 * inch, 1.8 * inch],
    )
    sig_table.setStyle(
        TableStyle(
            [
                ("LINEABOVE", (0, 0), (-1, 0), 0.5, colors.black),
                ("ALIGN", (0, 1), (-1, 1), "CENTER"),
                ("FONTNAME", (0, 1), (-1, 1), "Helvetica"),
                ("FONTSIZE", (0, 1), (-1, 1), 7),
            ]
        )
    )
    story.append(sig_table)

    story.append(Spacer(1, 0.04 * inch))
    story.append(Paragraph("(1) Biffer la mention inutile.", style_compact))
    story.append(Paragraph("Note importante : Le bulletin est sans valeur s'il est raturé ou surchargé.", style_compact))
    story.append(Paragraph("Interdiction formelle de reproduire ce bulletin sous peine des sanctions prévues par la loi. IGE/P.S./012", style_compact))

    doc.build(story)
    buffer.seek(0)
    filename = f"academics/report_cards/bulletin_rdc_{report_card.id}.pdf"
    file_content = ContentFile(buffer.read())
    return default_storage.save(filename, file_content)


def generate_report_card_pdf(report_card):
    """Generate PDF report card"""
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4)
    styles = getSampleStyleSheet()
    story = []
    
    # Title
    title = Paragraph(f"<b>BULLETIN SCOLAIRE</b>", styles['Title'])
    story.append(title)
    story.append(Spacer(1, 0.2*inch))
    
    # Student info
    student = report_card.student
    student_info = f"""
    <b>Élève:</b> {student.user.get_full_name()}<br/>
    <b>Matricule:</b> {student.student_id}<br/>
    <b>Classe:</b> {student.school_class.name if student.school_class else 'N/A'}<br/>
    <b>Année scolaire:</b> {report_card.academic_year}<br/>
    <b>Trimestre:</b> {report_card.get_term_display()}<br/>
    """
    story.append(Paragraph(student_info, styles['Normal']))
    story.append(Spacer(1, 0.3*inch))
    
    # Grades table
    grades = Grade.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
        term=report_card.term
    )
    
    if grades.exists():
        data = [['Matière', 'Contrôle continu', 'Examen', 'Total', 'Appréciation']]
        
        for grade in grades:
            appreciation = get_appreciation(grade.total_score)
            data.append([
                grade.subject.name,
                str(grade.continuous_assessment),
                str(grade.exam_score) if grade.exam_score else '-',
                str(grade.total_score),
                appreciation
            ])
        
        # Summary row
        data.append([
            '<b>TOTAL</b>',
            '',
            '',
            f'<b>{report_card.average_score}/20</b>',
            get_appreciation(report_card.average_score)
        ])
        
        table = Table(data, colWidths=[2*inch, 1*inch, 1*inch, 1*inch, 1.5*inch])
        table.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.grey),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('FONTSIZE', (0, 0), (-1, 0), 12),
            ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
            ('BACKGROUND', (0, 1), (-1, -2), colors.beige),
            ('GRID', (0, 0), (-1, -1), 1, colors.black),
            ('FONTSIZE', (0, 1), (-1, -1), 10),
        ]))
        
        story.append(table)
        story.append(Spacer(1, 0.3*inch))
    
    # Comments
    if report_card.teacher_comment:
        story.append(Paragraph("<b>Commentaire de l'enseignant:</b>", styles['Heading3']))
        story.append(Paragraph(report_card.teacher_comment, styles['Normal']))
        story.append(Spacer(1, 0.2*inch))
    
    if report_card.principal_comment:
        story.append(Paragraph("<b>Commentaire du directeur:</b>", styles['Heading3']))
        story.append(Paragraph(report_card.principal_comment, styles['Normal']))
    
    # Rank
    if report_card.rank:
        story.append(Spacer(1, 0.2*inch))
        rank_text = f"<b>Rang:</b> {report_card.rank}/{report_card.total_students}"
        story.append(Paragraph(rank_text, styles['Normal']))
    
    doc.build(story)
    buffer.seek(0)
    
    filename = f"academics/report_cards/report_{report_card.id}.pdf"
    file_content = ContentFile(buffer.read())
    saved_file = default_storage.save(filename, file_content)
    
    return saved_file


def get_appreciation(score):
    """Get appreciation based on score"""
    if score >= 16:
        return "Excellent"
    elif score >= 14:
        return "Très bien"
    elif score >= 12:
        return "Bien"
    elif score >= 10:
        return "Assez bien"
    elif score >= 8:
        return "Passable"
    else:
        return "Insuffisant"
