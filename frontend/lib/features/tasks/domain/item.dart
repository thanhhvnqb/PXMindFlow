import 'dart:convert';

class Item {
  final String id;
  final String kind;
  final int version;
  final Map<String, dynamic> data;
  Item(this.id, this.kind, this.version, Map<String, dynamic> value)
    : data = Map.unmodifiable(value);
  String get title => data['title'] as String? ?? '';
  bool get deleted => data['deleted_at'] != null;
  bool get completed => data['completed'] == true;
  String get notes => data['notes'] as String? ?? '';
  String? get dueDate {
    final instant = DateTime.tryParse(
      data['due_at'] as String? ?? '',
    )?.toLocal();
    if (instant == null) return data['due_date'] as String?;
    return '${instant.year.toString().padLeft(4, '0')}-${instant.month.toString().padLeft(2, '0')}-${instant.day.toString().padLeft(2, '0')}';
  }

  String encode() => jsonEncode(data);
}
