"""Builds the Vulcanic project documentation PDF."""
import os
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    Flowable, Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate,
    Spacer, Table, TableStyle,
)

REPO, OUT = sys.argv[1], sys.argv[2]
SHOTS = sys.argv[3:]  # extra folders to look for images in

INK = colors.HexColor('#12161A')
MUTED = colors.HexColor('#5B6570')
LINE = colors.HexColor('#D5D8DC')
PANEL = colors.HexColor('#F2F3F1')
HEAT = colors.HexColor('#C8321A')
DARK = colors.HexColor('#0E1216')

W, H = A4
MARGIN = 22 * mm
BODY_W = W - 2 * MARGIN


def style(name, **kw):
    base = dict(fontName='Helvetica', fontSize=10.5, leading=15.5, textColor=INK)
    base.update(kw)
    return ParagraphStyle(name, **base)


BODY = style('body', spaceAfter=7)
SMALL = style('small', fontSize=9, leading=12.5, textColor=MUTED)
CELL = style('cell', fontSize=9.2, leading=12.5)
CELLB = style('cellb', fontSize=9.2, leading=12.5, fontName='Helvetica-Bold')
H1 = style('h1', fontName='Helvetica-Bold', fontSize=19, leading=23, spaceBefore=4, spaceAfter=10)
H2 = style('h2', fontName='Helvetica-Bold', fontSize=13.5, leading=17, spaceBefore=13, spaceAfter=6)
H3 = style('h3', fontName='Helvetica-Bold', fontSize=11, leading=14, spaceBefore=9, spaceAfter=4)
EYEBROW = style('eyebrow', fontName='Helvetica-Bold', fontSize=8.5, leading=11, textColor=HEAT, spaceAfter=3)
CAPTION = style('caption', fontSize=8.6, leading=11.5, textColor=MUTED, alignment=TA_CENTER, spaceBefore=4, spaceAfter=10)
BULLET = style('bullet', leftIndent=13, bulletIndent=2, spaceAfter=3.5)

story = []


def P(text, st=BODY):
    story.append(Paragraph(text, st))


def bullets(items):
    for item in items:
        story.append(Paragraph(item, BULLET, bulletText='•'))
    story.append(Spacer(1, 4))


def section(letter, title):
    story.append(PageBreak())
    P('PART %s' % letter, EYEBROW)
    P(title, H1)


def table(rows, widths, header=True, font=CELL):
    data = []
    for r, row in enumerate(rows):
        data.append([
            Paragraph(str(c), CELLB if (header and r == 0) else font) for c in row
        ])
    t = Table(data, colWidths=[w * BODY_W for w in widths], repeatRows=1 if header else 0)
    st = [
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LINEBELOW', (0, 0), (-1, -1), 0.5, LINE),
        ('TOPPADDING', (0, 0), (-1, -1), 5), ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6), ('RIGHTPADDING', (0, 0), (-1, -1), 6),
    ]
    if header:
        st += [('BACKGROUND', (0, 0), (-1, 0), PANEL), ('LINEBELOW', (0, 0), (-1, 0), 0.8, INK)]
    t.setStyle(TableStyle(st))
    story.append(t)
    story.append(Spacer(1, 9))


def find(name):
    for folder in [os.path.join(REPO, 'build/renders'), os.path.join(REPO, 'docs/screenshots'),
                   os.path.join(REPO, 'docs/markers')] + SHOTS:
        p = os.path.join(folder, name)
        if os.path.exists(p):
            return p
    return None


class Placeholder(Flowable):
    """A marked space for a screenshot taken on the test device."""

    def __init__(self, label, w, h):
        super().__init__()
        self.label, self.width, self.height = label, w, h

    def draw(self):
        c = self.canv
        c.setStrokeColor(LINE)
        c.setDash(3, 3)
        c.roundRect(0, 0, self.width, self.height, 6)
        c.setDash()
        c.setFillColor(MUTED)
        c.setFont('Helvetica-Bold', 6.8)
        c.drawCentredString(self.width / 2, self.height / 2 + 12, 'SCREENSHOT')
        c.setFont('Helvetica', 6.8)
        # Wrap the label to the box.
        words, lines, line = self.label.replace('\n', ' ').split(), [], ''
        for word in words:
            trial = (line + ' ' + word).strip()
            if c.stringWidth(trial, 'Helvetica', 6.8) > self.width - 8 and line:
                lines.append(line)
                line = word
            else:
                line = trial
        lines.append(line)
        for i, text in enumerate(lines):
            c.drawCentredString(self.width / 2, self.height / 2 - 9 * i, text)


def figure_row(items, caption, height=62 * mm):
    """items: file names, or ('placeholder', label)."""
    cells, gap = [], 5 * mm
    n = len(items)
    cell_w = (BODY_W - gap * (n - 1)) / n
    for item in items:
        if isinstance(item, tuple):
            cells.append(Placeholder(item[1], min(cell_w - 4, height * 0.52), height))
            continue
        path = find(item)
        if path is None:
            cells.append(Placeholder(item, min(cell_w, height * 0.46), height))
            continue
        img = Image(path)
        ratio = img.imageWidth / float(img.imageHeight)
        h = height
        w = h * ratio
        if w > cell_w:
            w, h = cell_w, cell_w / ratio
        img.drawWidth, img.drawHeight = w, h
        cells.append(img)
    t = Table([cells], colWidths=[cell_w + (gap if i < n - 1 else 0) for i in range(n)])
    t.setStyle(TableStyle([('ALIGN', (0, 0), (-1, -1), 'CENTER'), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                           ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0)]))
    story.append(KeepTogether([t, Paragraph(caption, CAPTION)]))


