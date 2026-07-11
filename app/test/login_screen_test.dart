import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cachy/data/services/auth_service.dart';
import 'package:cachy/ui/features/onboarding/views/login_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('login screen: Google primary, quiet anonymous path', (tester) async {
    final auth = FakeAuthService();
    var done = 0;
    await tester.pumpWidget(
      Provider<AuthService>.value(
        value: auth,
        child: MaterialApp(home: LoginScreen(onDone: () => done++)),
      ),
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Or use without login…'), findsOneWidget);

    await tester.tap(find.text('Or use without login…'));
    await tester.pumpAndSettle();
    expect(auth.currentUser?.isAnonymous, isTrue);
    expect(done, 1);
  });
}
