import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';
import 'package:mindflow/features/tasks/domain/item.dart';
import 'package:mindflow/features/tasks/domain/organization.dart';
import 'package:mindflow/features/tasks/domain/task_query.dart';

void main() {
  late AppDatabase db;
  late LocalRepository repo;
  setUp(() {
    db = AppDatabase.testing(NativeDatabase.memory());
    repo = LocalRepository(db);
  });
  tearDown(() => db.close());
  Future<List<Item>> items() => repo.watch().first;
  Future<void> seed() async {
    for (final id in ['a', 'b', 'c']) {
      await repo.save('tag', {'title': id}, id: id);
    }
    await repo.save('task_list', {
      'title': 'Teaching',
      'tag_ids': ['a'],
    }, id: 's');
    await repo.save('task_list', {'title': 'Research'}, id: 'r');
    await repo.save('project', {
      'title': 'Semester',
      'space_id': 's',
      'tag_ids': ['b'],
    }, id: 'p');
    await repo.save('task', {
      'title': 'Prepare',
      'project_id': 'p',
      'tag_ids': ['c'],
    }, id: 't');
    await repo.save('task', {'title': 'Slides', 'parent_id': 't'}, id: 'child');
    await repo.save('task', {'title': 'Inbox'}, id: 'inbox');
  }

  test(
    'nested subtasks derive Space context and detach without copying tags',
    () async {
      await repo.save('tag', {'title': 'Work'}, id: 'work');
      await repo.save('task_list', {
        'title': 'Space',
        'tag_ids': ['work'],
      }, id: 'space');
      await repo.save('task', {
        'title': 'Root',
        'list_id': 'space',
      }, id: 'root');
      var parent = 'root';
      for (var level = 1; level <= 4; level++) {
        await repo.save('task', {
          'title': 'Level $level',
          'parent_id': parent,
        }, id: 'level$level');
        parent = 'level$level';
      }
      expect(
        TaskQuery(tagId: 'work').apply(await items(), DateTime.now()),
        hasLength(5),
      );
      await repo.updateTasks(['level1'], {'parent_id': null});
      expect(
        TaskQuery(tagId: 'work').apply(await items(), DateTime.now()).single.id,
        'root',
      );
      expect(
        const TaskQuery(view: 'Inbox').apply(await items(), DateTime.now()),
        hasLength(4),
      );
    },
  );
  test(
    'offline search includes Space, Project and archived Tag records',
    () async {
      await seed();
      await repo.save('tag', {
        'title': 'LegacyTeaching',
        'archived_at': '2026-10-17T00:00:00Z',
      }, id: 'archived');
      expect((await repo.search('Teaching').first).single.kind, 'task_list');
      expect((await repo.search('Semester').first).single.kind, 'project');
      expect((await repo.search('LegacyTeaching').first).single.kind, 'tag');
    },
  );
  test(
    'effective tags follow actual ancestry and preserve direct bindings',
    () async {
      await seed();
      final all = await items();
      for (final tag in ['a', 'b', 'c']) {
        expect(
          TaskQuery(tagId: tag)
              .apply(all, DateTime.now())
              .map((i) => i.id)
              .toSet(),
          {'t', 'child'},
        );
      }
      expect(
        Organization(all).directTags(all.firstWhere((i) => i.id == 'child')),
        isEmpty,
      );
      expect(
        const TaskQuery(view: 'Inbox').apply(all, DateTime.now()).single.id,
        'inbox',
      );
    },
  );
  test(
    'moving project or parent recalculates subtree tags and archive',
    () async {
      await seed();
      await repo.save('project', {
        'title': 'Semester',
        'space_id': 'r',
        'tag_ids': ['b'],
        'status': 'completed',
      }, id: 'p');
      expect(
        TaskQuery(tagId: 'a').apply(await items(), DateTime.now()),
        isEmpty,
      );
      await repo.save('task_list', {
        'title': 'Research',
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      }, id: 'r');
      expect(
        const TaskQuery().apply(await items(), DateTime.now()).map((i) => i.id),
        ['inbox'],
      );
      expect(
        const TaskQuery(includeArchived: true)
            .apply(await items(), DateTime.now()),
        hasLength(3),
      );
      final task = jsonDecode((await repo.get('task', 't'))!.payload);
      expect(task['archived_at'], isNull);
      await repo.save('task_list', {
        'title': 'Research',
        'archived_at': null,
      }, id: 'r');
      expect(
        const TaskQuery().apply(await items(), DateTime.now()),
        hasLength(3),
      );
      await repo.updateTasks(['t'], {'project_id': null, 'list_id': 's'});
      expect(
        TaskQuery(tagId: 'a').apply(await items(), DateTime.now()),
        hasLength(2),
      );
      expect(
        TaskQuery(tagId: 'b').apply(await items(), DateTime.now()),
        isEmpty,
      );
    },
  );
  test(
    'archived tags keep associations; unassign does not affect ancestors',
    () async {
      await seed();
      await repo.save('tag', {
        'title': 'a',
        'archived_at': DateTime.now().toUtc().toIso8601String(),
      }, id: 'a');
      expect(
        TaskQuery(tagId: 'a').apply(await items(), DateTime.now()),
        hasLength(2),
      );
      await repo.updateTasks(['t'], {'tag_ids': []});
      expect(
        TaskQuery(tagId: 'c').apply(await items(), DateTime.now()),
        isEmpty,
      );
      expect(
        TaskQuery(tagId: 'a').apply(await items(), DateTime.now()),
        hasLength(2),
      );
      await repo.save('tag', {'title': 'a', 'archived_at': null}, id: 'a');
      expect(
        TaskQuery(tagId: 'a').apply(await items(), DateTime.now()),
        hasLength(2),
      );
    },
  );
  test(
    'invalid references, mixed placement and cycles roll back outbox',
    () async {
      await seed();
      final count = (await db.select(db.outbox).get()).length;
      for (final patch in [
        {'project_id': 'missing'},
        {'list_id': 's'},
        {'project_id': null, 'parent_id': 'child'},
      ]) {
        await expectLater(repo.updateTasks(['t'], patch), throwsStateError);
      }
      expect(await db.select(db.outbox).get(), hasLength(count));
      await expectLater(
        repo.save('task_list', {'title': 'Teaching'}, id: 's', delete: true),
        throwsStateError,
      );
      await repo.updateTasks(['t'], {}, delete: true);
      expect(
        (await items()).where((i) => ['t', 'child'].contains(i.id)),
        isEmpty,
      );
    },
  );
  test(
    'v2 upgrade preserves records and frozen pending operation bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'organization_migration',
      );
      final file = File('${directory.path}/local.sqlite');
      final original = AppDatabase.testing(NativeDatabase(file));
      final local = LocalRepository(original);
      await local.save('task_list', {'title': 'Legacy'}, id: 'old');
      await local.save('task', {
        'title': 'Unsent',
        'list_id': 'old',
      }, id: 'old-task');
      final before = await original.select(original.outbox).get();
      await original.customStatement('UPDATE outbox SET sent = 1');
      for (final key in [
        'list_id',
        'space_id',
        'project_id',
        'parent_id',
        'archived_at',
      ]) {
        await original.customStatement('DROP INDEX records_$key');
      }
      await original.customStatement('PRAGMA user_version = 2');
      await original.close();
      final upgraded = AppDatabase.testing(NativeDatabase(file));
      try {
        final pending = await upgraded.select(upgraded.outbox).get();
        expect(
          pending.map((r) => r.operationId),
          before.map((r) => r.operationId),
        );
        expect(pending.map((r) => r.payload), before.map((r) => r.payload));
        expect(pending.every((r) => r.sent), isTrue);
        expect(
          (await LocalRepository(
            upgraded,
          ).watch().first).map((i) => i.id).toSet(),
          {'old', 'old-task'},
        );
        final indexes = await upgraded
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'records_%'",
            )
            .get();
        expect(indexes, hasLength(5));
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