class Diagram(Flowable):
    """Boxes and arrows, described in a small grid."""

    def __init__(self, height, draw):
        super().__init__()
        self.width, self.height, self._draw = BODY_W, height, draw

    def draw(self):
        self._draw(self.canv, self.width, self.height)


def box(c, x, y, w, h, title, sub=None, fill=colors.white, bold=True, dark=False):
    c.setStrokeColor(INK if not dark else DARK)
    c.setFillColor(fill)
    c.setLineWidth(0.8)
    c.roundRect(x, y, w, h, 4, stroke=1, fill=1)
    c.setFillColor(colors.white if dark else INK)
    c.setFont('Helvetica-Bold' if bold else 'Helvetica', 8.4)
    ty = y + h / 2 + (4 if sub else -3)
    c.drawCentredString(x + w / 2, ty, title)
    if sub:
        c.setFont('Helvetica', 7.2)
        c.setFillColor(colors.HexColor('#C9CED4') if dark else MUTED)
        for i, line in enumerate(sub.split('\n')):
            c.drawCentredString(x + w / 2, ty - 10 - 8.5 * i, line)


def arrow(c, x1, y1, x2, y2, label=None):
    import math
    c.setStrokeColor(INK)
    c.setFillColor(INK)
    c.setLineWidth(0.8)
    c.line(x1, y1, x2, y2)
    a = math.atan2(y2 - y1, x2 - x1)
    s = 4.2
    p = c.beginPath()
    p.moveTo(x2, y2)
    p.lineTo(x2 - s * math.cos(a - 0.45), y2 - s * math.sin(a - 0.45))
    p.lineTo(x2 - s * math.cos(a + 0.45), y2 - s * math.sin(a + 0.45))
    p.close()
    c.drawPath(p, stroke=0, fill=1)
    if label:
        c.setFont('Helvetica', 6.8)
        c.setFillColor(MUTED)
        c.drawCentredString((x1 + x2) / 2, (y1 + y2) / 2 + 3, label)


def architecture(c, w, h):
    # Bands.
    c.setFillColor(PANEL)
    c.setStrokeColor(LINE)
    c.roundRect(0, h - 70, w, 70, 5, stroke=1, fill=1)
    c.roundRect(0, 0, w, h - 86, 5, stroke=1, fill=1)
    c.setFillColor(MUTED)
    c.setFont('Helvetica-Bold', 7.4)
    c.drawString(8, h - 13, 'ANDROID (KOTLIN)')
    c.drawString(8, h - 99, 'FLUTTER (DART)')
    bw = (w - 5 * 10) / 4.0
    top = h - 62
    names = [('ARCore session', 'planes, anchors,\nlight, camera image'),
             ('CameraX + ML Kit', 'camera preview,\ncode corners'),
             ('Gravity sensor', 'which way is up'),
             ('Media', 'speech, clips,\ngallery, capture')]
    xs = [10 + i * (bw + 10) for i in range(4)]
    for x, (t, s) in zip(xs, names):
        box(c, x, top, bw, 44, t, s)
    mid = h - 152
    mids = [('ArFrame', 'view, projection,\nanchor pose'),
            ('MarkerPose', 'homography to 3D pose,\nstabiliser'),
            ('OrbitCamera', 'explorer view'),
            ('Narrator / Gallery', 'listen, save picture')]
    for x, (t, s) in zip(xs, mids):
        box(c, x, mid, bw, 44, t, s)
    arrow(c, xs[0] + bw / 2, top, xs[0] + bw / 2, mid + 44)
    arrow(c, xs[1] + bw / 2, top, xs[1] + bw / 2, mid + 44)
    arrow(c, xs[2] + bw / 2, top, xs[1] + bw * 0.85, mid + 44)
    arrow(c, xs[3] + bw / 2, top, xs[3] + bw / 2, mid + 44)
    ry = mid - 62
    box(c, xs[0], ry, bw * 3 + 20, 40, 'SceneRenderer',
        'one software renderer for every mode: transform, cull, sort, shade, Canvas.drawVertices',
        fill=DARK, dark=True)
    for i in range(3):
        arrow(c, xs[i] + bw / 2, mid, xs[i] + bw / 2, ry + 40)
    uy = 10
    box(c, xs[0], uy, w - 20, 34, 'Interface',
        'home, console (eruption trace, trigger, toggles), pins, component sheet, view rail, guide, markers')
    arrow(c, xs[1] + bw / 2, ry, xs[1] + bw / 2, uy + 34)
    arrow(c, xs[3] + bw / 2, mid, xs[3] + bw / 2, uy + 34)


def workflow(c, w, h):
    cw = (w - 2 * 12) / 3.0
    xs = [0, cw + 12, 2 * (cw + 12)]
    bh, gap = 26, 12
    box(c, w / 2 - 70, h - bh, 140, bh, 'Launch: Home screen', fill=DARK, dark=True)
    heads = ['Place on a surface', 'On a marker', 'Just the model']
    hy = h - bh - 34
    for x, t in zip(xs, heads):
        box(c, x, hy, cw, bh, t, fill=PANEL)
        arrow(c, w / 2, h - bh, x + cw / 2, hy + bh)
    cols = [
        ['Camera permission', 'ARCore available?', 'Scan: planes and\nfeature points shown',
         'Tap: hit test,\ncreate anchor', 'Volcano anchored;\nwalk around it'],
        ['Camera permission', 'Detect and identify\nthe marker code', 'Estimate pose\nfrom four corners',
         'Level with gravity,\nsmooth', 'Volcano follows marker;\nfades when lost'],
        ['Orbit camera', 'Drag, pinch,\nview buttons', None, None, None],
    ]
    for x, col in zip(xs, cols):
        y = hy
        for step in col:
            if step is None:
                break
            ny = y - gap - bh - 4
            parts = step.split('\n')
            box(c, x, ny, cw, bh + 4, parts[0], parts[1] if len(parts) > 1 else None, bold=False)
            arrow(c, x + cw / 2, y, x + cw / 2, ny + bh + 4)
            y = ny
    # Fallback branch for phones without ARCore.
    fy = hy - 2 * (gap + bh + 4)
    c.setFont('Helvetica', 6.8)
    c.setFillColor(HEAT)
    c.drawString(xs[0] + 4, fy - 9, 'no: screen placement (tap to place)')
    # Shared bottom.
    by = 0
    box(c, 0, by, w, bh + 6, 'Shared interaction in every mode',
        'erupt / pause / reset  ·  cutaway  ·  pins and component sheet  ·  listen  ·  turn, zoom  ·  save a picture',
        fill=DARK, dark=True)


