import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:mindflow/app/providers.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';
import 'package:mindflow/shared/shell.dart';

void main() {
  testWidgets('expired sync session opens sign-in directly', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.testing(NativeDatabase.memory());
    final repository = LocalRepository(db);
    var syncs = 0;
    var logouts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: MindFlowShell(
            view: 'tasks',
            status: 'sign_in_required',
            sync: () {
              syncs++;
            },
            logout: () async {
              logouts++;
            },
            toggleTheme: () {},
            toggleLanguage: () {},
            vietnamese: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sync = find.byTooltip('Sync: Sign in required · 0 pending');
    await tester.tap(sync);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(syncs, 0);
    expect(logouts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final closing = db.close();
    await tester.pumpAndSettle();
    await closing;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('adaptive shell creates and completes canonical task', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.testing(NativeDatabase.memory());
    final repository = LocalRepository(db);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MindFlowShell(
            view: 'tasks',
            status: 'offline',
            sync: () {},
            logout: () async {},
            toggleTheme: () {},
            toggleLanguage: () {},
            vietnamese: false,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('MindFlow'), findsOneWidget);
    expect(find.text('offline · 0 pending'), findsNothing);
    expect(find.text('Tasks'), findsNothing);
    final syncButton = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Sync: offline · 0 pending',
      ),
    );
    expect(
      syncButton.color,
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.error,
    );
    expect(find.text('Select a task to see its details'), findsOneWidget);
    final leftDivider = find.byTooltip('Resize organization column');
    final rightDivider = find.byTooltip('Resize task details column');
    final leftStart = tester.getCenter(leftDivider).dx;
    final rightStart = tester.getCenter(rightDivider).dx;
    final workspaceRight = tester.getTopRight(find.byType(Scaffold).first).dx;
    expect(
      rightStart - leftStart - 8,
      closeTo(workspaceRight - rightStart - 4, 1),
    );
    await tester.drag(leftDivider, const Offset(60, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getCenter(leftDivider).dx, closeTo(leftStart + 60, 1));
    final rightBeforeDrag = tester.getCenter(rightDivider).dx;
    await tester.drag(rightDivider, const Offset(-80, 0), touchSlopX: 0);
    await tester.pumpAndSettle();
    expect(tester.getCenter(rightDivider).dx, closeTo(rightBeforeDrag - 80, 1));
    final dragStart = tester.getCenter(rightDivider);
    final gesture = await tester.startGesture(
      dragStart,
      kind: PointerDeviceKind.mouse,
    );
    // Multiple pointer events before a frame must all contribute to the width.
    await gesture.moveTo(dragStart + const Offset(25, 0));
    await gesture.moveTo(dragStart + const Offset(50, 0));
    await gesture.moveTo(dragStart + const Offset(75, 0));
    await tester.pump();
    expect(tester.getCenter(rightDivider).dx, closeTo(dragStart.dx + 75, 1));
    await gesture.moveTo(dragStart + const Offset(100, 0));
    await tester.pump();
    expect(tester.getCenter(rightDivider).dx, closeTo(dragStart.dx + 100, 1));
    await gesture.up();
    await tester.drag(leftDivider, const Offset(2000, 0));
    await tester.drag(rightDivider, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(rightDivider).dx - tester.getCenter(leftDivider).dx,
      greaterThanOrEqualTo(368),
    );
    expect(tester.takeException(), isNull);

    expect(find.text('New Space'), findsNothing);
    expect(find.text('Show archived'), findsNothing);
    expect(find.byTooltip('Add Spaces'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Show archived Spaces',
            ),
          )
          .isSelected,
      isFalse,
    );
    await tester.tap(find.byTooltip('Show archived Spaces'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Hide archived Spaces',
            ),
          )
          .isSelected,
      isTrue,
    );
    expect(find.byTooltip('Show archived Projects'), findsOneWidget);
    await tester.tap(find.byTooltip('Show archived Projects'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide archived Projects'), findsOneWidget);
    expect(find.byTooltip('Hide archived Spaces'), findsOneWidget);
    expect(find.byTooltip('Show archived Tags'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide archived Spaces'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show archived Spaces'), findsOneWidget);
    expect(find.byTooltip('Hide archived Projects'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide archived Projects'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Add note'), findsOneWidget);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(500, 900);
    await tester.pumpAndSettle();
    expect(find.byTooltip('MindFlow'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Spaces and filters'));
    await tester.pumpAndSettle();
    expect(find.text('My tasks'), findsOneWidget);
    Navigator.of(tester.element(find.text('My tasks'))).pop();
    tester.view.physicalSize = const Size(1400, 1000);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Write a thoughtful plan',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsOneWidget);
    await tester.tap(find.text('Write a thoughtful plan'));
    await tester.pumpAndSettle();
    expect(find.text('Task details'), findsOneWidget);
    expect(find.byKey(const ValueKey('task-detail-title')), findsOneWidget);
    await tester.tap(find.text('Markdown code'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('task-detail-notes')),
      'Saved without an edit button',
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Saved locally'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(() => db.select(db.outbox).get()),
      hasLength(2),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsNothing);
    await tester.tap(find.byTooltip('Task view options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsOneWidget);
    await tester.tap(find.text('Select tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reopen selected'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsNothing);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    final closing = db.close();
    await tester.pumpAndSettle();
    await closing;
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('all six views fit a compact viewport with enlarged text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = AppDatabase.testing(NativeDatabase.memory());
    final repository = LocalRepository(db);
    final router = GoRouter(
      initialLocation: '/tasks',
      routes: [
        GoRoute(
          path: '/:view',
          builder: (_, state) => MindFlowShell(
            view: state.pathParameters['view']!,
            status: 'offline',
            sync: () {},
            logout: () async {},
            toggleTheme: () {},
            toggleLanguage: () {},
            vietnamese: false,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repository)],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      ),
    );
    for (final view in [
      'tasks',
      'matrix',
      'habits',
      'calendar',
      'focus',
      'search',
    ]) {
      router.go('/$view');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: view);
      expect(find.text('Add task'), findsOneWidget);
      expect(
        find.byTooltip('Menu'),
        view == 'tasks' ? findsNothing : findsOneWidget,
      );
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Account and settings'), findsOneWidget);
    expect(find.byTooltip('Sync: offline · 0 pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    final closing = db.close();
    await tester.pumpAndSettle();
    await closing;
    debugDefaultTargetPlatformOverride = null;
  });
}
