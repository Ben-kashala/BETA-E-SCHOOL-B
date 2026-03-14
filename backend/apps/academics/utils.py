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


def _bulletin_logo_path(filename):
    """Retourne le chemin absolu du logo si trouvé (static/bulletins ou STATIC_ROOT/bulletins)."""
    base = getattr(settings, "BASE_DIR", None)
    if base:
        p = os.path.join(str(base), "static", "bulletins", filename)
        if os.path.isfile(p):
            return p
    static_root = getattr(settings, "STATIC_ROOT", None)
    if static_root:
        p = os.path.join(str(static_root), "bulletins", filename)
        if os.path.isfile(p):
            return p
    # Repli : depuis backend (parent de config), static/bulletins
    this_dir = os.path.dirname(os.path.abspath(__file__))
    for _ in range(3):
        parent = os.path.dirname(this_dir)
        p = os.path.join(parent, "static", "bulletins", filename)
        if os.path.isfile(p):
            return p
        this_dir = parent
    return None


def generate_bulletin_rdc_pdf(report_card):
    """
    Génère le bulletin au format officiel RDC (une page), identique au modèle
    IGE/P.S./012 (1ère Année des Humanités Scientifiques).
    """
    from reportlab.lib.enums import TA_CENTER
    from reportlab.lib.styles import ParagraphStyle

    buffer = BytesIO()
    margin_pt = 0.5 * inch

    def _make_border_canvas(margin):
        class BorderCanvas(canvas.Canvas):
            def showPage(self):
                self.saveState()
                self.setStrokeColor(colors.black)
                self.setLineWidth(1.5)
                w, h = self._pagesize
                m = margin
                self.rect(m, m, w - 2 * m, h - 2 * m)
                self.restoreState()
                super().showPage()
        return BorderCanvas

    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=margin_pt,
        rightMargin=margin_pt,
        topMargin=margin_pt,
        bottomMargin=margin_pt,
        canvasmaker=_make_border_canvas(margin_pt),
    )
    styles = getSampleStyleSheet()
    # En-tête : texte en blanc sur fond sombre (ou noir pour impression)
    style_title_main = ParagraphStyle(
        "title_main",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=11,
        leading=12,
        fontName="Helvetica-Bold",
        textColor=colors.black,
        spaceBefore=0,
        spaceAfter=1,
    )
    style_title_sub = ParagraphStyle(
        "title_sub",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=9,
        leading=10,
        fontName="Helvetica-Bold",
        textColor=colors.black,
        spaceBefore=0,
        spaceAfter=0,
    )
    style_small = ParagraphStyle(
        "small",
        parent=styles["Normal"],
        fontSize=7,
    )
    story = []

    student = report_card.student
    user = student.user
    school = getattr(user, "school", None)

    school_name = getattr(school, "name", "") if school else ""
    province = getattr(school, "province", "") if school else ""
    city = getattr(school, "city", "") if school else ""
    commune = getattr(school, "commune", "") if school else ""
    code_ecole = getattr(school, "code", "") if school else ""

    # ----- EN-TÊTE : Drapeau gauche, 3 lignes centrées, Armoiries droite -----
    logo_w, logo_h = 1.15 * inch, 0.85 * inch
    left_logo_path = (
        _bulletin_logo_path("Drapeau.png")
        or _bulletin_logo_path("drapeau_RDC.png")
        or _bulletin_logo_path("rdc_flag.png")
    )
    right_logo_path = (
        _bulletin_logo_path("Armoirie.png")
        or _bulletin_logo_path("armoiries_RDC.png")
        or _bulletin_logo_path("rdc_arms.png")
    )

    def _logo_or_spacer(path):
        if path:
            try:
                return Image(path, width=logo_w, height=logo_h)
            except Exception:
                pass
        return Spacer(logo_w, logo_h)

    logo_left = _logo_or_spacer(left_logo_path)
    logo_right = _logo_or_spacer(right_logo_path)
    title_block = [
        Paragraph("<b>REPUBLIQUE DEMOCRATIQUE DU CONGO</b>", style_title_main),
        Paragraph("<b>MINISTERE DE L'EDUCATION NATIONALE</b>", style_title_sub),
        Paragraph("<b>ET NOUVELLE CITOYENNETE</b>", style_title_sub),
    ]
    header_table = Table(
        [[logo_left, title_block, logo_right]],
        colWidths=[logo_w, None, logo_w],
    )
    header_table.setStyle(TableStyle([
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(header_table)
    # Ligne horizontale fine noire sous l'en-tête (pleine largeur)
    line_table = Table([[""]], colWidths=[7 * inch])
    line_table.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, -1), 1, colors.black),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(line_table)
    story.append(Spacer(1, 4))

    # ----- BLOC INFOS : 2 colonnes (gauche: N° ID., PROVINCE, VILLE, COMMUNE/TER, ECOLE, CODE | droite: ELEVE, SEXE, NE(E) A, LE, CLASSE, N° PERM.) -----
    full_name = user.get_full_name() or ""
    classe = student.school_class.name if student.school_class else ""
    dob = getattr(user, "date_of_birth", None)
    dob_str = dob.strftime("%d/%m/%Y") if dob else "…./…./………."
    sex_label = "M" if getattr(student, "gender", None) == "M" else "F" if getattr(student, "gender", None) == "F" else "…"
    place_of_birth = getattr(student, "place_of_birth", None) or ""
    n_perm = student.student_id or ""

    # Deux colonnes : gauche (N° ID., PROVINCE, VILLE, COMMUNE/TER, ECOLE, CODE) | droite (ELEVE, SEXE, NE (E) A, LE, CLASSE, N° PERM.)
    info_data = [
        ["N° ID.", "", "ELEVE :", full_name],
        ["PROVINCE EDUCATIONNELLE :", province, "SEXE :", sex_label],
        ["VILLE :", city, "NE (E) A :", place_of_birth],
        ["COMMUNE/TER (1) :", commune, "LE", dob_str],
        ["ECOLE :", school_name, "CLASSE :", classe],
        ["CODE :", code_ecole, "N° PERM.", n_perm],
    ]
    info_table = Table(
        info_data,
        colWidths=[1.5 * inch, 2.3 * inch, 1.1 * inch, 2.2 * inch],
    )
    info_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (2, 0), (2, -1), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 5))

    # ----- TITRE : BULLETIN DE LA ... ANNEE SCOLAIRE ... (encadré bordure noire fine) -----
    titre_bulletin = f"BULLETIN DE LA {classe or '1ère ANNEE DES HUMANITES SCIENTIFIQUES'}   ANNEE SCOLAIRE {report_card.academic_year or '2024 - 2025'}"
    style_titre = ParagraphStyle(
        "bulletin_titre",
        parent=styles["Normal"],
        alignment=TA_CENTER,
        fontSize=9,
        leading=10,
        fontName="Helvetica-Bold",
        spaceBefore=6,
        spaceAfter=6,
    )
    titre_para = Paragraph(f"<b>{titre_bulletin}</b>", style_titre)
    titre_wrapper = Table([[titre_para]], colWidths=[7 * inch])
    titre_wrapper.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.5, colors.black),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("BACKGROUND", (0, 0), (-1, -1), colors.white),
    ]))
    story.append(titre_wrapper)
    story.append(Spacer(1, 5))

    # ----- TABLEAU DES NOTES (structure officielle) -----
    # Colonnes : BRANCHES | S1: 1ère P, 2e P, 3e P, 4e P, %, Sign., Prof., MAX., EXAM., TOTAL | S2: idem | TOTAL | EXAMEN DE REPECHAGE
    num_cols = 23
    header_row1 = [
        "BRANCHES",
        "PREMIER SEMESTRE", "", "", "", "", "", "", "", "",
        "SECOND SEMESTRE", "", "", "", "", "", "", "", "", "",
        "TOTAL",
        "EXAMEN DE\nREPECHAGE",
    ]
    header_row2 = [
        "",
        "1ère P.", "2e P.", "3e P.", "4e P.", "%", "Sign.", "Prof.", "MAX.", "EXAM.", "TOTAL",
        "1ère P.", "2e P.", "3e P.", "4e P.", "%", "Sign.", "Prof.", "MAX.", "EXAM.", "TOTAL",
        "",
        "",
    ]
    header_row1 = header_row1[:num_cols]
    header_row2 = header_row2[:num_cols]

    data_rows = [header_row1, header_row2]

    grades = GradeBulletin.objects.filter(
        student=student,
        academic_year=report_card.academic_year,
    ).select_related("subject")
    resolved_class = student.school_class
    cs_by_subject_id = {}
    if resolved_class:
        for cs in ClassSubject.objects.filter(school_class=resolved_class).select_related("subject"):
            cs_by_subject_id[cs.subject_id] = cs

    def val(v):
        if v is None:
            return ""
        return str(Decimal(str(v)).quantize(Decimal("0.01")))

    # Données par domaine (comme sur le modèle officiel)
    domains = {}
    for g in grades:
        if not g.subject:
            continue
        cs = cs_by_subject_id.get(g.subject_id)
        domain = (getattr(cs, "domain", None) or "AUTRES").strip().upper() or "AUTRES"
        domains.setdefault(domain, []).append((g, cs))

    for domain, items in sorted(domains.items(), key=lambda x: x[0]):
        data_rows.append([domain] + [""] * (num_cols - 1))
        for g, cs in items:
            max_p = getattr(cs, "period_max", None) or 20
            row = [
                g.subject.name,
                val(g.s1_p1), val(g.s1_p2), "", "",
                "", "", "",
                str(int(max_p)), val(g.s1_exam), val(g.total_s1),
                val(g.s2_p3), val(g.s2_p4), "", "",
                "", "", "",
                str(int(max_p)), val(g.s2_exam), val(g.total_s2),
                val(g.total_general),
                val(g.reclamation_score) or "",
            ]
            row = row[:num_cols]
            while len(row) < num_cols:
                row.append("")
            data_rows.append(row[:num_cols])
        # Sous-total domaine (optionnel, si on veut afficher comme le PDF)
        # data_rows.append(["Sous - Total", ...])

    col_widths = [
        1.5 * inch,
        0.32 * inch, 0.32 * inch, 0.32 * inch, 0.32 * inch, 0.26 * inch, 0.26 * inch, 0.26 * inch, 0.3 * inch, 0.3 * inch, 0.35 * inch,
        0.32 * inch, 0.32 * inch, 0.32 * inch, 0.32 * inch, 0.26 * inch, 0.26 * inch, 0.26 * inch, 0.3 * inch, 0.3 * inch, 0.35 * inch,
        0.38 * inch,
        0.42 * inch,
    ]
    table = Table(data_rows, colWidths=col_widths[:num_cols])
    table.setStyle(TableStyle([
        ("SPAN", (0, 0), (0, 1)),
        ("SPAN", (1, 0), (10, 0)),
        ("SPAN", (11, 0), (20, 0)),
        ("SPAN", (21, 0), (21, 1)),
        ("SPAN", (22, 0), (22, 1)),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTNAME", (0, 0), (-1, 1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 6),
        ("BACKGROUND", (0, 0), (-1, 1), colors.HexColor("#e8e8e8")),
    ]))
    story.append(table)
    story.append(Spacer(1, 5))

    # ----- MAXIMA GÉNÉRAUX, TOTAUX, POURCENTAGE, PLACE, APPLICATION, CONDUITE, SIGNATURE -----
    pct = ""
    if report_card.average_score is not None:
        pct = f"{float(report_card.average_score) * 5:.2f} %"
    place = f"{report_card.rank or ''} / {report_card.total_students or ''}"
    appli = str(report_card.application) if report_card.application is not None else ""
    conduite = str(report_card.conduite) if report_card.conduite is not None else ""

    footer_data = [
        ["MAXIMA GENERAUX", ""],
        ["TOTAUX", ""],
        ["- PASSE (1)", ""],
        ["- DOUBLE (1)", ""],
        ["LE…/.../20….", ""],
        ["Chef d'Etablissement", "Sceau de l'Ecole"],
        ["POURCENTAGE", pct],
        ["PLACE / NBRE D'ELEVES", place],
        ["APPLICATION", appli],
        ["CONDUITE", conduite],
        ["SIGNATURE", ""],
    ]
    footer_table = Table(
        footer_data,
        colWidths=[2.0 * inch, 4.5 * inch],
    )
    footer_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(footer_table)
    story.append(Spacer(1, 6))

    # ----- DÉCISIONS ET NOTES LÉGALES -----
    story.append(Paragraph(
        "- L'élève ne pourra passer dans la classe supérieure s'il n'a subi avec succès un examen de repêchage en..................................................................................................……….",
        style_small,
    ))
    story.append(Paragraph("…………………………………………………………………………………………………….............................................................................................................................................................................................(1)", style_small))
    story.append(Paragraph("- L'élève passe dans la classe supérieure (1)", style_small))
    story.append(Paragraph("- L'élève double la classe (1)", style_small))
    story.append(Spacer(1, 4))
    story.append(Paragraph("(1) Biffer la mention inutile.", style_small))
    story.append(Paragraph("Note importante : Le bulletin est sans valeur s'il est raturé ou surchargé.", style_small))
    story.append(Paragraph("IGE/P.S./012", style_small))
    story.append(Paragraph(
        "Interdiction formelle de reproduire ce bulletin sous peine des sanctions prévues par la loi.",
        style_small,
    ))
    story.append(Spacer(1, 4))
    story.append(Paragraph("Sceau de l'Ecole", style_small))
    story.append(Paragraph(f"Fait à {city or '……………………'}, le……..…/…………/20……..", style_small))
    story.append(Paragraph("Chef d'Etablissement,", style_small))
    story.append(Paragraph("Signature de l'élève", style_small))

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
