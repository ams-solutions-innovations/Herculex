import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/buddy/application/buddy_share_policy.dart';
import 'package:herculex/features/buddy/domain/buddy_scope.dart';
import 'package:herculex/features/buddy/presentation/buddy_scope_toggle.dart';

void main() {
  testWidgets('BuddyScopeToggle shows selection and notifies on change when enabled', (tester) async {
    BuddyScope currentScope = BuddyScope.both;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return BuddyScopeToggle(
                scope: currentScope,
                onChanged: (newScope) {
                  setState(() {
                    currentScope = newScope;
                  });
                },
                decision: const ShareDecision(
                  scope: BuddyScope.both,
                  userOverridable: true,
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Both (Shared)'), findsOneWidget);
    expect(find.text('Only Me'), findsOneWidget);

    // Tap Only Me
    await tester.tap(find.text('Only Me'));
    await tester.pumpAndSettle();

    expect(currentScope, BuddyScope.mine);
  });

  testWidgets('BuddyScopeToggle displays reason text when scope is forced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BuddyScopeToggle(
            scope: BuddyScope.mine,
            onChanged: (_) {},
            decision: const ShareDecision(
              scope: BuddyScope.mine,
              userOverridable: false,
              reason: 'Custom exercises cannot be shared with gym buddies',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Custom exercises cannot be shared with gym buddies'), findsOneWidget);
  });
}