def navigation(c, w, h):
    bw, bh = 96, 24
    box(c, w / 2 - bw / 2, h - bh, bw, bh, 'Home', fill=DARK, dark=True)
    kids = ['Surface', 'Marker', '3D explorer', 'Markers', 'How it works']
    n = len(kids)
    gap = (w - n * bw) / (n - 1)
    ky = h - bh - 40
    for i, k in enumerate(kids):
        x = i * (bw + gap)
        box(c, x, ky, bw, bh, k, fill=PANEL)
        arrow(c, w / 2, h - bh, x + bw / 2, ky + bh)
    subs = {0: ['Tracked surface', 'Screen placement'], 1: ['Marker scene'], 3: ['Fullscreen marker']}
    for i, items in subs.items():
        x = i * (bw + gap)
        y = ky
        for s in items:
            ny = y - 14 - bh
            box(c, x, ny, bw, bh, s, bold=False)
            arrow(c, x + bw / 2, y, x + bw / 2, ny + bh)
            y = ny
    c.setFont('Helvetica', 7.2)
    c.setFillColor(MUTED)
    c.drawCentredString(w / 2, 4, 'Surface, Marker and 3D explorer share one scene layout: top bar, view rail, console, component sheet.')


# --------------------------------------------------------------------------
# Cover
# --------------------------------------------------------------------------
story.append(Spacer(1, 26 * mm))
P('PROJECT DOCUMENTATION', EYEBROW)
P('Vulcanic', style('cover', fontName='Helvetica-Bold', fontSize=44, leading=48, spaceAfter=6))
P('An AR-Based Interactive Volcano for Android, with Marker-Based and Markerless Tracking',
  style('coversub', fontSize=15, leading=20, textColor=MUTED, spaceAfter=18))
cover = find('screen_explorer_erupting.png')
if cover:
    img = Image(cover)
    r = img.imageWidth / float(img.imageHeight)
    img.drawHeight = 112 * mm
    img.drawWidth = 112 * mm * r
    img.hAlign = 'LEFT'
    story.append(img)
story.append(Spacer(1, 12 * mm))
table([
    ['Course', 'CSST 106 | Mixed, Augmented and Virtual Reality: Final Project'],
    ['Application', 'Vulcanic 1.2.0 for Android 13 and newer'],
    ['Source code', 'github.com/TeachDian/vulcanic'],
    ['Prepared by', '____________________________________________'],
    ['Date', '____________________________________________'],
], [0.24, 0.76], header=False)

# --------------------------------------------------------------------------
# Contents
# --------------------------------------------------------------------------
story.append(PageBreak())
P('Contents', H1)
table([
    ['A', 'Project Introduction', 'Title, description, objectives'],
    ['B', 'System Planning and Design', 'Problem, users, architecture, workflow, interface, requirements, AR design'],
    ['C', 'Application Development and Implementation', 'Tools, marker-based and markerless implementation, 3D objects, integration, challenges'],
    ['D', 'System Testing and Evaluation', 'Automated tests, device test plan, tracking and interface evaluation'],
    ['E', 'Conclusion', 'Summary, learning outcomes, recommendations'],
    ['', 'Appendix', 'Required demonstrations checklist, references'],
], [0.07, 0.40, 0.53], header=False)
P('<b>How to read this document.</b> Parts A to C and E describe the system as built. Part D contains the '
  'automated test results and a test plan with blank result columns: the tests on a physical phone are to be '
  'carried out and recorded by the project team. Dashed boxes mark where screenshots from that device belong.', SMALL)

# --------------------------------------------------------------------------
# A
# --------------------------------------------------------------------------
section('A', 'Project Introduction')
P('Project Title', H2)
P('<b>Vulcanic: An AR-Based Interactive Volcano for Android, with Marker-Based and Markerless Tracking</b>')
P('Project Description', H2)
P('Vulcanic is an Android application that places an animated, three-dimensional volcano in the user\'s '
  'surroundings through the phone\'s camera. It is the school-exhibit volcano model rebuilt in augmented '
  'reality: the user stands it on a desk, sets off an eruption, opens a cutaway to see what is underground, '
  'and taps any of its five components to read or hear what that component does.')
P('The application demonstrates both families of AR tracking:')
bullets([
    '<b>Markerless (Surface mode).</b> Google ARCore tracks the phone\'s motion, detects horizontal surfaces '
    'and anchors the volcano to the point the user taps. The user can then walk around it.',
    '<b>Marker-based (Marker mode).</b> The camera recognises a printed marker, or one shown on a second '
    'phone, and the volcano stands on it and follows it as it moves.',
    '<b>3D explorer.</b> The same model on a plain backdrop with no camera, for phones or settings where AR '
    'is not practical.',
])
P('<b>Purpose and intended users.</b> The application is a learning aid for Earth science. It is intended '
  'for junior and senior high school students studying volcanoes, for teachers who want a model to '
  'demonstrate with, and for anyone curious about how an eruption works.')
