import 'package:intl/intl.dart';
import 'item.dart';

/// A projection of canonical tasks without separate Inbox records.
class TaskQuery {
  final String view, sort;
  final String? listId;
  final int? priority;
  const TaskQuery({
    this.view = 'All',
    this.sort = 'priority',
    this.listId,
    this.priority,
  });
  List<Item> apply(Iterable<Item> items, DateTime now) {
    final today = DateFormat('yyyy-MM-dd').format(now);
    final result = items.where((i) {
      if (i.kind != 'task' || i.deleted) return false;
      if (listId != null && i.data['list_id'] != listId) return false;
      if (priority != null && (i.data['priority'] ?? 0) != priority) {
        return false;
      }
      return switch (view) {
        'Inbox' => !i.completed && i.data['list_id'] == null,
        'Today' =>
          !i.completed && i.dueDate != null && i.dueDate!.compareTo(today) <= 0,
        'Upcoming' =>
          !i.completed && i.dueDate != null && i.dueDate!.compareTo(today) > 0,
        'Completed' => i.completed,
        _ => !i.completed,
      };
    }).toList();
    result.sort((a, b) {
      final compared = switch (sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'due' => (a.dueDate ?? '9999-12-31').compareTo(
          b.dueDate ?? '9999-12-31',
        ),
        'newest' => (b.data['created_at'] as String? ?? '').compareTo(
          a.data['created_at'] as String? ?? '',
        ),
        _ => (b.data['priority'] as int? ?? 0).compareTo(
          a.data['priority'] as int? ?? 0,
        ),
      };
      return compared != 0 ? compared : a.id.compareTo(b.id);
    });
    return result;
  }
}
