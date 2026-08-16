/// Lav et URL-venligt slug fra dansk/engelsk tekst.
String slugify(String input) {
  var slug = input.trim().toLowerCase();
  slug = slug
      .replaceAll('æ', 'ae')
      .replaceAll('ø', 'oe')
      .replaceAll('å', 'aa');
  slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  slug = slug.replaceAll(RegExp(r'-+'), '-');
  return slug.replaceAll(RegExp(r'^-|-$'), '');
}