P('<b>Real-world application.</b> A physical volcano model shows a shape. It cannot show magma rising, a '
  'conduit, or a chamber, and it erupts once. An AR model can be placed on any desk, repeated as often as '
  'needed, opened up, and carried in a pocket. The Philippines sits on the Pacific Ring of Fire and has '
  'more than twenty active volcanoes, so the subject is part of the curriculum and of everyday life; the '
  'model is a stratovolcano, the type of Mayon in Albay.')
P('Project Objectives', H2)
P('<b>General objective.</b> To develop an interactive AR application that integrates marker-based and '
  'markerless tracking to present a volcano and its internal structure in the user\'s real environment.')
P('<b>Specific objectives.</b>')
bullets([
    'Recognise a custom visual marker, identify it, and display and track a 3D model on it.',
    'Detect real surfaces without a marker, let the user place the model on one, and keep it anchored.',
    'Model the volcano as five separate 3D components and integrate them into the AR scene.',
    'Animate a simplified eruption that shows magma rising, the eruption, lava flow and cooling.',
    'Provide interaction: rotation, scaling, repositioning, a cutaway view, selectable components with '
    'information, narration, and image capture.',
    'Remain usable on phones that do not support ARCore.',
])
P('<b>Technologies demonstrated.</b> Marker recognition and pose estimation, natural feature tracking, '
  'plane detection, hit testing, spatial anchoring, light estimation, real-time 3D rendering, text-to-speech '
  'and audio playback.')

# --------------------------------------------------------------------------
# B
# --------------------------------------------------------------------------
section('B', 'System Planning and Design')
P('Application Planning', H2)
P('<b>Problem addressed.</b> The internal structure of a volcano and the sequence of an eruption are hard '
  'to teach from flat diagrams, and physical models are static, fragile and show only the outside. Students '
  'need a model they can look into and watch change over time.')
P('<b>Target users and beneficiaries.</b>')
table([
    ['Group', 'How they benefit'],
    ['Students (Grades 7 to 12)', 'See the parts of a volcano in three dimensions, in their own space, and replay the eruption at will.'],
    ['Science teachers', 'A demonstration model that needs no materials and no setup beyond a phone.'],
    ['Schools with limited equipment', 'Runs on phones students already have; a printed marker is the only material, and a second phone can replace it.'],
    ['General public', 'An approachable explanation of a natural hazard that affects many communities.'],
], [0.32, 0.68])
P('System Design', H2)
P('System architecture', H3)
P('The system has two layers. The Android layer, written in Kotlin, talks to the hardware and to Google\'s '
  'tracking libraries. The Flutter layer, written in Dart, holds the application logic, draws the volcano and '
  'the interface. They communicate through platform channels. A deliberate choice was to give the three '
  'viewing modes <b>one renderer</b>: it needs only a view matrix, a projection matrix and a model matrix, '
  'and each mode supplies those from a different source.')
story.append(Diagram(284, architecture))
P('Figure 1. System architecture.', CAPTION)
P('Application workflow', H3)
story.append(Diagram(338, workflow))
P('Figure 2. Application workflow for the three modes.', CAPTION)
P('User interface and navigation', H3)
P('The interface is deliberately quiet: graphite and bone, one typeface, and vivid colour reserved for the '
  'volcano and for heat. The home screen offers one main action and two secondary ones. Every viewing mode '
  'shares the same scene layout, so a user who learns one mode knows the others.')
story.append(Diagram(150, navigation))
P('Figure 3. Navigation structure.', CAPTION)
figure_row(['screen_home.png', 'screen_explorer.png', 'screen_explorer_part.png', 'screen_guide.png'],
           'Figure 4. Home, the scene with its console and view rail, the component sheet, and the guide.',
           height=70 * mm)
table([
    ['Element', 'Purpose'],
    ['Top bar', 'Back, tracking status (a coloured dot and one word), mode buttons, save a picture.'],
    ['View rail', 'Zoom in, zoom out, quarter turn, and mode actions (Move, Recentre, view from above).'],
    ['Console', 'The eruption drawn as a seismograph trace with a playhead; the Erupt button; toggles for the cutaway and the pins.'],
    ['Pins', 'Numbered discs on the model. Tapping one selects that component.'],
    ['Component sheet', 'Name, a two-sentence summary, facts in a table, Listen, previous and next.'],
    ['Hints', 'One line of guidance above the console, for example the reason tracking is struggling.'],
], [0.24, 0.76])
P('Hardware and software requirements', H3)
table([
    ['', 'Requirement'],
    ['Phone', 'Android 13 (API 33) or newer, with a rear camera.'],
    ['For markerless tracking', 'A phone on Google\'s ARCore supported-devices list, with Google Play Services for AR installed. The app offers to install it.'],
    ['For marker-based tracking', 'Any phone with a camera. A printed marker, or a second device showing the marker full screen.'],
    ['Storage', 'About 25 MB for the installed application.'],
    ['Development machine', 'Flutter 3.47, Dart 3.13, Android SDK 36, Android Studio or the command-line tools.'],
], [0.30, 0.70])

P('AR Design', H2)
P('<b>Virtual objects.</b> The volcano is assembled from five separately modeled components:')
table([
    ['No.', 'Component', 'File', 'Triangles', 'Role in the scene'],
    ['01', 'Volcanic cone and crater', 'cone.obj', '4,284', 'The exterior; includes the cut faces shown by the cutaway.'],
    ['02', 'Ground and rock layers', 'terrain.obj', '1,136', 'The plinth, and the strata revealed by the cutaway.'],
    ['03', 'Magma chamber', 'chamber.obj', '432', 'The reservoir under the volcano.'],
    ['04', 'Main conduit', 'conduit.obj', '336', 'The passage from the chamber to the crater; fills as magma rises.'],
    ['05', 'Surface lava flow', 'lava.obj', '408', 'A ribbon down the slope along which fresh lava advances.'],
], [0.07, 0.25, 0.15, 0.12, 0.41])
P('<b>Digital content.</b> Each component has a name, a two-sentence summary, two or three facts, and a '
  'fuller explanation that is read aloud. Further content: the eruption animation, ash, steam and ejected '
  'fragments as particles, a seismograph-style timeline, and two printable markers.')
