import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/core/db/web_persistence.dart';

void main() {
  test('persistent browser modes do not report storage failure', () {
    for (final mode in [
      WasmStorageImplementation.opfsShared,
      WasmStorageImplementation.opfsLocks,
      WasmStorageImplementation.sharedIndexedDb,
    ]) {
      expect(webPersistenceWarning(mode), isNull, reason: mode.name);
    }
  });
  test('unsafe IndexedDB explains the multiple tab risk', () {
    expect(
      webPersistenceWarning(WasmStorageImplementation.unsafeIndexedDb),
      contains('one tab'),
    );
  });
  test('memory fallback warns about loss on reload', () {
    expect(
      webPersistenceWarning(WasmStorageImplementation.inMemory),
      contains('lost when you close or reload'),
    );
  });
}
