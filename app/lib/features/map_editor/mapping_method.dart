/// Sådan organisereren lægger stier og steder på kortet.
enum MappingMethod {
  walk('Gå ruten fysisk', 'Gå langs veje og stier — GPS optager ruten automatisk.'),
  draw('Tegn ruten', 'Tryk på kortet for at tegne veje og markere huse og steder.');

  const MappingMethod(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Hovedfaner i kort-editoren.
enum EditorSection {
  routes('Ruter'),
  places('Steder'),
  map('Kort'),
  audioTour('Lydvandringer'),
  treasureHunt('Skattejagt');

  const EditorSection(this.label);

  final String label;
}

/// Hvad et tryk på kortet gør i editoren.
enum EditorMode {
  drawPath,
  addPlace,
  editPlace,
  /// Administrer tilkoblinger mellem steder og officielle stier.
  editConnections,
  connectPoiToPath,
}
