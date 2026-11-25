# Vulcanic

An interactive AR volcano for Android, built with Flutter.

Stand a stratovolcano on your desk, set off an eruption, open a cutaway down
to the magma chamber, and tap any of its five components to read or hear
what it does, in a recorded voice if you add one. It works three ways:

| Mode | Tracking | Needs |
| ---- | -------- | ----- |
| **Surface** | Markerless: ARCore plane detection and anchoring | An ARCore phone |
| **Marker** | Marker-based: a printed code, tracked in 3D | Any phone with a camera |
| **3D explorer** | None: orbit the model on a plain backdrop | Nothing |

Surface tracking is always tried first. The app asks ARCore about the phone
as soon as it opens, waits for a slow first answer rather than assuming the
worst, and offers to install Google Play Services for AR if that is all that
is missing. If no surface turns up after twenty seconds it says why and
offers screen placement.

Phones without ARCore are detected at run time. On them, Surface becomes
*screen placement* (tap the camera view to put the volcano there), and
Marker works exactly as it does everywhere else.

<p>
  <img src="docs/screenshots/home.png" width="24%" alt="Home screen">
  <img src="docs/screenshots/explorer_erupting.png" width="24%" alt="Eruption with the cutaway open">
  <img src="docs/screenshots/explorer_part.png" width="24%" alt="Component card">
  <img src="docs/screenshots/markers.png" width="24%" alt="Marker gallery">
</p>

## Run it

Requires Flutter 3.47+ and a phone on Android 13 (API 33) or newer.

```bash
flutter run
```

Build an installable APK:

```bash
flutter build apk --release --split-per-abi
```

The APKs land in `build/app/outputs/flutter-apk/`; `app-arm64-v8a-release.apk`
is the one for almost every current phone.

## Using it

**Surface.** Point at a table or floor and move the phone slowly. Detected
surfaces are outlined and a ring shows where the volcano would stand. Tap to
place it, then walk around it. *Move* places it again; the grid button shows
or hides what the tracker sees.

**Marker.** Print a marker from [`docs/markers/`](docs/markers), or open
*Markers* in the app on a second device (the download button there saves a
printable copy to the gallery). Point the camera at it: the
volcano stands on the marker and follows it as it moves. Cover the marker or
take it out of view and the volcano fades out until it returns. Marker 02
opens straight into the cutaway.

**Everywhere.** Drag to turn, pinch to resize, or use the view buttons under
the camera button: zoom in, zoom out and a quarter turn to the next side (the
explorer adds a view from above). The view also moves by itself: opening the
cutaway turns the opening to face you and zooms in, and selecting a component
brings it round. *Erupt* plays an 18 second
sequence: three seconds of build-up as the ground trembles and the crater
glow quickens, a burst, a pulsing ash column, lava that advances in surges,
and a slow cooling. *Inside* opens the
cutaway. Tap a label or a number to open a component's card, and *Listen* to
have it read aloud. The camera button saves a picture to the gallery.

## The interface

Graphite and bone, one typeface, and as few words as the app can get away
with. Colour is kept for the volcano and for heat.

- **Home** has one filled button, *Place on a surface*. A green dot on it
  means this phone can track surfaces.
- **The console** at the bottom holds the eruption: a seismograph trace that
  gets rougher where the ground shakes, the trigger, and two icon toggles
  for the cutaway and the pins.
- **Pins** are small numbered discs on the model. Tap one to open its sheet;
  only the selected component is named.
- **The sheet** gives a two-sentence summary and a short table of facts.
  *Listen* reads the fuller explanation.

## How it is built

```mermaid
flowchart LR
  subgraph Android
    ARCore[ARCore session<br/>planes, anchors, light]
    Scanner[CameraX + ML Kit<br/>code corners]
  end
  subgraph Flutter
    AR[ArFrame<br/>view, projection, anchor]
    Pose[MarkerPose<br/>homography to 3D pose]
    Orbit[OrbitCamera]
    Renderer[SceneRenderer<br/>Canvas.drawVertices]
    UI[Shared controls<br/>dock, timeline, cards]
  end
  ARCore -- camera texture + packet per frame --> AR
  Scanner -- preview + corners --> Pose
  AR --> Renderer
  Pose --> Renderer
  Orbit --> Renderer
  Renderer --> UI
```

One renderer serves every mode. It only needs a view, a projection and a
model matrix, and each mode supplies them from a different source.

### The model

The volcano is five separately modeled components, each a plain OBJ file in
`assets/models/`:

