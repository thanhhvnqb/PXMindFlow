import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:mindflow/core/db/database.dart';
import 'package:mindflow/core/sync/sync_worker.dart';
import 'package:mindflow/features/tasks/data/local_repository.dart';

void main() {
  const url = String.fromEnvironment('TEST_API_URL');
  test(
    'real PostgreSQL API: two offline clients, lost ACK, conflict resolution and isolation',
    () async {
      final transport = Dio(
        BaseOptions(baseUrl: url, receiveTimeout: const Duration(seconds: 15)),
      );
      Future<Dio> account() async {
        final response = await transport.post(
          '/auth/register',
          data: {
            'email': '${const Uuid().v4()}@integration.example',
            'password': 'integration test password',
          },
        );
        return Dio(
          BaseOptions(
            baseUrl: url,
            headers: {
              'Authorization': 'Bearer ${response.data['access_token']}',
            },
          ),
        );
      }

      final api = await account();
      final foreign = await account();
      final dbA = AppDatabase.testing(NativeDatabase.memory());
      final dbB = AppDatabase.testing(NativeDatabase.memory());
      final repoA = LocalRepository(dbA), repoB = LocalRepository(dbB);
      final workerA = SyncWorker(repoA, api, (_) {}),
          workerB = SyncWorker(repoB, api, (_) {});
      try {
        final project = const Uuid().v4(), task = const Uuid().v4();
        await repoA.save('task_list', {
          'title': 'Offline project',
        }, id: project);
        await repoA.save('task', {
          'title': 'Offline task',
          'list_id': project,
        }, id: task);
        await workerA.run();
        await workerB.run();
        expect((await repoB.get('task', task))?.version, 1);
        await repoA.save('task', {'title': 'Device A'}, id: task);
        await repoB.save('task', {'title': 'Device B'}, id: task);
        await Future.wait([workerA.run(), workerB.run()]);
        final conflictsA = await dbA.select(dbA.conflicts).get();
        final conflictsB = await dbB.select(dbB.conflicts).get();
        expect(conflictsA.length + conflictsB.length, 1);
        final losing = conflictsA.isNotEmpty ? repoA : repoB;
        final losingWorker = conflictsA.isNotEmpty ? workerA : workerB;
        await losing.resolve((conflictsA + conflictsB).single, mine: true);
        await losingWorker.run();
        expect((await losing.get('task', task))!.version, 3);
        expect(await losing.db.select(losing.db.outbox).get(), isEmpty);
        // Drop an actual successful HTTP response after server commit.
        bool drop = true;
        api.interceptors.add(
          InterceptorsWrapper(
            onResponse: (response, handler) {
              if (drop && response.requestOptions.path == '/sync/push') {
                drop = false;
                handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              } else {
                handler.next(response);
              }
            },
          ),
        );
        final lost = const Uuid().v4();
        await repoA.save('task', {'title': 'Lost acknowledgement'}, id: lost);
        await workerA.run();
        expect(await dbA.select(dbA.outbox).get(), hasLength(1));
        await workerA.run();
        expect((await repoA.get('task', lost))!.version, 1);
        expect(await dbA.select(dbA.outbox).get(), isEmpty);
        final page = await foreign.get(
          '/sync/pull',
          queryParameters: {'cursor': 0},
        );
        expect(page.data['changes'], isEmpty);
        await repoA.save(
          'task',
          {'title': 'Lost acknowledgement'},
          id: lost,
          delete: true,
        );
        await workerA.run();
        await workerB.run();
        expect(
          jsonDecode((await repoB.get('task', lost))!.payload)['deleted_at'],
          isNotNull,
        );
      } finally {
        workerA.dispose();
        workerB.dispose();
        await dbA.close();
        await dbB.close();
        api.close();
        foreign.close();
        transport.close();
      }
    },
    skip: url.isEmpty ? 'Set TEST_API_URL for the isolated Docker API' : false,
  );
}
