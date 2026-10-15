import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:mindflow/app/providers.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';
import 'package:mindflow/shared/shell.dart';

void main() {
  testWidgets('adaptive shell creates and completes canonical task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
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
    expect(find.text('MindFlow'), findsOneWidget);
    await tester.tap(find.text('Add task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Write a thoughtful plan',
    );
    await tester.tap(find.text('Save'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsOneWidget);
    expect(
      await tester.runAsync(() => db.select(db.outbox).get()),
      hasLength(1),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsNothing);
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Write a thoughtful plan'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    final closing = db.close();
    await tester.pumpAndSettle();
    await closing;
  });
  testWidgets('all six views fit a compact viewport with enlarged text', (
    tester,
  ) async {
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
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
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    final closing = db.close();
    await tester.pumpAndSettle();
    await closing;
  });
}