figure_row(['dormant.png', 'erupting.png', 'flowing.png'],
           'Figure 5. Reference renders of the model: dormant, the burst with the cutaway open, and lava flowing.',
           height=58 * mm)

# --------------------------------------------------------------------------
# C
# --------------------------------------------------------------------------
section('C', 'Application Development and Implementation')
P('Software and Tools', H2)
table([
    ['Tool', 'Used for'],
    ['Flutter 3.47 / Dart 3.13', 'Application framework, interface and the 3D renderer.'],
    ['Kotlin', 'Android-side bridges to ARCore, sensors, media and the gallery.'],
    ['Google ARCore 1.57', 'Markerless tracking: motion tracking, plane detection, hit testing, anchors, light estimation.'],
    ['Google ML Kit barcode scanning (through the mobile_scanner plugin, with CameraX)', 'Marker detection: finds the marker\'s code and reports its four corners.'],
    ['Android gravity sensor', 'Levels the model in marker mode.'],
    ['Android TextToSpeech (through flutter_tts) and MediaPlayer', 'Narration: a speech engine voice, or a recorded clip when one is supplied.'],
    ['A model generator written in Dart (tool/forge_models.dart)', 'Builds the five components as Wavefront OBJ files.'],
    ['Git and GitHub', 'Version control; every change went through a reviewed pull request.'],
], [0.42, 0.58])
P('The application is about 7,000 lines of Dart and 1,250 lines of Kotlin, with 87 automated tests.', SMALL)

P('Marker-Based Implementation', H2)
P('<b>Marker preparation.</b> The marker is a custom card carrying a QR code. The code\'s content is the '
  'marker\'s identity (<font face="Courier">VULCANIC:01</font> and <font face="Courier">VULCANIC:02</font>), '
  'so the application knows which content belongs to which marker: marker 01 shows the volcano, marker 02 '
  'opens directly into the cutaway. The marker is drawn by the application itself, can be printed from the '
  'project files, saved to the gallery, or shown full screen on a second phone.')
mk = find('marker-01-volcano.png')
figure_row(['marker-01-volcano.png', 'screen_markers.png', 'screen_marker_full.png'],
           'Figure 6. The printable marker, the marker gallery, and a marker shown full screen for a second phone.',
           height=58 * mm)
P('<b>Recognition and tracking.</b> The process for each camera frame is:')
bullets([
    '<b>Detection.</b> ML Kit locates the code and returns its four corner points in the camera image.',
    '<b>Identification.</b> The code is decoded. Codes that are not Vulcanic markers are ignored and the user '
    'is told so.',
    '<b>Pose estimation.</b> Because the code is a flat square of known shape, four points are enough to '
    'recover its position and orientation. The application fits the homography that maps the square onto '
    'its image and factors it into a rotation and a translation. Distances are measured in units of the '
    'code\'s width, so the marker works at any printed size and the volcano scales with it.',
    '<b>Stabilisation.</b> Four corners locate a marker far better than they give its tilt, so a raw pose '
    'trembles. When the marker is roughly level, the model\'s vertical axis is taken from the gravity sensor '
    'rather than from the image, and position and facing are smoothed heavily at rest and lightly in motion.',
    '<b>Display.</b> The volcano is rendered on the pose, with an outline over the recognised code.',
])
P('<b>Response to the marker being moved, covered or removed.</b> While the marker moves, the volcano '
  'follows it. If the code is covered or leaves the view, no detection arrives; after 0.45 seconds the '
  'marker is declared lost, the status changes, and the volcano fades out. When the marker returns, the '
  'volcano reappears on it without easing in from its old position.')
figure_row([('placeholder', 'Marker-based recognition\n(outline on the marker)'),
            ('placeholder', 'Marker-based visualisation\n(volcano on the marker)'),
            ('placeholder', 'Marker interaction\n(cutaway or eruption)')],
           'Figure 7. Marker-based mode on the test device.', height=52 * mm)

P('Markerless Implementation', H2)
P('<b>Natural feature tracking.</b> ARCore finds visually distinct points in the camera image (corners, '
  'texture, edges of objects) and follows them from frame to frame. Combined with the phone\'s motion '
  'sensors, this gives the phone\'s position and orientation in the room. The application can draw these '
  'feature points as dots, which makes the technique visible during a demonstration.')
P('<b>Plane detection.</b> Where feature points lie on a common flat surface, ARCore reports a plane with '
  'an outline that grows as more of the surface is seen. The application is set to find horizontal planes '
  'and draws each outline over the camera image.')
P('<b>Placement and anchoring.</b> A ring shows where the centre of the screen meets a detected plane. '
  'When the user taps, the application performs a hit test from that screen point into the scene; if it '
  'lands inside a plane\'s outline, an anchor is created there. ARCore keeps the anchor fixed in the world '
  'as its understanding of the room improves, and the volcano is drawn on it every frame using ARCore\'s '
  'own camera matrices. The model rises into place and a ring spreads across the surface.')
P('<b>Manipulation.</b> Drag to rotate, pinch to scale, the view rail for stepwise zoom and turn, and Move '
  'to place the model again elsewhere.')
P('<b>Tracking feedback.</b> A status dot and word show the tracking state, and when tracking degrades the '
  'application shows ARCore\'s reason: too dark, moving too fast, or too little surface detail. Brightness '
  'of the model follows ARCore\'s light estimate, and the model dims if its anchor stops tracking.')