| # | Component | File |
| - | --------- | ---- |
| 01 | Volcanic cone and crater | `cone.obj` |
| 02 | Ground and rock layers | `terrain.obj` |
| 03 | Magma chamber | `chamber.obj` |
| 04 | Main conduit | `conduit.obj` |
| 05 | Surface lava flow | `lava.obj` |

The cone is coloured by what the ground would be (vegetation on the gentle
apron, scree, bare rock where it steepens, ash and scorch under the rim), and
contact shade is baked into the vertices: darker in the gullies and where the
cone meets the ground. From outside, the rock block shows only as a thin
plinth. The strata under it appear when the cutaway opens, and the model
rises by that much so they have somewhere to be.

They are generated by `tool/forge_models.dart` and carry per-vertex colours,
so they open directly in Blender (File → Import → Wavefront). Re-export over
a file to change the model, or regenerate everything with:

```bash
dart run tool/forge_models.dart
```

### The renderer

`lib/engine/` draws the model with `Canvas.drawVertices`: no 3D engine and
no native rendering library. Triangles are transformed, culled and sorted on
the CPU and lit by three lights fixed to the viewer: a warm key, a cool fill
for the shadow side and a rim on the silhouette. Lava is coloured by
temperature along a real incandescence ramp. A canvas has no depth buffer, so `scene_renderer.dart` orders the
scene by splitting it into four quadrants that have a fixed far-to-near
order from any viewpoint; the cutaway is the same structure used in reverse.

### Markerless tracking

ARCore does the tracking and Flutter draws everything.

- `android/.../ar/ArSessionRunner.kt` runs the session on its own GL thread.
  It draws the camera image into a Flutter texture and packs each frame's
  view and projection matrices, anchor pose, plane outlines, feature points
  and light estimate into one array.
- `lib/ar/ar_session.dart` decodes it. `lib/ui/surface_screen.dart` draws
  the planes, feature points and placement ring, hit-tests a tap against a
  plane and creates the anchor.
- Tracking quality is shown live: the status pill, and a hint naming the
  cause when it degrades (too dark, moving too fast, too little detail).

### Marker tracking

- The marker is a card with a QR code that carries its identity
  (`VULCANIC:01`, `VULCANIC:02`), drawn by `lib/ui/marker_card.dart`.
- ML Kit finds the code and reports its four corners.
- `lib/ar/marker_pose.dart` turns four corners into a 3D pose: it fits the
  homography from the flat square to its image, then factors that into a
  rotation and a translation. Distances are in units of the code's width,
  so the marker can be printed at any size.
- `MarkerTracker` eases between detections and reports the marker lost when
  they stop.

### Narration

*Listen* on a component's sheet reads its explanation aloud
(`lib/narration/`).

- If the app ships a recording for that component
  (`assets/narration/<component>.m4a`), that recording is played, straight
  from the APK through Android's `MediaPlayer`.
- Otherwise the phone's speech engine reads the same text in a male English
  voice, chosen by name because Android does not label voices by gender.

[`docs/narration.md`](docs/narration.md) has the script for all five
components and how to add recordings. They can be added one at a time.

### Motion

Each kind of movement has its own feel. Turning the model is a spring with a
little overshoot; zooming is damped so it never bounces. A placed model
rises into place while a ring spreads over the surface from where it landed.
The component sheet rises from the edge and its lines follow one by one.

## Limits worth knowing

- **Screen placement is not anchored.** Without motion tracking the volcano
  stays where it is on the screen, not in the room.
- **Marker tracking assumes a typical camera field of view**, since the
  scanner does not report lens intrinsics. Perspective can be slightly off
  on unusual lenses. It also depends on the code being readable: glare,
  motion blur, or a steep angle will drop the lock.
- **Surface tracking needs light and texture.** Plain, glossy or dim
  surfaces are found slowly or not at all.
- **No occlusion.** The volcano always draws in front of real objects.
- Triangles that cross the camera's near plane are dropped, which only
  shows if you move the phone inside the model.

## Tests

```bash
flutter test
```

Covers the OBJ parser, the model's structure, the eruption timeline, the
AR packet decoder, placement and marker pose maths, voice selection, and
the screens themselves. `test/engine/render_dump_test.dart` and
`test/ui/screens_test.dart` also write PNGs to `build/renders/`.

## Credits

- Typeface: [Archivo](https://github.com/Omnibus-Type/Archivo), SIL Open Font
  License (`assets/fonts/OFL.txt`).
- Tracking: Google ARCore and ML Kit barcode scanning (via
  [mobile_scanner](https://pub.dev/packages/mobile_scanner)).
- Speech: [flutter_tts](https://pub.dev/packages/flutter_tts).
