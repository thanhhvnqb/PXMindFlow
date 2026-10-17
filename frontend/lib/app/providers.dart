import '../features/pomodoro/domain/focus_clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/tasks/data/local_repository.dart';
import '../features/tasks/domain/item.dart';
import '../core/db/database.dart';

final repositoryProvider = Provider<LocalRepository>(
  (ref) => throw StateError('Account repository required'),
  dependencies: const [],
);
final itemsProvider = StreamProvider<List<Item>>(
  (ref) => ref.watch(repositoryProvider).watch(),
  dependencies: [repositoryProvider],
);
final conflictsProvider = StreamProvider<List<Conflict>>(
  (ref) => ref.watch(repositoryProvider).watchConflicts(),
  dependencies: [repositoryProvider],
);
final pendingProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).watchPending(),
  dependencies: [repositoryProvider],
);

final searchProvider = StreamProvider.family<List<Item>, String>(
  (ref, query) => ref.watch(repositoryProvider).search(query),
  dependencies: [repositoryProvider],
);

final focusClockProvider = Provider<FocusClock>((ref) => FocusClock());