P('<b>Phones without ARCore.</b> The application checks ARCore availability at launch. A capable phone '
  'that only lacks Google Play Services for AR is offered the install. A phone that cannot run ARCore gets '
  'screen placement instead: the camera image with the volcano placed where the user taps, using an '
  'assumed camera pose. This is clearly labelled and is not world-anchored. Marker mode works on such '
  'phones unchanged.')
figure_row([('placeholder', 'Markerless plane detection\n(plane outline and ring)'),
            ('placeholder', 'Markerless object placement\n(volcano on the surface)'),
            ('placeholder', 'Markerless interaction\n(scaled, rotated or erupting)'),
            'built-camera.jpg'],
           'Figure 8. Markerless mode on the test device. The last image is the screen-placement fallback, '
           'captured on an Android emulator.', height=58 * mm)

P('3D Object Development', H2)
P('<b>Technique and tools.</b> The five components were modeled procedurally. A generator program '
  '(<font face="Courier">tool/forge_models.dart</font>) constructs each mesh from a mathematical '
  'description and writes it as a standard Wavefront OBJ file with per-vertex colour, which opens directly '
  'in Blender for inspection or further editing. The techniques used are those of conventional modeling:')
bullets([
    '<b>Revolved profile.</b> The cone is a profile curve, steep near the summit and gentle at the foot, '
    'swept around the vertical axis in 72 segments and 24 rings.',
    '<b>Displacement.</b> Ridges and gullies are added by moving vertices in and out along the slope, and '
    'the crater rim is made uneven and breached where the lava leaves.',
    '<b>Vertex painting.</b> Colour is chosen from height and steepness: vegetation on the apron, scree, '
    'bare rock, ash and scorch under the rim.',
    '<b>Baked contact shade.</b> Vertices are darkened in the gullies and where the cone meets the ground.',
    '<b>Modeling for a cutaway.</b> Every ring has a vertex on the two cutting planes, so no triangle '
    'crosses them, and section faces showing the layers are modeled as part of the cone and the ground.',
    '<b>Other components.</b> The chamber is a lobed ellipsoid, the conduit a tapering tube, and the lava '
    'flow a raised ribbon that follows the cone\'s surface down a meandering path.',
])
figure_row([('placeholder', 'Component 01 in the\nmodeling tool'), ('placeholder', 'Component 02'),
            ('placeholder', 'Component 03'), ('placeholder', 'Component 04'), ('placeholder', 'Component 05')],
           'Figure 9. Development of the five components. Space for screenshots of each component in the '
           'modeling tool.', height=40 * mm)

P('System Integration', H2)
bullets([
    '<b>Models into the scene.</b> The OBJ files are parsed at start-up into one set of triangles. Each '
    'triangle is tagged with its component, its role (exterior, cut face, deep rock, magma, conduit, lava) '
    'and its quadrant.',
    '<b>Rendering.</b> The renderer transforms the vertices, removes back-facing triangles, sorts the rest '
    'and lights them with a warm key light, a cool fill and a rim, then draws them in one call. Because a '
    '2D canvas has no depth buffer, the model is split into four quadrants that have a fixed far-to-near '
    'order from any viewpoint; the cutaway uses the same structure to remove one quadrant.',
    '<b>Tracking into rendering.</b> ARCore\'s view and projection matrices and the anchor pose, the marker '
    'pose, or the explorer\'s orbit camera feed the same renderer.',
    '<b>Animation.</b> The eruption is a pure function of time, so it can be paused and reset exactly. '
    'It drives the conduit fill, crater glow, particles, lava advance and lava temperature.',
    '<b>Interaction.</b> One controller holds the state that every mode shares: eruption, cutaway, pins, '
    'selection, rotation and scale, with spring motion for changes the application makes itself.',
])
P('<b>Interactive features.</b> Beyond the required controls, the application provides: rotation and '
  'scaling by gesture and by buttons; repositioning; an animated eruption with pause and reset; a cutaway '
  'view that turns and zooms to the opening; object selection with information overlays; interactive '
  'numbered pins; narration by speech engine or recorded clip; and image capture to the gallery.')

P('Challenges Encountered', H2)
table([
    ['Challenge', 'How it was addressed'],
    ['A 2D canvas has no depth buffer, so triangles drew in the wrong order.',
     'The model is divided by two planes into quadrants with a known drawing order, and components stack in a fixed order inside each quadrant.'],
    ['Flutter has no ARCore view that would let the application draw its own content.',
     'ARCore runs in a Kotlin session on its own graphics thread. The camera image is passed to Flutter as a texture and tracking data as one packet per frame.'],
    ['On a real phone the model trembled on the marker.',
     'The tilt recovered from four corners is noise-sensitive. The model is now levelled with the gravity sensor and the remaining pose is smoothed adaptively.'],
    ['Capable phones were sent to the fallback.',
     'ARCore\'s support check can answer slowly. The check now starts at launch and waits, and the app offers to install the AR services when only they are missing.'],
    ['The first model looked banded and flat.',
     'Colour is assigned by terrain rather than by ring, contact shade is baked in, and three lights replace one.'],
    ['Saved pictures included the on-screen controls.',
     'The controls are hidden and the capture waits until that frame has reached the screen.'],
    ['Stopping a recorded narration did not stop playback.',
     'A state flag was cleared before it was read. Found in review and covered by a test.'],
], [0.40, 0.60])

