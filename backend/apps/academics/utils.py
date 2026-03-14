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
    watermark_path = _bulletin_logo_path("Armoirie.png") or _bulletin_logo_path("rdc_arms.png")

    def _make_border_canvas(margin):
        class BorderCanvas(canvas.Canvas):
            def showPage(self):
                self.saveState()
                w, h = self._pagesize
                self.setFillColor(colors.HexColor("#eef6ff"))
                self.rect(0, 0, w, h, stroke=0, fill=1)
                if watermark_path and os.path.isfile(watermark_path):
                    try:
                        self.setFillAlpha(0.08)
                        size = 3.2 * inch
                        self.drawImage(
                            watermark_path,
                            (w - size) / 2,
                            (h - size) / 2 - 0.5 * inch,
                            width=size,
                            height=size,
                            preserveAspectRatio=True,
                            mask="auto",
                        )
                        self.setFillAlpha(1)
                    except Exception:
                        pass
                self.setStrokeColor(colors.black)
                self.setLineWidth(1.5)
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
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#dce8f5")),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.black),
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

    # ----- BLOC INFOS : structure du modèle officiel -----
    full_name = user.get_full_name() or ""
    classe = student.school_class.name if student.school_class else "1ère ANNEE DES HUMANITES SCIENTIFIQUES"
    dob = getattr(user, "date_of_birth", None)
    dob_str = dob.strftime("%d/%m/%Y") if dob else "....../....../.........."
    sex_label = "M" if getattr(student, "gender", None) == "M" else "F" if getattr(student, "gender", None) == "F" else "........"
    place_of_birth = getattr(student, "place_of_birth", None) or ""
    n_perm = student.student_id or ""

    id_cells = ["N° ID."] + [""] * 22
    id_table = Table([id_cells], colWidths=[0.55 * inch] + [0.28 * inch] * 22)
    id_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
        ("FONTNAME", (0, 0), (0, 0), "Helvetica-Bold"),
    ]))
    story.append(id_table)

    province_table = Table(
        [["PROVINCE EDUCATIONNELLE :", province]],
        colWidths=[2.35 * inch, 4.35 * inch],
    )
    province_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("FONTNAME", (0, 0), (0, 0), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
    ]))
    story.append(province_table)

    info_data = [
        ["VILLE :", city, "ELEVE :", full_name, "SEXE :", sex_label],
        ["COMMUNE /TER (1) :", commune, "NE (E) A :", place_of_birth, "LE", dob_str],
        ["ECOLE :", school_name, "CLASSE :", classe, "", ""],
        ["CODE :", code_ecole, "N° PERM.", n_perm, "", ""],
    ]
    info_table = Table(
        info_data,
        colWidths=[1.25 * inch, 2.05 * inch, 1.0 * inch, 1.9 * inch, 0.6 * inch, 0.9 * inch],
    )
    info_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTNAME", (2, 0), (2, -1), "Helvetica-Bold"),
        ("FONTNAME", (4, 0), (4, -1), "Helvetica-Bold"),
        ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))
    story.append(info_table)
    story.append(Spacer(1, 3))

    # ----- TITRE : BULLETIN DE LA ... ANNEE SCOLAIRE ... (encadré bordure noire fine) -----
    titre_bulletin = f"BULLETIN DE LA 1ère ANNEE DES HUMANITES SCIENTIFIQUES    ANNEE SCOLAIRE {report_card.academic_year or '2024 - 2025'}"
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

    # ----- TABLEAU DES NOTES (structure officielle : 14 colonnes, 3 niveaux d'en-têtes) -----
    # Colonnes : BRANCHES | PREMIER SEMESTRE (MAX., TRAVAUX JOURNAL. 1ère P./2è P., MAX. EXAM., TOTAL) | SECOND (3è P./4è P., idem) | TOTAL GENERAL | EXAMEN DE REPECHAGE (%, Sign. Prof.)
    HEADER_DARK = colors.HexColor("#dce8f5")
    HEADER_LIGHT = colors.HexColor("#f3f7fd")
    SOUS_TOTAL_BG = None

    num_cols = 14
    header_row1 = [
        "BRANCHES",
        "PREMIER SEMESTRE", "", "", "", "",
        "SECOND SEMESTRE", "", "", "", "",
        "TOTAL\nGENERAL",
        "EXAMEN DE REPECHAGE", "",
    ]
    header_row2 = [
        "",
        "MAX.", "TRAVAUX JOURNAL.", "", "MAX. EXAM.", "TOTAL",
        "MAX.", "TRAVAUX JOURNAL.", "", "MAX. EXAM.", "TOTAL",
        "",
        "%", "Sign. Prof.",
    ]
    header_row3 = [
        "",
        "", "1ère P.", "2è P.", "", "",
        "", "3è P.", "4è P.", "", "",
        "", "", "",
    ]
    header_row1 = header_row1[:num_cols]
    header_row2 = header_row2[:num_cols]
    header_row3 = header_row3[:num_cols]

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

    # Structure fixe 1ère Scientifique (modèle officiel) : (domain, sub_domain|None, subject_label|None, max_period)
    # subject_label "Sous - Total" = ligne sous-total (fond noir) ; dernier élément = tuple (max_s1, exam_s1, total_s1, max_s2, exam_s2, total_s2, total_gen)
    BULLETIN_1ERE_SCIENCE = [
        ("DOMAINE DES SCIENCES", "Sous-domaine des mathématiques", "Algèbre, Stat. & Analy.", 40),
        (None, None, "Géométrie et Trigo.", 20),
        (None, None, "Dessin scientifique", 10),
        (None, None, "Sous - Total", (70, 140, 280, 70, 140, 280, 560)),
        (None, "Sous-domaine des Sciences de la Vie et de la Terre", "Biologie générale", 20),
        (None, None, "microbiologie", 10),
        (None, None, "Géologie", 10),
        (None, None, "Sous - Total", (40, 80, 160, 40, 80, 160, 320)),
        (None, "Sous-domaine des Sciences Physiques, Technologie et TIC", "Chimie", 30),
        (None, None, "Physique", 30),
        (None, None, "Tech. d'Info et Com (TIC)", 10),
        (None, None, "Sous - Total", (70, 140, 280, 70, 140, 280, 560)),
        ("DOMAINE DES LANGUES", None, "Français", 50),
        (None, None, "Anglais", 30),
        (None, None, "Sous - Total", (80, 160, 320, 80, 160, 320, 640)),
        ("DOMAINE DE L'UNIVERS SOCIAL ET ENVIRONNEMENT", None, "Ed. civ. & morale", 10),
        (None, None, "Géographie", 20),
        (None, None, "Histoire", 20),
        (None, None, "Education à la vie (1)", 10),
        (None, None, "Sociologie africaine", 20),
        (None, None, "Religion (1)", 10),
        (None, None, "Sous - Total", (90, 180, 360, 90, 180, 360, 720)),
        ("DOMAINE DU DEVELOPPEMENT PERSONNEL", None, "Educat. phys. & sport.", 10),
        (None, None, "Sous - Total", (10, 20, 40, 10, 20, 40, 80)),
    ]

    # Map GradeBulletin par nom de matière (normalisé)
    grades_by_name = {}
    for g in grades:
        if g.subject:
            n = (g.subject.name or "").strip()
            grades_by_name[n] = (g, cs_by_subject_id.get(g.subject_id))
            # alias courants
            if "Algèbre" in n or "Algebre" in n:
                grades_by_name["Algèbre, Stat. & Analy."] = (g, cs_by_subject_id.get(g.subject_id))
            if "Géométrie" in n or "Geometrie" in n:
                grades_by_name["Géométrie et Trigo."] = (g, cs_by_subject_id.get(g.subject_id))
            if "Dessin" in n:
                grades_by_name["Dessin scientifique"] = (g, cs_by_subject_id.get(g.subject_id))
            if "Biologie" in n:
                grades_by_name["Biologie générale"] = (g, cs_by_subject_id.get(g.subject_id))
            if "Français" in n or "Francais" in n:
                grades_by_name["Français"] = (g, cs_by_subject_id.get(g.subject_id))
            if "Anglais" in n:
                grades_by_name["Anglais"] = (g, cs_by_subject_id.get(g.subject_id))
            if "Chimie" in n:
                grades_by_name["Chimie"] = (g, cs_by_subject_id.get(g.subject_id))
            if "Physique" in n:
                grades_by_name["Physique"] = (g, cs_by_subject_id.get(g.subject_id))
            if "TIC" in n or "Info" in n:
                grades_by_name["Tech. d'Info et Com (TIC)"] = (g, cs_by_subject_id.get(g.subject_id))

    def make_data_row(label, max_p, g_ctx):
        """Une ligne de données : label, S1 (max, 1ère P, 2è P, exam, total), S2 (idem), total général, %, Sign. Prof."""
        if g_ctx:
            g, cs = g_ctx
            max_p = max_p or (getattr(cs, "period_max", None) or 20)
            return [
                label,
                str(int(max_p)), val(g.s1_p1), val(g.s1_p2), val(g.s1_exam), val(g.total_s1),
                str(int(max_p)), val(g.s2_p3), val(g.s2_p4), val(g.s2_exam), val(g.total_s2),
                val(g.total_general),
                val(g.reclamation_score) or "", "",
            ]
        if max_p is not None:
            max_exam = max_p * 2
            total_s = max_p * 4
            tot_gen = max_p * 8
            return [
                label,
                str(int(max_p)), "", "", str(int(max_exam)), str(int(total_s)),
                str(int(max_p)), "", "", str(int(max_exam)), str(int(total_s)),
                str(int(tot_gen)), "", "",
            ]
        return [label] + [""] * (num_cols - 1)

    data_rows = [header_row1, header_row2, header_row3]

    for domain, sub_domain, subject_label, max_p in BULLETIN_1ERE_SCIENCE:
        if domain:
            current_domain = domain
            data_rows.append([domain] + [""] * (num_cols - 1))
        if sub_domain:
            current_sub = sub_domain
            data_rows.append([sub_domain] + [""] * (num_cols - 1))
        if subject_label == "Sous - Total":
            # Ligne sous-total : valeurs officielles (max_s1, exam_s1, total_s1, max_s2, exam_s2, total_s2, total_gen)
            if isinstance(max_p, (list, tuple)) and len(max_p) >= 7:
                m1, e1, t1, m2, e2, t2, tg = max_p[0], max_p[1], max_p[2], max_p[3], max_p[4], max_p[5], max_p[6]
                row = [
                    "Sous - Total",
                    str(m1), "", "", str(e1), str(t1),
                    str(m2), "", "", str(e2), str(t2),
                    str(tg), "", "",
                ]
            else:
                row = ["Sous - Total"] + [""] * (num_cols - 1)
            row = row[:num_cols]
            while len(row) < num_cols:
                row.append("")
            data_rows.append(row[:num_cols])
            continue
        if subject_label:
            g_ctx = grades_by_name.get(subject_label)
            row = make_data_row(subject_label, max_p, g_ctx)
            row = row[:num_cols]
            while len(row) < num_cols:
                row.append("")
            data_rows.append(row[:num_cols])

    col_widths = [
        1.55 * inch,
        0.35 * inch, 0.4 * inch, 0.35 * inch, 0.4 * inch, 0.38 * inch,
        0.35 * inch, 0.4 * inch, 0.35 * inch, 0.4 * inch, 0.38 * inch,
        0.45 * inch,
        0.35 * inch, 0.4 * inch,
    ]
    table = Table(data_rows, colWidths=col_widths[:num_cols])
    tbl_style = [
        ("SPAN", (0, 0), (0, 2)),
        ("SPAN", (1, 0), (5, 0)),
        ("SPAN", (6, 0), (10, 0)),
        ("SPAN", (11, 0), (11, 2)),
        ("SPAN", (12, 0), (13, 0)),
        ("SPAN", (2, 1), (3, 1)),
        ("SPAN", (7, 1), (8, 1)),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("ALIGN", (0, 0), (0, -1), "LEFT"),
        ("ALIGN", (1, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTNAME", (0, 0), (-1, 2), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 6),
        ("BACKGROUND", (0, 0), (-1, 0), HEADER_DARK),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.black),
        ("BACKGROUND", (0, 1), (-1, 2), HEADER_LIGHT),
    ]
    # Lignes "Sous - Total" en gras
    for r in range(3, len(data_rows)):
        if len(data_rows[r]) and data_rows[r][0] == "Sous - Total":
            tbl_style.append(("FONTNAME", (0, r), (-1, r), "Helvetica-Bold"))
    # Lignes domaine / sous-domaine en bandeau bleu clair
    for r in range(3, len(data_rows)):
        cell0 = (data_rows[r][0] if data_rows[r] else "").strip()
        if cell0 and cell0 != "Sous - Total" and (
            cell0.startswith("DOMAINE") or cell0.startswith("Sous-domaine")
        ):
            tbl_style.append(("BACKGROUND", (0, r), (-1, r), HEADER_DARK))
            tbl_style.append(("TEXTCOLOR", (0, r), (-1, r), colors.black))
            tbl_style.append(("FONTNAME", (0, r), (-1, r), "Helvetica-Bold"))
    table.setStyle(TableStyle(tbl_style))
    story.append(table)
    story.append(Spacer(1, 5))

    # ----- SECTION RÉSUMÉ : gauche = MAXIMA, TOTAUX, POURCENTAGE, PLACE, APPLICATION, CONDUITE, SIGNATURE | droite = encadré - PASSE (1), - DOUBLE (1), LE..../....../20...., Chef d'Etablissement, Sceau de l'Ecole -----
    pct = ""
    if report_card.average_score is not None:
        pct = f"{float(report_card.average_score) * 5:.2f} %"
    place = f"{report_card.rank or ''} / {report_card.total_students or ''}"
    appli = str(report_card.application) if report_card.application is not None else ""
    conduite = str(report_card.conduite) if report_card.conduite is not None else ""

    footer_left_data = [
        ["MAXIMA GENERAUX", ""],
        ["TOTAUX", ""],
        ["POURCENTAGE", pct],
        ["PLACE / NBRE D'ELEVES", place],
        ["APPLICATION", appli],
        ["CONDUITE", conduite],
        ["SIGNATURE", ""],
    ]
    footer_left_table = Table(footer_left_data, colWidths=[1.8 * inch, 2.8 * inch])
    footer_left_table.setStyle(TableStyle([
        ("GRID", (0, 0), (-1, -1), 0.25, colors.black),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("FONTSIZE", (0, 0), (-1, -1), 7),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
    ]))
    footer_right_cells = [
        "- PASSE (1)",
        "- DOUBLE (1)",
        "LE..../....../20....",
        "Chef d'Etablissement",
        "Sceau de l'Ecole",
    ]
    footer_right_text = "\n<br/>\n".join(footer_right_cells)
    footer_right_para = Paragraph(footer_right_text, style_small)
    footer_table = Table(
        [[footer_left_table, footer_right_para]],
        colWidths=[4.6 * inch, 2.2 * inch],
    )
    footer_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (0, 0), 0),
        ("LEFTPADDING", (1, 0), (1, 0), 6),
        ("BOX", (1, 0), (1, 0), 0.5, colors.black),
        ("BACKGROUND", (1, 0), (1, 0), colors.white),
    ]))
    story.append(footer_table)
    story.append(Spacer(1, 6))

    # ----- DÉCISIONS ET MENTIONS LÉGALES (ordre comme capture 2) -----
    story.append(Paragraph(
        "- L'élève ne pourra passer dans la classe supérieure s'il n'a subi avec succès un examen de repêchage en.......................................................................................(1)",
        style_small,
    ))
    story.append(Paragraph("- L'élève passe dans la classe supérieure (1)", style_small))
    story.append(Paragraph("- L'élève double la classe (1)", style_small))
    story.append(Spacer(1, 5))
    # Ligne signatures : gauche Signature de l'élève, centre Sceau de l'Ecole, droite Fait à ... le....../....../20......
    sig_line = Table([
        [
            Paragraph("<b>Signature de l'élève</b>", style_small),
            Paragraph("<b>Sceau de l'Ecole</b>", style_small),
            Paragraph(f"Fait à {city or '..............................................'} le....../....../20......", style_small),
        ]
    ], colWidths=[2.2 * inch, 2.2 * inch, 2.6 * inch])
    sig_line.setStyle(TableStyle([
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
    ]))
    story.append(sig_line)
    story.append(Spacer(1, 4))
    story.append(Paragraph("(1) Biffer la mention inutile.", style_small))
    story.append(Paragraph("Note importante : Le bulletin est sans valeur s'il est raturé ou surchargé.", style_small))
    story.append(Paragraph(
        "<b>Interdiction formelle de reproduire ce bulletin sous peine des sanctions prévues par la loi.</b>",
        style_small,
    ))
    story.append(Spacer(1, 4))
    # En bas à droite : Chef d'Etablissement, puis IGE/P.S./012 en dessous
    story.append(Paragraph("<b>Chef d'Etablissement,</b>", ParagraphStyle("right", parent=style_small, alignment=2)))
    story.append(Paragraph("IGE/P.S./012", ParagraphStyle("right2", parent=style_small, alignment=2)))

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
