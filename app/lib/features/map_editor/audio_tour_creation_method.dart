enum AudioTourCreationMethod {
  walk(
    'Gå ruten fysisk',
    'Gå ruten og optag fortællinger med mikrofonen undervejs.',
  ),
  manual(
    'Byg manuelt',
    'Vælg steder, upload lydfiler og sæt rækkefølgen på listen.',
  );

  const AudioTourCreationMethod(this.title, this.subtitle);

  final String title;
  final String subtitle;
}
