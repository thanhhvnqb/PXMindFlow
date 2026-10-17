import 'package:drift_flutter/drift_flutter.dart';

/// Missing optional APIs explain fallbacks, not failure to persist data.
String? webPersistenceWarning(WasmStorageImplementation implementation) =>
    switch (implementation) {
      WasmStorageImplementation.opfsShared ||
      WasmStorageImplementation.opfsLocks ||
      WasmStorageImplementation.sharedIndexedDb => null,
      WasmStorageImplementation.unsafeIndexedDb =>
        'This browser cannot safely share local data between tabs. '
            'Keep MindFlow open in one tab and sync your changes.',
      WasmStorageImplementation.inMemory =>
        'Local storage is unavailable. Changes will be lost when you close '
            'or reload this page unless synced. Allow browser storage or use '
            'a supported browser.',
    };
