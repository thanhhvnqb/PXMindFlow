import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/app/mindflow_app.dart';
import 'package:mindflow/core/auth/auth_controller.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';

class TestAuth extends AuthController {
  final api = Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            data: {'changes': [], 'next_cursor': 0, 'has_more': false},
          ),
        ),
      ),
    );
  int logins = 0;

  @override
  Future<Account?> restore() async => null;

  @override
  Future<Account> login(String email, String password, bool register) async {
    logins++;
    return Account('test-account', api);
  }
}

void main() {
  testWidgets('successful sign in replaces login page with task shell', (
    tester,
  ) async {
    final auth = TestAuth();
    final db = AppDatabase.testing(NativeDatabase.memory());
    await tester.runAsync(
      () => LocalRepository(db).save('task', {'title': 'Saved before sign in'}),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MindFlowApp(auth: auth, databaseFactory: (_, _) => db),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      'test-password-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(auth.logins, 1);
    expect(find.text('Make room for what matters.'), findsNothing);
    expect(find.text('Add task'), findsOneWidget);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Saved before sign in'), findsOneWidget);
    expect(
      find.text('Could not open local storage. Retry by restarting.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.runAsync(db.close);
  });
  testWidgets(
    'storage failure pauses startup and retry retains pending edits',
    (tester) async {
      final auth = TestAuth();
      final db = AppDatabase.testing(NativeDatabase.memory());
      final repo = LocalRepository(db);
      await tester.runAsync(
        () => repo.save('task', {'title': 'Unsynced task'}),
      );
      var attempts = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MindFlowApp(
            auth: auth,
            databaseFactory: (_, _) {
              attempts++;
              if (attempts == 1) {
                throw StateError('Storage blocked for regression test');
              }
              return db;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'test@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'test-password-123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Local storage is unavailable'), findsOneWidget);
      expect(find.text('Add task'), findsNothing);
      await tester.tap(find.text('Diagnostic details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Storage blocked for regression test'),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(() => db.select(db.outbox).get()),
        hasLength(1),
      );
      await tester.tap(find.text('Retry storage'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('Unsynced task'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(db.close);
    },
  );
}
