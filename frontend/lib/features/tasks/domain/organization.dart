import 'item.dart';

/// Relationships are resolved from canonical records, never copied to children.
class Organization {
  final List<Item> items;
  Organization(Iterable<Item> records)
    : items = records.where((i) => !i.deleted).toList();
  Item? find(String kind, dynamic id) {
    for (final item in items) {
      if (item.kind == kind && item.id == id) return item;
    }
    return null;
  }

  List<Item> ancestors(Item item) {
    final result = <Item>[];
    final seen = <String>{'${item.kind}/${item.id}'};
    Item? current = item;
    while (current != null) {
      final data = current.data;
      final Item? parent = switch (current.kind) {
        'task' when data['parent_id'] != null => find(
          'task',
          data['parent_id'],
        ),
        'note' when data['project_id'] != null => find(
          'project',
          data['project_id'],
        ),
        'note' => find('task_list', data['list_id']),
        'task' when data['project_id'] != null => find(
          'project',
          data['project_id'],
        ),
        'task' => find('task_list', data['list_id']),
        'project' => find('task_list', data['space_id']),
        _ => null,
      };
      if (parent == null || !seen.add('${parent.kind}/${parent.id}')) break;
      result.add(parent);
      current = parent;
    }
    return result;
  }

  bool archived(Item item) =>
      [item, ...ancestors(item)].any((i) => i.data['archived_at'] != null);
  Set<String> directTags(Item item) =>
      (item.data['tag_ids'] as List? ?? []).cast<String>().toSet();
  Map<String, List<Item>> tagSources(Item item) {
    final result = <String, List<Item>>{};
    for (final source in [item, ...ancestors(item)]) {
      for (final tag in directTags(source)) {
        result.putIfAbsent(tag, () => []).add(source);
      }
    }
    return result;
  }

  bool inSpace(Item item, String id) =>
      ancestors(item).any((i) => i.kind == 'task_list' && i.id == id);
  bool inProject(Item item, String id) =>
      ancestors(item).any((i) => i.kind == 'project' && i.id == id);
  bool inbox(Item item) =>
      !ancestors(item).any((i) => i.kind == 'task_list' || i.kind == 'project');

  void validate(Item item) {
    for (final tag in directTags(item)) {
      if (find('tag', tag) == null) throw StateError('Invalid tag reference');
    }
    final references = <String, String>{
      'list_id': 'task_list',
      'space_id': 'task_list',
      'project_id': 'project',
      'parent_id': 'task',
      'habit_id': 'habit',
    };
    for (final entry in references.entries) {
      if (item.data[entry.key] != null &&
          find(entry.value, item.data[entry.key]) == null) {
        throw StateError('Invalid ${entry.key} reference');
      }
    }
    if (item.kind == 'project' && item.data['space_id'] == null) {
      throw StateError('A project requires a Space');
    }
    if (item.kind == 'note' &&
        ['list_id', 'project_id'].where((k) => item.data[k] != null).length !=
            1) {
      throw StateError('A note requires exactly one Space or project');
    }
    if (item.kind != 'task') return;
    if ([
          'list_id',
          'project_id',
          'parent_id',
        ].where((k) => item.data[k] != null).length >
        1) {
      throw StateError('Ambiguous task context');
    }
    final seen = <String>{item.id};
    var parent = item.data['parent_id'];
    while (parent != null) {
      if (!seen.add(parent as String)) throw StateError('Task cycle');
      parent = find('task', parent)?.data['parent_id'];
    }
  }
}
