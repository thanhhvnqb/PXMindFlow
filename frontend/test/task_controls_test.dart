import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/features/tasks/presentation/task_controls.dart';

void main() {
  testWidgets('time selection emits UTC and clearing time preserves date', (
    tester,
  ) async {
    String? date;
    String? at;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => TaskDateButton(
              value: date,
              dueAt: at,
              vietnamese: false,
              onChanged: (value, instant) => update(() {
                date = value;
                at = instant;
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Set due date'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(DateTime.parse(at!).isUtc, isTrue);
    expect(DateTime.parse(at!).toLocal().hour, 9);
    final selectedDay = date;
    await tester.tap(find.byType(TextButton).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Clear time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear time'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(at, isNull);
    expect(date, selectedDay);
  });
  testWidgets('expanding carries draft and cancelling preserves it', (
    tester,
  ) async {
    String? expandedTitle;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickTaskEntry(
            vietnamese: false,
            onDetails: (title, due, priority, dueAt) async {
              expandedTitle = title;
              return false;
            },
            onSave: (_, _, _, _) async {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Continue editing');
    await tester.tap(find.byTooltip('Task details'));
    await tester.pumpAndSettle();
    expect(expandedTitle, 'Continue editing');
    expect(find.text('Continue editing'), findsOneWidget);
  });
  testWidgets(
    'quick entry retains failed draft and submits date and priority',
    (tester) async {
      var fail = true;
      final saved = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickTaskEntry(
              vietnamese: false,
              onDetails: (_, _, _, _) async => false,
              onSave: (title, due, priority, dueAt) async {
                if (fail) throw StateError('offline storage failure');
                saved.addAll([title, due, priority]);
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Draft task');
      await tester.tap(find.byTooltip('Priority'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set due date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Draft task'), findsOneWidget);
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      fail = false;
      await tester.tap(find.byTooltip('Add task'));
      await tester.pumpAndSettle();
      expect(saved.first, 'Draft task');
      expect(saved[1], isNotNull);
      expect(saved.last, 3);
      expect(find.text('Draft task'), findsNothing);
    },
  );
}
