import 'package:flutter_test/flutter_test.dart';

import 'package:event_map/main.dart';

void main() {
  testWidgets('shows config hint when Supabase is not configured', (tester) async {
    await tester.pumpWidget(const PlotspottingApp());
    expect(find.textContaining('Supabase er ikke konfigureret'), findsOneWidget);
  });
}
