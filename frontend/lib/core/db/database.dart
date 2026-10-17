import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'web_persistence.dart';
part 'database.g.dart';

class Records extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id, kind};
}

class Outbox extends Table {
  IntColumn get position => integer().autoIncrement()();
  TextColumn get operationId => text().unique()();
  TextColumn get entityId => text()();
  TextColumn get kind => text()();
  TextColumn get operation => text()();
  TextColumn get payload => text()();
  IntColumn get baseVersion => integer()();
  BoolColumn get sent => boolean().withDefault(const Constant(false))();
}

class Conflicts extends Table {
  TextColumn get entityId => text()();
  TextColumn get kind => text()();
  TextColumn get local => text()();
  TextColumn get remote => text()();
  TextColumn get reason => text()();
  @override
  Set<Column> get primaryKey => {entityId, kind};
}

class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Records, Outbox, Conflicts, SyncState])
class AppDatabase extends _$AppDatabase {
  AppDatabase(String account, {void Function(String)? persistenceWarning})
    : super(
        driftDatabase(
          name: 'mindflow_$account',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.dart.js'),
            onResult: (result) {
              final warning = webPersistenceWarning(
                result.chosenImplementation,
              );
              if (warning != null) persistenceWarning?.call(warning);
            },
          ),
        ),
      );
  AppDatabase.testing(super.executor);
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _searchIndex();
      await _organizationIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _searchIndex();
      if (from < 3) await _organizationIndexes();
    },
  );
  Future<void> _organizationIndexes() async {
    for (final key in [
      'list_id',
      'space_id',
      'project_id',
      'parent_id',
      'archived_at',
    ]) {
      await customStatement(
        "CREATE INDEX IF NOT EXISTS records_$key ON records(kind, json_extract(payload, '\$.$key'))",
      );
    }
  }

  Future<void> _searchIndex() async {
    try {
      await customStatement(
        "CREATE VIRTUAL TABLE record_fts USING fts5(id UNINDEXED, kind UNINDEXED, title, notes)",
      );
      await customStatement(
        "INSERT INTO record_fts SELECT id, kind, json_extract(payload, '\$.title'), json_extract(payload, '\$.notes') FROM records",
      );
      await customStatement(
        "CREATE TRIGGER record_fts_insert AFTER INSERT ON records BEGIN INSERT INTO record_fts VALUES(new.id, new.kind, json_extract(new.payload, '\$.title'), json_extract(new.payload, '\$.notes')); END",
      );
      await customStatement(
        "CREATE TRIGGER record_fts_delete AFTER DELETE ON records BEGIN DELETE FROM record_fts WHERE id = old.id AND kind = old.kind; END",
      );
      await customStatement(
        "CREATE TRIGGER record_fts_update AFTER UPDATE ON records BEGIN DELETE FROM record_fts WHERE id = old.id AND kind = old.kind; INSERT INTO record_fts VALUES(new.id, new.kind, json_extract(new.payload, '\$.title'), json_extract(new.payload, '\$.notes')); END",
      );
      await into(syncState).insertOnConflictUpdate(
        SyncStateCompanion.insert(key: 'fts', value: 'true'),
      );
    } catch (_) {
      await into(syncState).insertOnConflictUpdate(
        SyncStateCompanion.insert(key: 'fts', value: 'false'),
      );
    }
  }
}
