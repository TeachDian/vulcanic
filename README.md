# Vulcanic

An interactive AR volcano for Android, built with Flutter.

Place a stratovolcano on a real surface (markerless, ARCore) or on a printed
marker, trigger an eruption, open a cutaway, and explore its five components.

Work in progress — features land one pull request at a time.

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
