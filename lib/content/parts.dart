import 'package:flutter/material.dart';

import '../engine/volcano_geometry.dart';

/// A short fact shown as a chip under a component's description.
class Fact {
  const Fact(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
}

/// What the app says about one component of the volcano.
class PartInfo {
  const PartInfo({
    required this.tagline,
    required this.description,
    required this.facts,
    required this.icon,
  });

  final String tagline;

  /// Shown on the detail card and read aloud by the narrator.
  final String description;
  final List<Fact> facts;
  final IconData icon;
}

extension PartContent on VolcanoPart {
  PartInfo get info => _info[this]!;
}

const Map<VolcanoPart, PartInfo> _info = {
  VolcanoPart.cone: PartInfo(
    icon: Icons.landscape_rounded,
    tagline: 'The mountain an eruption builds',
    description:
        'The cone is the volcano you see from the outside. It grows layer by '
        'layer from the lava, ash and rock thrown out by earlier eruptions. '
        'This one is a stratovolcano: steep near the summit, with a bowl '
        'shaped crater at the top where the vent opens.',
    facts: [
      Fact(Icons.category_rounded, 'Stratovolcano', 'Type'),
      Fact(Icons.layers_rounded, 'Lava and ash', 'Built from'),
      Fact(Icons.place_rounded, 'Mayon, Albay', 'A real one'),
    ],
  ),
  VolcanoPart.terrain: PartInfo(
    icon: Icons.layers_rounded,
    tagline: 'The crust beneath the volcano',
    description:
        'Under the volcano lies the crust: bands of older rock laid down '
        'over millions of years. Magma forces its way up through cracks in '
        'these layers. The cutaway shows them from the side, like the '
        'layers in a slice of cake.',
    facts: [
      Fact(Icons.straighten_rounded, '5 to 70 km', 'Crust thickness'),
      Fact(Icons.hourglass_bottom_rounded, 'Oldest at the bottom', 'Order'),
    ],
  ),
  VolcanoPart.chamber: PartInfo(
    icon: Icons.bubble_chart_rounded,
    tagline: 'Where molten rock waits',
    description:
        'The magma chamber is a reservoir of molten rock stored deep '
        'underground. As more magma arrives and the gas dissolved in it '
        'builds up, the pressure rises until the rock above can no longer '
        'hold it, and the magma is forced upward.',
    facts: [
      Fact(Icons.thermostat_rounded, '700 to 1,300 °C', 'Temperature'),
      Fact(Icons.south_rounded, '1 to 10 km', 'Typical depth'),
      Fact(Icons.label_rounded, 'Magma', 'Name underground'),
    ],
  ),
  VolcanoPart.conduit: PartInfo(
    icon: Icons.vertical_align_top_rounded,
    tagline: 'The passage to the surface',
    description:
        'The conduit is the pipe that connects the magma chamber to the '
        'crater. During an eruption, magma races up it as the gas inside '
        'expands into bubbles, the same way a shaken bottle of soda fizzes '
        'over when it is opened.',
    facts: [
      Fact(Icons.air_rounded, 'Expanding gas', 'Driven by'),
      Fact(Icons.flag_rounded, 'The crater', 'Ends at'),
    ],
  ),
  VolcanoPart.lava: PartInfo(
    icon: Icons.local_fire_department_rounded,
    tagline: 'Molten rock above ground',
    description:
        'Once magma reaches the surface it is called lava. It spills from '
        'the crater and runs downhill, glowing orange while it is hot. As it '
        'cools it darkens and hardens into solid rock, adding a new layer '
        'to the cone.',
    facts: [
      Fact(Icons.label_rounded, 'Lava', 'Name at the surface'),
      Fact(Icons.directions_walk_rounded, 'Often walking pace', 'Speed'),
      Fact(Icons.ac_unit_rounded, 'Solid rock', 'Cools into'),
    ],
  ),
};
