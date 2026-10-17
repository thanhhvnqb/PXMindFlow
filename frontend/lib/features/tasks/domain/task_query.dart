import 'package:intl/intl.dart';

import 'item.dart';
import 'organization.dart';

/// A projection of canonical tasks without separate Inbox records.
class TaskQuery {
  final String view, sort;
  final String? listId;
  final int? priority;
  final String? projectId, tagId;
  final bool includeArchived;
  const TaskQuery({
    this.view = 'All',
    this.sort = 'priority',
    this.listId,
    this.priority,
    this.projectId,
    this.tagId,
    this.includeArchived = false,
  });
  List<Item> apply(Iterable<Item> items, DateTime now) {
    final organization = Organization(items);
    final today = DateFormat('yyyy-MM-dd').format(now);
    final result = items.where((i) {
      if (i.kind != 'task' || i.deleted) return false;
      if (!includeArchived && organization.archived(i)) return false;
      if (listId != null &&
          !(i.data['list_id'] == listId || organization.inSpace(i, listId!))) {
        return false;
      }
      if (projectId != null && !organization.inProject(i, projectId!)) {
        return false;
      }
      if (tagId != null && !organization.tagSources(i).containsKey(tagId)) {
        return false;
      }
      if (priority != null && (i.data['priority'] ?? 0) != priority) {
        return false;
      }
      return switch (view) {
        'Inbox' =>
          !i.completed &&
              (i.data['list_id'] == null &&
                  i.data['project_id'] == null &&
                  organization.inbox(i)),
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
