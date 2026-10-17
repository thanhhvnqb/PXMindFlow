import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';

void main() {
  test(
    'Multiple offline notes keep independent identity, search and outbox',
    () async {
      final db = AppDatabase.testing(NativeDatabase.memory());
      final repo = LocalRepository(db);
      addTearDown(db.close);
      await repo.save('task_list', {'title': 'Space'}, id: 'space');
      for (final id in ['first', 'second']) {
        await repo.save('note', {
          'title': id,
          'list_id': 'space',
          'notes': '**Markdown**',
        }, id: id);
      }
      expect(
        (await repo.watch().first).where((i) => i.kind == 'note'),
        hasLength(2),
      );
      expect(await repo.watchPending().first, 3);
      expect(await repo.search('Markdown').first, hasLength(2));
      await expectLater(
        repo.save('task_list', {'title': 'Space'}, id: 'space', delete: true),
        throwsStateError,
      );
      await repo.save(
        'note',
        {'title': 'first', 'list_id': 'space', 'notes': 'changed'},
        id: 'first',
        delete: true,
      );
      expect(
        (await repo.watch().first).where((i) => i.kind == 'note'),
        hasLength(1),
      );
      expect(await repo.watchPending().first, 4);
    },
  );
}
