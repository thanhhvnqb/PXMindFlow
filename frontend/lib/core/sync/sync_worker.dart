import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/tasks/data/local_repository.dart';
import '../db/database.dart';

class SyncWorker {
  final LocalRepository repository;
  final Dio api;
  final void Function(String) status;
  Future<void>? _running;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;
  SyncWorker(this.repository, this.api, this.status);
  Future<void> run() {
    if (_disposed) return _running ?? Future.value();
    return _running ??= _cycle().whenComplete(() => _running = null);
  }

  Future<void> _cycle() async {
    final db = repository.db;
    status('syncing');
    try {
      final device = await repository.state('device', const Uuid().v4());
      await repository.setState('device', device);
      final pending = await (db.select(
        db.outbox,
      )..orderBy([(r) => OrderingTerm.asc(r.position)])).get();
      for (final queued in pending) {
        final op = await (db.select(
          db.outbox,
        )..where((r) => r.position.equals(queued.position))).getSingleOrNull();
        if (op == null) continue;
        if (_disposed) return;
        final blocked =
            await (db.select(db.conflicts)..where(
                  (r) =>
                      r.entityId.equals(op.entityId) & r.kind.equals(op.kind),
                ))
                .getSingleOrNull();
        if (blocked != null) continue;
        // Freeze before network I/O. Crash/lost ACK retries send identical bytes.
        await (db.update(db.outbox)
              ..where((r) => r.position.equals(op.position)))
            .write(const OutboxCompanion(sent: Value(true)));
        final response = await api.post(
          '/sync/push',
          data: {
            'mutations': [
              {
                'operation_id': op.operationId,
                'device_id': device,
                'entity_type': op.kind,
                'entity_id': op.entityId,
                'operation': op.operation,
                'base_version': op.baseVersion,
                'payload': jsonDecode(op.payload),
              },
            ],
          },
        );
        final result = response.data['results'][0];
        await db.transaction(() async {
          if (result['status'] == 'applied') {
            final record = Map<String, dynamic>.from(result['record']);
            await (db.delete(
              db.outbox,
            )..where((r) => r.position.equals(op.position))).go();
            final remaining =
                await (db.select(db.outbox)..where(
                      (r) =>
                          r.entityId.equals(op.entityId) &
                          r.kind.equals(op.kind),
                    ))
                    .get();
            if (remaining.isEmpty) {
              await repository.canonical(record);
            } else {
              await (db.update(db.records)..where(
                    (r) => r.id.equals(op.entityId) & r.kind.equals(op.kind),
                  ))
                  .write(RecordsCompanion(version: Value(record['version'])));
              await (db.update(db.outbox)..where(
                    (r) =>
                        r.entityId.equals(op.entityId) &
                        r.kind.equals(op.kind) &
                        r.sent.equals(false),
                  ))
                  .write(
                    OutboxCompanion(baseVersion: Value(record['version'])),
                  );
            }
          } else {
            await repository.conflict(
              op.kind,
              op.entityId,
              result['record'],
              result['status'] == 'validation_failure'
                  ? 'validation_failure:${result['code'] ?? 'invalid_payload'}'
                  : result['code'] ?? 'version_conflict',
            );
          }
        });
      }
      bool more;
      do {
        if (_disposed) return;
        final cursor = int.parse(await repository.state('cursor', '0'));
        final response = await api.get(
          '/sync/pull',
          queryParameters: {'cursor': cursor, 'limit': 100},
        );
        final page = response.data;
        await db.transaction(() async {
          int previous = cursor;
          for (final change in page['changes']) {
            final sequence = change['sequence'] as int;
            if (sequence <= previous) {
              throw StateError('Non-monotonic pull page');
            }
            previous = sequence;
            final record = Map<String, dynamic>.from(change['record']);
            final local = await repository.get(
              record['entity_type'],
              record['id'],
            );
            if (local != null && local.version >= record['version']) continue;
            final pending =
                await (db.select(db.outbox)..where(
                      (r) =>
                          r.entityId.equals(record['id']) &
                          r.kind.equals(record['entity_type']),
                    ))
                    .get();
            if (pending.isEmpty) {
              await repository.canonical(record);
            } else {
              await repository.conflict(
                record['entity_type'],
                record['id'],
                record,
                'remote_change_with_pending_edit',
              );
            }
          }
          if (page['next_cursor'] != previous) {
            throw StateError('Invalid pull cursor');
          }
          await repository.setState('cursor', '${page['next_cursor']}');
        });
        more = page['has_more'];
      } while (more);
      _failures = 0;
      final conflicts = await db.select(db.conflicts).get();
      final remaining = await db.select(db.outbox).get();
      status(
        conflicts.isNotEmpty
            ? 'attention'
            : remaining.isNotEmpty
            ? 'pending'
            : 'synced',
      );
    } catch (error) {
      if (error is DioException &&
          [401, 403].contains(error.response?.statusCode)) {
        status('sign_in_required');
        return;
      }
      if (error is DioException &&
          error.response?.statusCode == 409 &&
          error.response?.data is Map &&
          error.response?.data['detail'] == 'cursor_ahead') {
        // Re-read retained history without destroying any local records/outbox.
        await repository.setState('cursor', '0');
      }
      status('offline');
      if (!_disposed) {
        _failures++;
        _retry?.cancel();
        _retry = Timer(
          Duration(
            seconds: min(300, 1 << min(_failures, 8)) + Random().nextInt(4),
          ),
          run,
        );
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
  }
}
