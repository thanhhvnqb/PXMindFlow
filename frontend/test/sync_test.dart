import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/core/sync/sync_worker.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';

class Server implements HttpClientAdapter {
  final records = <String, Map<String, dynamic>>{};
  final operations = <String, Map<String, dynamic>>{};
  final requests = <Map<String, dynamic>>[];
  final changes = <Map<String, dynamic>>[];
  bool loseAck = false;
  bool badPage = false;
  bool authFailure = false;
  bool rejectPayload = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (authFailure) {
      return ResponseBody.fromString(
        '{"detail":"invalid_access_token"}',
        401,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (options.path == '/sync/push') {
      final op = Map<String, dynamic>.from(options.data['mutations'][0]);
      requests.add(op);
      final id = op['operation_id'] as String;
      var result = operations[id];
      if (result == null) {
        final current = records[op['entity_id']];
        if (rejectPayload) {
          result = {
            'operation_id': id,
            'status': 'validation_failure',
            'code': 'invalid_payload',
          };
        } else if (op['base_version'] != (current?['version'] ?? 0)) {
          result = {
            'operation_id': id,
            'status': 'conflict',
            'record': current,
          };
        } else {
          final record = {
            'id': op['entity_id'],
            'entity_type': op['entity_type'],
            'version': (current?['version'] as int? ?? 0) + 1,
            'payload': {
              ...op['payload'],
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
              'deleted_at': op['operation'] == 'delete'
                  ? '2026-01-01T00:00:00Z'
                  : null,
            },
          };
          records[op['entity_id']] = record;
          changes.add({'sequence': changes.length + 1, 'record': record});
          result = {'operation_id': id, 'status': 'applied', 'record': record};
        }
        operations[id] = result;
      }
      if (loseAck) {
        loseAck = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }
      return ResponseBody.fromString(
        jsonEncode({
          'results': [result],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    final cursor = options.queryParameters['cursor'] as int;
    final page = changes.where((c) => (c['sequence'] as int) > cursor).toList();
    if (badPage) page.addAll(page.toList());
    return ResponseBody.fromString(
      jsonEncode({
        'changes': page,
        'next_cursor': page.isEmpty ? cursor : page.last['sequence'],
        'has_more': false,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late AppDatabase db;
  late LocalRepository repo;
  late Server server;
  late SyncWorker worker;
  late String status;
  setUp(() {
    db = AppDatabase.testing(NativeDatabase.memory());
    repo = LocalRepository(db);
    server = Server();
    final api = Dio()..httpClientAdapter = server;
    worker = SyncWorker(repo, api, (v) => status = v);
  });
  tearDown(() async {
    worker.dispose();
    await db.close();
  });
  test(
    'organization dependency order and lost ACK preserve placement edits',
    () async {
      await repo.save('tag', {'title': 'QBU'}, id: 'tag');
      await repo.save('task_list', {
        'title': 'Teaching',
        'tag_ids': ['tag'],
      }, id: 'space');
      await repo.save('project', {
        'title': 'Semester',
        'space_id': 'space',
      }, id: 'project');
      await repo.save('task', {
        'title': 'Prepare',
        'project_id': 'project',
      }, id: 'task');
      await repo.save('task', {
        'title': 'Slides',
        'parent_id': 'task',
      }, id: 'child');
      server.loseAck = true;
      await worker.run();
      await repo.updateTasks(
        ['task'],
        {'project_id': null, 'list_id': 'space'},
      );
      await worker.run();
      expect(status, 'synced');
      expect(await db.select(db.outbox).get(), isEmpty);
      expect(server.requests.map((r) => r['entity_type']), [
        'tag',
        'tag',
        'task_list',
        'project',
        'task',
        'task',
        'task',
      ]);
      expect(server.records['task']!['payload']['list_id'], 'space');
      expect(server.records['task']!['version'], 2);
      expect(server.records['child']!['payload']['parent_id'], 'task');
    },
  );
  test('retry rejected update preserves version and uses fresh operation after API upgrade', () async {
    await repo.save('task', {'title': 'Original'}, id: 'one');
    await worker.run();
    await repo.updateTasks(
      ['one'],
      {'title': 'Keep this edit', 'project_id': null},
    );
    server.rejectPayload = true;
    await worker.run();
    expect(status, 'attention');
    final rejection = (await db.select(db.conflicts).get()).single;
    expect(rejection.reason, 'validation_failure:invalid_payload');
    final rejectedOp = (await db.select(db.outbox).get()).single.operationId;
    server.rejectPayload = false;
    await repo.resolve(rejection, mine: true);
    final retry = (await db.select(db.outbox).get()).single;
    expect(retry.operation, 'update');
    expect(retry.baseVersion, 1);
    expect(retry.operationId, isNot(rejectedOp));
    expect(
      jsonDecode((await repo.get('task', 'one'))!.payload)['title'],
      'Keep this edit',
    );
    await worker.run();
    expect(status, 'synced');
    expect(server.records['one']!['version'], 2);
    expect(server.records['one']!['payload']['title'], 'Keep this edit');
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(await db.select(db.conflicts).get(), isEmpty);
  });
  test(
    'legacy invalid_payload without snapshot never discards local data',
    () async {
      await repo.save('task', {'title': 'Original'}, id: 'one');
      await worker.run();
      await repo.updateTasks(['one'], {'title': 'Latest local edit'});
      await repo.conflict('task', 'one', null, 'invalid_payload');
      final rejection = (await db.select(db.conflicts).get()).single;
      await expectLater(repo.resolve(rejection, mine: false), throwsStateError);
      expect(await db.select(db.outbox).get(), hasLength(1));
      expect((await repo.get('task', 'one'))!.version, 1);
      await repo.resolve(rejection, mine: true);
      await worker.run();
      expect(status, 'synced');
      expect(server.records['one']!['payload']['title'], 'Latest local edit');
    },
  );
  test(
    'retry rejected new task remains a create and preserves its ID',
    () async {
      server.rejectPayload = true;
      await repo.save('task', {'title': 'Never uploaded'}, id: 'new');
      await worker.run();
      final rejected = (await db.select(db.conflicts).get()).single;
      server.rejectPayload = false;
      await repo.resolve(rejected, mine: true);
      expect((await db.select(db.outbox).get()).single.operation, 'create');
      expect((await repo.get('task', 'new'))!.version, 0);
      await worker.run();
      expect(status, 'synced');
      expect(server.records['new']!['payload']['title'], 'Never uploaded');
    },
  );
  test('atomic write rollback retains neither domain nor outbox', () async {
    try {
      await db.transaction(() async {
        await repo.save('task', {'title': 'Rollback'});
        throw StateError('crash');
      });
    } catch (_) {}
    expect(await db.select(db.records).get(), isEmpty);
    expect(await db.select(db.outbox).get(), isEmpty);
  });
  test(
    'offline create edit delete sequence uses acknowledged versions',
    () async {
      await repo.save('task', {'title': 'First'}, id: 'one');
      await repo.save('task', {'title': 'Second'}, id: 'one');
      await repo.save('task', {'title': 'Second'}, id: 'one', delete: true);
      await worker.run();
      expect(status, 'synced');
      expect(server.requests.map((r) => r['base_version']), [0, 1, 2]);
      expect(await db.select(db.outbox).get(), isEmpty);
      expect(
        jsonDecode((await repo.get('task', 'one'))!.payload)['deleted_at'],
        isNotNull,
      );
    },
  );
  test('lost ACK then later edit replays frozen operation without overwriting edit', () async {
    await repo.save('task', {'title': 'First'}, id: 'one');
    server.loseAck = true;
    await worker.run();
    expect(status, 'offline');
    await repo.save('task', {'title': 'Later'}, id: 'one');
    await worker.run();
    expect(status, 'synced');
    expect(server.requests[0], server.requests[1]);
    expect(
      jsonDecode((await repo.get('task', 'one'))!.payload)['title'],
      'Later',
    );
    expect(server.records['one']!['version'], 2);
  });
  test(
    'two devices retain conflicts and keep mine against remote version',
    () async {
      await repo.save('task', {'title': 'Base'}, id: 'one');
      await worker.run();
      final db2 = AppDatabase.testing(NativeDatabase.memory());
      final repo2 = LocalRepository(db2);
      final worker2 = SyncWorker(
        repo2,
        Dio()..httpClientAdapter = server,
        (_) {},
      );
      await worker2.run();
      await repo.save('task', {'title': 'Device A'}, id: 'one');
      await repo2.save('task', {'title': 'Device B'}, id: 'one');
      await worker.run();
      await worker2.run();
      expect(
        jsonDecode((await repo2.get('task', 'one'))!.payload)['title'],
        'Device B',
      );
      final conflicts = await db2.select(db2.conflicts).get();
      expect(conflicts, hasLength(1));
      await repo2.resolve(conflicts.single, mine: true);
      await worker2.run();
      expect(server.records['one']!['payload']['title'], 'Device B');
      expect(server.records['one']!['version'], 3);
      worker2.dispose();
      await db2.close();
    },
  );
  test('nonmonotonic page rolls back data and cursor', () async {
    server.changes.add({
      'sequence': 1,
      'record': {
        'id': 'one',
        'entity_type': 'task',
        'version': 1,
        'payload': {'title': 'Remote'},
      },
    });
    server.badPage = true;
    await worker.run();
    expect(status, 'offline');
    expect(await repo.state('cursor', '0'), '0');
    expect(await db.select(db.records).get(), isEmpty);
  });
  test('overlapping cycles share one worker future', () async {
    await repo.save('task', {'title': 'Once'}, id: 'one');
    await Future.wait([worker.run(), worker.run(), worker.run()]);
    expect(server.requests, hasLength(1));
  });
  test(
    'authentication failure preserves pending data and asks for sign-in',
    () async {
      await repo.save('task', {'title': 'Must be retained'}, id: 'one');
      server.authFailure = true;
      await worker.run();
      expect(status, 'sign_in_required');
      expect(await db.select(db.outbox).get(), hasLength(1));
      expect(
        jsonDecode((await repo.get('task', 'one'))!.payload)['title'],
        'Must be retained',
      );
    },
  );
  test(
    'editing during attention keeps the latest local payload on resolution',
    () async {
      await repo.save('task', {'title': 'First local'}, id: 'one');
      await repo.conflict('task', 'one', {
        'id': 'one',
        'entity_type': 'task',
        'version': 2,
        'payload': {'title': 'Remote'},
      }, 'version_conflict');
      final openedDialog = (await db.select(db.conflicts).get()).single;
      await repo.save('task', {'title': 'Later local'}, id: 'one');
      await repo.resolve(openedDialog, mine: true);
      expect(
        jsonDecode((await repo.get('task', 'one'))!.payload)['title'],
        'Later local',
      );
      final pending = await db.select(db.outbox).get();
      expect(pending, hasLength(1));
      expect(pending.single.baseVersion, 2);
      expect(jsonDecode(pending.single.payload)['title'], 'Later local');
    },
  );
  test('FTS index updates with canonical edits and tombstones', () async {
    await repo.save('task', {
      'title': 'Design a calmer morning',
      'notes': 'Review project roadmap',
    }, id: 'search');
    expect(await repo.state('fts', 'false'), 'true');
    expect((await repo.search('roadmap').first).single.id, 'search');
    await repo.save('task', {
      'title': 'Changed title',
      'notes': 'Another note',
    }, id: 'search');
    expect(await repo.search('roadmap').first, isEmpty);
    expect((await repo.search('Changed').first).single.title, 'Changed title');
    await repo.save(
      'task',
      {'title': 'Changed title'},
      id: 'search',
      delete: true,
    );
    expect(await repo.search('Changed').first, isEmpty);
  });
  test('two check-ins on one calendar day share the same identity', () async {
    await repo.save('habit', {'title': 'Read'}, id: 'habit');
    final payload = {
      'habit_id': 'habit',
      'local_date': '2026-10-13',
      'timezone': 'Etc/UTC',
      'count': 1,
    };
    await repo.save('habit_checkin', payload);
    await repo.save('habit_checkin', payload);
    expect(
      (await repo.watch().first).where((i) => i.kind == 'habit_checkin'),
      hasLength(1),
    );
  });
  test(
    'keep server explicitly clears pending conflict without a new write',
    () async {
      await repo.save('task', {'title': 'Local'}, id: 'one');
      final remote = {
        'id': 'one',
        'entity_type': 'task',
        'version': 2,
        'payload': {'title': 'Server'},
      };
      await repo.conflict('task', 'one', remote, 'test');
      await repo.resolve(
        (await db.select(db.conflicts).get()).single,
        mine: false,
      );
      expect(await db.select(db.outbox).get(), isEmpty);
      expect(
        jsonDecode((await repo.get('task', 'one'))!.payload)['title'],
        'Server',
      );
    },
  );
  test('disk restart retains unsent local data and outbox', () async {
    final directory = await Directory.systemTemp.createTemp('mindflow_test');
    final file = File('${directory.path}/store.sqlite');
    var disk = AppDatabase.testing(NativeDatabase(file));
    await LocalRepository(disk)
        .save('task', {'title': 'Offline restart'}, id: 'restart');
    await disk.close();
    disk = AppDatabase.testing(NativeDatabase(file));
    expect((await LocalRepository(disk).get('task', 'restart'))!.version, 0);
    expect(await disk.select(disk.outbox).get(), hasLength(1));
    await disk.close();
    await directory.delete(recursive: true);
  });
}
