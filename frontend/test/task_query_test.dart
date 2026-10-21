import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';
import 'package:mindflow/features/tasks/domain/item.dart';
import 'package:mindflow/features/tasks/domain/task_query.dart';

void main() {
  test(
    'Next 7 days uses local calendar boundaries and excludes completed tasks',
    () {
      final items = [
        for (final day in [14, 15, 21, 22])
          Item('$day', 'task', 0, {
            'title': '$day',
            'due_date': '2026-10-$day',
          }),
        Item('done', 'task', 0, {
          'title': 'Done',
          'due_date': '2026-10-16',
          'completed': true,
        }),
      ];
      expect(
        const TaskQuery(
          view: 'Next 7 days',
          sort: 'due',
        ).apply(items, DateTime(2026, 10, 15, 23, 59)).map((i) => i.id),
        ['15', '21'],
      );
    },
  );

  test('task views intersect list and priority; dates sort before undated', () {
    final items = [
      Item('a', 'task', 0, {'title': 'Undated', 'priority': 3}),
      Item('b', 'task', 0, {
        'title': 'Overdue',
        'priority': 3,
        'due_date': '2026-10-14',
        'list_id': 'work',
      }),
      Item('c', 'task', 0, {'title': 'Tomorrow', 'due_date': '2026-10-16'}),
      Item('d', 'task', 0, {'title': 'Done', 'completed': true}),
      Item('e', 'task', 0, {'title': 'Deleted', 'deleted_at': '2026-10-15'}),
    ];
    final now = DateTime(2026, 10, 15);
    expect(const TaskQuery(view: 'Inbox').apply(items, now).map((i) => i.id), [
      'a',
      'c',
    ]);
    expect(
      const TaskQuery(
        view: 'Today',
        listId: 'work',
        priority: 3,
      ).apply(items, now).single.id,
      'b',
    );
    expect(const TaskQuery(view: 'Upcoming').apply(items, now).single.id, 'c');
    expect(const TaskQuery(sort: 'due').apply(items, now).map((i) => i.id), [
      'b',
      'c',
      'a',
    ]);
    expect(const TaskQuery(view: 'Completed').apply(items, now).single.id, 'd');
  });

  test(
    'bulk writes preserve current notes and queue one mutation per live task',
    () async {
      final db = AppDatabase.testing(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = LocalRepository(db);
      await repo.save('task', {
        'title': 'One',
        'notes': 'latest notes',
      }, id: 'one');
      await repo.save('task', {'title': 'Two'}, id: 'two');
      await repo.updateTasks(
        ['one', 'two', 'one', 'missing'],
        {'completed': true},
      );
      final first = jsonDecode((await repo.get('task', 'one'))!.payload);
      expect(first['notes'], 'latest notes');
      expect(first['completed'], true);
      expect(await db.select(db.outbox).get(), hasLength(4));
      await repo.updateTasks(['one', 'two'], {}, delete: true);
      expect(await repo.watch().first, isEmpty);
      expect(await db.select(db.outbox).get(), hasLength(6));
      await repo.updateTasks(['one'], {'completed': false});
      expect(await db.select(db.outbox).get(), hasLength(6));
    },
  );
}
