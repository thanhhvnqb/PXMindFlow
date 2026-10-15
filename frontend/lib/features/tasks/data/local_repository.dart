import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/database.dart';
import '../domain/item.dart';

class LocalRepository {
  final AppDatabase db;
  LocalRepository(this.db);
  Stream<List<Item>> watch() => db
      .select(db.records)
      .watch()
      .map(
        (rows) => rows
            .map((r) => Item(r.id, r.kind, r.version, jsonDecode(r.payload)))
            .where((r) => !r.deleted)
            .toList(),
      );
  Stream<List<Item>> search(String query) async* {
    if (query.trim().isEmpty) {
      yield* watch().map(
        (items) => items
            .where((i) => ['task', 'task_list', 'habit'].contains(i.kind))
            .toList(),
      );
      return;
    }
    final fts = await state('fts', 'false');
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) => '"${word.replaceAll('"', '""')}"*')
        .join(' AND ');
    final sql = fts == 'true'
        ? "SELECT r.* FROM records r JOIN record_fts f ON r.id = f.id AND r.kind = f.kind WHERE record_fts MATCH ? AND r.kind IN ('task', 'task_list', 'habit') AND json_extract(r.payload, '\$.deleted_at') IS NULL ORDER BY rank LIMIT 200"
        : "SELECT * FROM records WHERE kind IN ('task', 'task_list', 'habit') AND json_extract(payload, '\$.deleted_at') IS NULL AND (instr(lower(json_extract(payload, '\$.title')), lower(?)) > 0 OR instr(lower(coalesce(json_extract(payload, '\$.notes'), '')), lower(?)) > 0) LIMIT 200";
    yield* db
        .customSelect(
          sql,
          variables: fts == 'true'
              ? [Variable<String>(words)]
              : [Variable<String>(query), Variable<String>(query)],
          readsFrom: {db.records},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => Item(
                  r.read<String>('id'),
                  r.read<String>('kind'),
                  r.read<int>('version'),
                  jsonDecode(r.read<String>('payload')),
                ),
              )
              .toList(),
        );
  }

  Stream<List<Conflict>> watchConflicts() => db.select(db.conflicts).watch();
  Stream<int> watchPending() =>
      db.select(db.outbox).watch().map((rows) => rows.length);
  Future<Record?> get(String kind, String id) => (db.select(
    db.records,
  )..where((r) => r.id.equals(id) & r.kind.equals(kind))).getSingleOrNull();
  Future<void> save(
    String kind,
    Map<String, dynamic> payload, {
    String? id,
    bool delete = false,
  }) async {
    final entityId =
        id ??
        (kind == 'habit_checkin'
            ? const Uuid().v5(
                Namespace.url.value,
                '${payload['habit_id']}/${payload['local_date']}/${payload['timezone']}',
              )
            : const Uuid().v4());
    await db.transaction(() async {
      final current = await get(kind, entityId);
      final data = {
        ...payload,
        'created_at': current == null
            ? DateTime.now().toUtc().toIso8601String()
            : jsonDecode(current.payload)['created_at'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_at': delete ? DateTime.now().toUtc().toIso8601String() : null,
      };
      await db
          .into(db.records)
          .insertOnConflictUpdate(
            RecordsCompanion.insert(
              id: entityId,
              kind: kind,
              payload: jsonEncode(data),
              version: Value(current?.version ?? 0),
            ),
          );
      await (db.update(db.conflicts)
            ..where((r) => r.entityId.equals(entityId) & r.kind.equals(kind)))
          .write(ConflictsCompanion(local: Value(jsonEncode(data))));
      await db
          .into(db.outbox)
          .insert(
            OutboxCompanion.insert(
              operationId: const Uuid().v4(),
              entityId: entityId,
              kind: kind,
              operation: current == null
                  ? 'create'
                  : delete
                  ? 'delete'
                  : 'update',
              payload: jsonEncode(clean(payload)),
              baseVersion: current?.version ?? 0,
            ),
          );
    });
  }

  static Map<String, dynamic> clean(Map<String, dynamic> data) => Map.from(data)
    ..remove('created_at')
    ..remove('updated_at')
    ..remove('deleted_at');
  Future<String> state(String key, String fallback) async =>
      (await (db.select(
        db.syncState,
      )..where((r) => r.key.equals(key))).getSingleOrNull())?.value ??
      fallback;
  Future<void> setState(String key, String value) => db
      .into(db.syncState)
      .insertOnConflictUpdate(
        SyncStateCompanion.insert(key: key, value: value),
      );
  Future<void> canonical(Map<String, dynamic> record) => db
      .into(db.records)
      .insertOnConflictUpdate(
        RecordsCompanion.insert(
          id: record['id'],
          kind: record['entity_type'],
          payload: jsonEncode(record['payload']),
          version: Value(record['version']),
        ),
      );
  Future<void> conflict(
    String kind,
    String id,
    dynamic remote,
    String reason,
  ) async {
    final row = await get(kind, id);
    await db
        .into(db.conflicts)
        .insertOnConflictUpdate(
          ConflictsCompanion.insert(
            entityId: id,
            kind: kind,
            local: row?.payload ?? '{}',
            remote: jsonEncode(remote),
            reason: reason,
          ),
        );
  }

  Future<void> resolve(Conflict conflict, {required bool mine}) async {
    await db.transaction(() async {
      final latestConflict =
          await (db.select(db.conflicts)..where(
                (r) =>
                    r.entityId.equals(conflict.entityId) &
                    r.kind.equals(conflict.kind),
              ))
              .getSingleOrNull();
      if (latestConflict == null) return;
      final latestLocal = await get(conflict.kind, conflict.entityId);
      final remote = jsonDecode(latestConflict.remote);
      // Explicit resolution supersedes all pending edits for this entity.
      await (db.delete(db.outbox)..where(
            (r) =>
                r.entityId.equals(conflict.entityId) &
                r.kind.equals(conflict.kind),
          ))
          .go();
      if (remote != null) {
        await canonical(remote);
      } else {
        await (db.delete(db.records)..where(
              (r) =>
                  r.id.equals(conflict.entityId) & r.kind.equals(conflict.kind),
            ))
            .go();
      }
      if (mine) {
        final local =
            jsonDecode(latestLocal?.payload ?? latestConflict.local)
                as Map<String, dynamic>;
        // A deleted server record cannot be resurrected under the same identity.
        if (remote != null &&
            remote['payload']['deleted_at'] != null &&
            local['deleted_at'] == null) {
          await save(conflict.kind, clean(local));
        } else if (remote != null || local['deleted_at'] == null) {
          await save(
            conflict.kind,
            clean(local),
            id: conflict.entityId,
            delete: local['deleted_at'] != null,
          );
        }
      }
      await (db.delete(db.conflicts)..where(
            (r) =>
                r.entityId.equals(conflict.entityId) &
                r.kind.equals(conflict.kind),
          ))
          .go();
    });
  }
}