# --------------------------------------------------------------------------
# D
# --------------------------------------------------------------------------
section('D', 'System Testing and Evaluation')
P('Functional Testing', H2)
P('<b>Automated tests.</b> The project has 87 automated tests, all passing on version 1.2.0. They cover:')
table([
    ['Area', 'What is verified'],
    ['3D models', 'The generated files are current; five substantial components; no triangle crosses a quadrant plane; the cutaway has faces and an interior to show.'],
    ['Eruption', 'The four phases occur in order; build-up, burst, flow and cooling; lava never moves backwards and stalls between surges; pause and reset.'],
    ['Renderer', 'The model renders in each state and from behind and above; pins can be hit.'],
    ['Markerless', 'The tracking packet is decoded correctly; the ARCore support check waits for slow answers; placement geometry.'],
    ['Marker-based', 'A known pose is recovered from four corners and re-projects onto them; the stabiliser reduces on-screen shake from about 22 px to about 3 px with noisy corners; a lost marker is detected.'],
    ['Interface', 'Home, explorer, component sheet, guide and markers build and respond at phone sizes, including a small screen.'],
    ['Narration', 'Voice selection across speech engines; a recorded clip is preferred, played and stopped.'],
], [0.20, 0.80])
P('<b>Device test plan.</b> The following tests are to be carried out on a physical phone and the results '
  'recorded. Version 1.2.0 was exercised on an Android 14 emulator during development; an emulator has no '
  'ARCore and no real camera, so it cannot stand in for these.')
table([
    ['No.', 'Feature', 'Steps', 'Expected result', 'Result'],
    ['1', 'Main interface', 'Open the app.', 'Home shows the volcano, one main action and two others.', ''],
    ['2', 'Marker recognition', 'Open Marker; point at marker 01.', 'The code is outlined; status shows the marker\'s name.', ''],
    ['3', 'Marker visualisation', 'Hold the view on the marker.', 'The volcano stands on the marker, upright and steady.', ''],
    ['4', 'Marker moved', 'Slide and turn the marker.', 'The volcano follows.', ''],
    ['5', 'Marker covered or removed', 'Cover the code, then uncover it.', 'The volcano fades, status shows Lost, then it returns.', ''],
    ['6', 'Marker identity', 'Point at marker 02.', 'The volcano opens with the cutaway showing.', ''],
    ['7', 'Marker interaction', 'Erupt; open Inside; tap a pin.', 'Eruption plays; cutaway opens; the sheet appears.', ''],
    ['8', 'Plane detection', 'Open Surface; move the phone over a table.', 'A plane outline and a ring appear; status shows Surface found.', ''],
    ['9', 'Object placement', 'Tap on the detected surface.', 'The volcano rises into place and stays there.', ''],
    ['10', 'Anchoring', 'Walk around the volcano.', 'It stays fixed on the surface.', ''],
    ['11', 'Markerless interaction', 'Drag, pinch, use the view rail, press Move.', 'It rotates, scales and can be placed again.', ''],
    ['12', 'Tracking feedback', 'Cover the camera, or move quickly.', 'A hint names the cause; the model dims.', ''],
    ['13', 'Narration', 'Open a component; press Listen.', 'The explanation is read aloud; Stop ends it.', ''],
    ['14', 'Image capture', 'Press the camera button.', 'A picture without controls is saved to the gallery.', ''],
    ['15', 'No-ARCore fallback', 'On a phone without ARCore, open Surface.', 'Screen placement opens; tapping places the volcano.', ''],
], [0.06, 0.19, 0.27, 0.34, 0.14])

P('AR Tracking Evaluation', H2)
P('The performance of each method is to be observed during the device tests. The factors below are known '
  'to affect recognition and positioning and should be varied and noted.')
table([
    ['Factor', 'Effect on marker-based tracking', 'Effect on markerless tracking'],
    ['Lighting', 'Low light and glare on the marker prevent the code being read.', 'Low light gives too few feature points; ARCore reports insufficient light.'],
    ['Surface or marker detail', 'A damaged, creased or partly hidden code is not recognised.', 'Plain, glossy or transparent surfaces are detected slowly or not at all.'],
    ['Motion', 'Fast movement blurs the code and the lock drops.', 'Fast movement loses tracking; ARCore reports excessive motion.'],
    ['Distance and size', 'A small or distant marker gives noisier pose and may not decode.', 'Planes far from the camera are detected less reliably.'],
    ['Viewing angle', 'A steep angle distorts the code beyond reading.', 'Little effect once a plane is found.'],
    ['Display instead of print', 'Screen glare and refresh flicker can reduce reliability.', 'Not applicable.'],
], [0.20, 0.40, 0.40])
table([
    ['Observation', 'Marker-based', 'Markerless'],
    ['Time to first recognition or first plane', '', ''],
    ['Stability of the model at rest', '', ''],
    ['Behaviour while moving', '', ''],
    ['Recovery after tracking is lost', '', ''],
    ['Conditions in which it failed', '', ''],
], [0.40, 0.30, 0.30])

P('User Interface Evaluation', H2)
P('<b>Usability measures built into the design.</b>')
bullets([
    'One main action on the home screen; the same controls in every mode.',
    'Instructions for both tracking methods in the guide, and a one-line hint in context.',
    'Status and failure reasons are stated in plain words.',
    'Works at 360 dp wide and on short screens; the component sheet scrolls if it does not fit.',
])
P('<b>Accessibility measures.</b>')
bullets([
    'Every icon-only control has a spoken label for screen readers and a long-press tooltip.',
    'Explanations can be listened to as well as read.',
    'Text and icons over the camera image sit on a scrim and carry a shadow for contrast.',
    'Every gesture has a button equivalent in the view rail.',
])
table([
    ['Question for test users', 'Response'],
    ['Could you place the volcano without help?', ''],
    ['Was it clear what each control does?', ''],
    ['Could you find and open the cutaway?', ''],
    ['Was the text readable over the camera image?', ''],
    ['What was confusing or missing?', ''],
], [0.55, 0.45])

