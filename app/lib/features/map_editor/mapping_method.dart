/// Sådan organisereren lægger stier og steder på kortet.
enum MappingMethod {
  walk('Gå ruten fysisk', 'Gå langs veje og stier — GPS optager ruten automatisk.'),
  draw('Tegn ruten', 'Tegn veje punkt for punkt eller træk frihånd langs stien.');

  const MappingMethod(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Tegnetilstand når [MappingMethod.draw] er valgt.
enum PathDrawStyle {
  tap('Punkt til punkt', 'Tryk for hvert hjørne og kryds.'),
  freehand('Frihånd', 'Træk fingeren langs stien — slip for at afslutte strøget.');

  const PathDrawStyle(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

/// Hovedfaner i kort-editoren.
enum EditorSection {
  routes('Ruter'),
  places('Steder'),
  map('Kort'),
  audioTour('Lyd'),
  treasureHunt('Skattejagt');

  const EditorSection(this.label);

  final String label;
}

/// Hvad et tryk på kortet gør i editoren.
enum EditorMode {
  /// Ruter-fane uden aktivt værktøj valgt.
  routesIdle,
  drawPath,
  addPlace,
  editPlace,
  /// Administrer tilkoblinger mellem steder og officielle stier.
  editConnections,
  connectPoiToPath,
}
