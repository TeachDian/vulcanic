/// A printed marker the app recognises.
///
/// Each marker carries its identity in its code, so the app knows which
/// content to show for it.
enum VulcanicMarker {
  volcano('VULCANIC:01', '01', 'Volcano', 'The whole stratovolcano'),
  crossSection(
    'VULCANIC:02',
    '02',
    'Cross-section',
    'Opens with the cutaway showing',
  );

  const VulcanicMarker(this.payload, this.number, this.title, this.caption);

  /// The text encoded in the marker.
  final String payload;
  final String number;
  final String title;
  final String caption;

  /// Lower-case name for file names.
  String get slug => title.toLowerCase().replaceAll(' ', '-');

  /// The marker with this [payload], or null for any other code.
  static VulcanicMarker? identify(String? payload) {
    for (final marker in values) {
      if (marker.payload == payload) return marker;
    }
    return null;
  }
}
