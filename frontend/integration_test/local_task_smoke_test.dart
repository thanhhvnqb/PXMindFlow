import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:mindflow/app/providers.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';
import 'package:mindflow/shared/shell.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('platform SQLite task creation survives database reopen', (
    tester,
  ) async {
    final account = 'smoke_${const Uuid().v4()}';
    final db = AppDatabase(account);
    final repo = LocalRepository(db);
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
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Platform storage smoke test',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Platform storage smoke test'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    router.dispose();
    await db.close();
    final reopened = AppDatabase(account);
    final rows = await LocalRepository(reopened).watch().first;
    expect(rows.single.title, 'Platform storage smoke test');
    expect(await reopened.select(reopened.outbox).get(), hasLength(1));
    await reopened.close();
    // Unique smoke database is retained; never purge another account's data.
  });
}