P('Results and Discussion', H2)
P('<b>Strengths of the system.</b>')
bullets([
    'Both tracking methods are implemented and share one model, one renderer and one interface.',
    'It degrades gracefully: marker mode and screen placement keep it usable on phones without ARCore.',
    'The renderer is self-contained, so the application is small (about 25 MB) and has no 3D engine dependency.',
    'Tracking state and its causes are shown to the user rather than hidden.',
    'The eruption and the cutaway explain a process, which a static model cannot.',
])
P('<b>Limitations.</b>')
bullets([
    'No occlusion: the volcano always draws in front of real objects.',
    'Marker mode assumes a typical camera field of view, because the scanner does not report lens intrinsics.',
    'Overlay and camera image can be a frame apart, so the model may drift slightly during fast motion.',
    'Screen placement is not anchored to the world.',
    'Triangles crossing the camera\'s near plane are dropped, visible only if the phone is moved inside the model.',
    'Markerless tracking detects horizontal surfaces only.',
])
P('<b>Device results.</b> To be summarised here from the tables above once the tests have been run.', SMALL)

# --------------------------------------------------------------------------
# E
# --------------------------------------------------------------------------
section('E', 'Conclusion')
P('Project Summary', H2)
P('Vulcanic is a working Android application that presents a volcano in augmented reality by two tracking '
  'methods. In Surface mode, ARCore detects a real surface and anchors the model to it. In Marker mode, a '
  'custom marker is recognised and identified, its pose is estimated from its four corners, and the model '
  'follows it. The model consists of five modeled components and carries an 18-second eruption, a cutaway, '
  'selectable components with spoken explanations, and image capture. A 3D explorer and a screen-placement '
  'fallback keep the application useful where AR is unavailable.')
P('Learning Outcomes', H2)
P('Building the system exercised the following knowledge and skills:')
bullets([
    'How marker-based AR works end to end: detection, identification, and recovering a 3D pose from a planar target.',
    'How markerless AR works: feature tracking, plane detection, hit testing and anchors, and what makes them fail.',
    'Why pose estimates are noisy and how sensor fusion and filtering steady them.',
    'The 3D graphics pipeline: model, view and projection transforms, culling, depth ordering and lighting.',
    'Procedural 3D modeling and preparing models for a specific rendering method.',
    'Bridging a cross-platform framework to native Android APIs, including threading and lifecycle.',
    'Designing an interface that stays legible over a live camera image.',
    'Working through reviewed pull requests with automated tests.',
])
P('Recommendations', H2)
bullets([
    'Move rendering to the GPU to gain a depth buffer, real shadows and glow, and occlusion by real surfaces using ARCore\'s depth API.',
    'Read the camera\'s true intrinsics for more accurate marker perspective.',
    'Use ARCore Augmented Images alongside the code-based marker, so a lost marker is bridged by motion tracking.',
    'Detect vertical surfaces, and add more volcano types (shield, cinder cone) for comparison.',
    'Record professional narration, add Filipino as a language, and add a short quiz mode for classroom use.',
    'Add eruption sound, and a hazard-map overlay linking the model to real alert levels.',
])

# --------------------------------------------------------------------------
# Appendix
# --------------------------------------------------------------------------
story.append(PageBreak())
P('APPENDIX', EYEBROW)
P('Required Demonstrations Checklist', H1)
table([
    ['No.', 'Demonstration', 'Where in the app', 'Captured'],
    ['1', 'Application main interface', 'Home screen', ''],
    ['2', 'Marker-based recognition', 'Marker: outline on the code, status shows the marker', ''],
    ['3', 'Marker-based AR visualisation', 'Marker: volcano standing on the marker', ''],
    ['4', 'Marker interaction', 'Marker: erupt, cutaway, pin and sheet', ''],
    ['5', 'Markerless plane detection', 'Surface: plane outline, feature points, ring', ''],
    ['6', 'Markerless object placement', 'Surface: volcano anchored after a tap', ''],
    ['7', 'Markerless object interaction', 'Surface: rotate, scale, Move, erupt', ''],
    ['8', 'Overall AR application', 'A walk through all three modes', ''],
], [0.07, 0.31, 0.47, 0.15])
P('The camera button in every scene saves a clean picture to Pictures/Vulcanic, which is the simplest way '
  'to collect these.', SMALL)
P('References and resources', H2)
table([
    ['Source code and releases', 'github.com/TeachDian/vulcanic'],
    ['Installable package', 'Release v1.2.0 on the repository (APK for arm64, 32-bit ARM and x86_64)'],
    ['Printable markers', 'docs/markers/ in the repository, or Markers in the app'],
    ['Narration script', 'docs/narration.md in the repository'],
    ['Google ARCore', 'developers.google.com/ar'],
    ['Google ML Kit barcode scanning', 'developers.google.com/ml-kit/vision/barcode-scanning'],
    ['Flutter', 'flutter.dev'],
    ['Typeface', 'Archivo, SIL Open Font License'],
], [0.34, 0.66], header=False)


def decorate(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setFont('Helvetica', 8)
        canvas.setFillColor(MUTED)
        canvas.drawString(MARGIN, 12 * mm, 'Vulcanic: Project Documentation')
        canvas.drawRightString(W - MARGIN, 12 * mm, str(doc.page))
        canvas.setStrokeColor(LINE)
        canvas.setLineWidth(0.5)
        canvas.line(MARGIN, 16 * mm, W - MARGIN, 16 * mm)
    canvas.restoreState()


doc = SimpleDocTemplate(
    OUT, pagesize=A4, leftMargin=MARGIN, rightMargin=MARGIN, topMargin=20 * mm, bottomMargin=22 * mm,
    title='Vulcanic: Project Documentation',
    subject='AR-Based Interactive Application: Marker-Based and Markerless Tracking',
)
doc.build(story, onFirstPage=decorate, onLaterPages=decorate)
print('wrote', OUT)
