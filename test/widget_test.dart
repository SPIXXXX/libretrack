import 'package:flutter_test/flutter_test.dart';

import 'package:libretrack/main.dart';
import 'package:libretrack/pages/login_page.dart';

void main() {
  testWidgets('opens the register page from login', (tester) async {
    await tester.pumpWidget(const MyApp(home: LoginPage()));

    expect(find.text('Welcome to LibraTrack'), findsOneWidget);
    expect(find.text('Register here'), findsOneWidget);

    await tester.ensureVisible(find.text('Register here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register here'));
    await tester.pumpAndSettle();

    expect(find.text('Profile picture can be added later'), findsOneWidget);
    expect(find.text('School ID'), findsOneWidget);
  });
}
