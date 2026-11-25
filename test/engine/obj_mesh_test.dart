import 'package:flutter_test/flutter_test.dart';
import 'package:vulcanic/engine/obj_mesh.dart';

void main() {
  test('parses coloured vertices, normals and materials', () {
    final mesh = ObjMesh.parse('''
# a single triangle
v 0 0 0 1 0 0
v 1 0 0 0 1 0
v 0 1 0 0 0 1
vn 0 0 1
usemtl lava
f 1//1 2//1 3//1
''');
    expect(mesh.triangleCount, 1);
    expect(mesh.materialNames, ['lava']);
    expect(mesh.positions, [0, 0, 0, 1, 0, 0, 0, 1, 0]);
    expect(mesh.colors, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    expect(mesh.normals.sublist(0, 3), [0, 0, 1]);
  });

  test('triangulates polygons and derives missing normals and colours', () {
    // What a Blender export looks like: quads, texture slots, no colours.
    final mesh = ObjMesh.parse('''
v 0 0 0
v 1 0 0
v 1 0 -1
v 0 0 -1
vt 0 0
usemtl cone_rock
f 1/1 2/1 3/1 4/1
''', fallbackColor: (material) => const [0.2, 0.4, 0.6]);
    expect(mesh.triangleCount, 2);
    // Counter-clockwise seen from above, so the face normal points up.
    for (var corner = 0; corner < 6; corner++) {
      expect(mesh.normals[corner * 3 + 1], closeTo(1, 1e-6));
      expect(mesh.colors[corner * 3 + 2], closeTo(0.6, 1e-6));
    }
  });

  test('supports negative indices and skips degenerate faces', () {
    final mesh = ObjMesh.parse('''
v 0 0 0
v 1 0 0
v 0 1 0
f -3 -2 -1
f 1 1 2
''');
    expect(mesh.triangleCount, 1);
    expect(mesh.materialNames, ['default']);
  });
}
