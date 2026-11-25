# Vulcanic

An interactive AR volcano for Android, built with Flutter.

Place a stratovolcano on a real surface (markerless, ARCore) or on a printed
marker, trigger an eruption, open a cutaway, and explore its five components.

Work in progress — features land one pull request at a time.

## The app

- **Home** — a live volcano and the ways to view it.
- **Surface** — markerless AR. ARCore detects a table or floor, a tap anchors
  the volcano there, and you can walk around it.
- **Marker** — marker-based AR. The volcano stands on a printed marker and
  follows it; cover or remove the marker and it fades out.
- **3D explorer** — the model on its own: drag to orbit, pinch to zoom.
- **How it works** — illustrated instructions.

Every mode shares one set of controls (`lib/ui/scene/`): the eruption
trigger with its four-step timeline, the cutaway and label toggles, numbered
shortcuts to the five components, and a detail card for the selected one.

The interface is set in [Sora](https://github.com/sora-xor/sora-font)
(SIL Open Font License, see `assets/fonts/OFL.txt`).

## Markerless tracking

ARCore does the tracking; Flutter draws everything.

```
ARCore session (Kotlin, own GL thread)
  ├─ camera image ──► Flutter texture ──► Texture widget
  └─ per frame: view + projection matrices, anchor pose,
     plane outlines, feature points, light estimate
                     └─► EventChannel ──► ArFrame ──► painters
```

- `android/.../ar/ArSessionRunner.kt` runs the session and packs each frame.
- `lib/ar/ar_session.dart` decodes it; `lib/ui/surface_screen.dart` turns it
  into the screen: detected planes and feature points are drawn as an
  overlay, a ring shows where a tap would land, and a tap hit-tests the
  plane and creates an anchor.
- The status pill and the hint above the dock report tracking quality and
  the reason when it degrades (too dark, moving too fast, too little
  surface detail).

**Phones without ARCore** are detected at run time
(`ArCoreApk.checkAvailability`) and get *screen placement* instead: the
camera feed with the volcano placed wherever you tap, using an assumed
camera pose (`lib/ar/placement.dart`). It is not anchored to the world. The
grid button's neighbour in the top bar switches between the two on phones
that support both, which is handy for demonstrating the difference.

## Marker tracking

Print a marker from [`docs/markers/`](docs/markers), or open *Markers* in the
app on a second screen.

- Each marker is a card with a QR code that carries its identity
  (`VULCANIC:01`, `VULCANIC:02`), drawn by `lib/ui/marker_card.dart`. The app
  shows different content per marker: 02 opens straight into the cutaway.
- ML Kit finds the code and reports its four corners in the camera image.
- `lib/ar/marker_pose.dart` turns those four corners into a 3D pose. It fits
  the homography from the flat square to its image, then factors that into a
  rotation and a translation. Distances are in units of the code's width, so
  the marker can be printed at any size and the volcano scales with it.
- `MarkerTracker` eases between detections and reports the marker lost when
  they stop, which fades the volcano out.

This path needs only a camera, so it works on phones without ARCore. It
assumes a typical field of view, because the scanner does not report the
lens intrinsics.

## The model

The volcano is assembled from five separately modeled components, each a
plain OBJ file in `assets/models/`:

| # | Component | File |
| - | --------- | ---- |
| 01 | Volcanic cone and crater | `cone.obj` |
| 02 | Ground and rock layers | `terrain.obj` |
| 03 | Magma chamber | `chamber.obj` |
| 04 | Main conduit | `conduit.obj` |
| 05 | Surface lava flow | `lava.obj` |

They are produced by `tool/forge_models.dart` and carry per-vertex colours,
so they open directly in Blender. Re-export over a file to change the model;
regenerate everything with:

```bash
dart run tool/forge_models.dart
```

## The renderer

`lib/engine/` draws the model with `Canvas.drawVertices` — no 3D engine or
native rendering library. Triangles are transformed, culled and sorted on the
CPU; see `scene_renderer.dart` for how ordering works without a depth buffer.
The same renderer serves every mode: it only needs a view, a projection and a
model matrix, whether those come from an orbit camera, ARCore or a marker.

## Requirements

- Flutter 3.47 or newer
- Android 13 (API 33) or newer

## Run

```bash
flutter run
```
