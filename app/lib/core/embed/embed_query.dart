/// Parses `?embed=1` (also `true` / `yes`) for iframe-visning.
bool parseEmbedQuery(String? value) {
  if (value == null || value.trim().isEmpty) return false;
  switch (value.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    default:
      return false;
  }
}
