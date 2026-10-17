import 'package:flutter/material.dart';

import '../domain/item.dart';
import 'task_controls.dart';
import 'markdown_editor.dart';
import 'organization_fields.dart';

/// Each patch is merged with the latest SQLite row by the repository.
class TaskDetails extends StatefulWidget {
  final Item item;
  final List<Item> lists;
  final bool vietnamese;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final VoidCallback onClose;
  final VoidCallback? onAddSubtask;
  final void Function(Item)? onOpenTask;
  const TaskDetails({
    super.key,
    required this.item,
    required this.lists,
    required this.vietnamese,
    required this.onSave,
    required this.onClose,
    this.onAddSubtask,
    this.onOpenTask,
  });
  @override
  State<TaskDetails> createState() => _TaskDetailsState();
}

class _TaskDetailsState extends State<TaskDetails> {
  late final title = TextEditingController(text: widget.item.title);
  late final notes = TextEditingController(text: widget.item.notes);
  Future<void> queue = Future.value();
  final failed = <String, dynamic>{};
  int pending = 0;
  String text(String en, String vi) => widget.vietnamese ? vi : en;
  void save(Map<String, dynamic> patch) {
    final write = widget.onSave;
    setState(() => pending++);
    queue = queue.then((_) async {
      final changes = {...failed, ...patch};
      try {
        await write(changes);
        failed.clear();
      } catch (_) {
        failed.addAll(changes);
      } finally {
        pending--;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant TaskDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (pending == 0 && failed.isEmpty) {
      if (title.text == oldWidget.item.title &&
          title.text != widget.item.title) {
        title.text = widget.item.title;
      }
      if (notes.text == oldWidget.item.notes &&
          notes.text != widget.item.notes) {
        notes.text = widget.item.notes;
      }
    }
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(text('Task details', 'Chi tiết công việc'))),
            IconButton(
              tooltip: text('Close', 'Đóng'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              value: widget.item.completed,
              semanticLabel: text('Completed', 'Hoàn thành'),
              onChanged: (value) => save({'completed': value}),
            ),
            TaskDateButton(
              value: widget.item.dueDate,
              dueAt: widget.item.data['due_at'] as String?,
              vietnamese: widget.vietnamese,
              onChanged: (date, at) => save({'due_date': date, 'due_at': at}),
            ),
            TaskPriorityButton(
              value: widget.item.data['priority'] as int? ?? 0,
              vietnamese: widget.vietnamese,
              onChanged: (value) => save({'priority': value}),
            ),
          ],
        ),
        const Divider(),
        TextField(
          key: const ValueKey('task-detail-title'),
          controller: title,
          maxLength: 500,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: InputDecoration(
            labelText: text('Title', 'Tiêu đề'),
            counterText: '',
            border: InputBorder.none,
            errorText: title.text.trim().isEmpty
                ? text('Add a title', 'Nhập tiêu đề')
                : null,
          ),
          onChanged: (value) {
            if (value.trim().isNotEmpty) {
              save({'title': value.trim()});
            } else {
              setState(() {});
            }
          },
        ),
        MarkdownEditor(
          key: const ValueKey('task-detail-notes'),
          controller: notes,
          vietnamese: widget.vietnamese,
          onChanged: (value) => save({'notes': value}),
        ),
        OrganizationFields(
          item: widget.item,
          all: widget.lists,
          vietnamese: widget.vietnamese,
          onChanged: save,
        ),
        if (widget.onAddSubtask != null)
          TextButton.icon(
            onPressed: widget.onAddSubtask,
            icon: const Icon(Icons.add),
            label: Text(text('Add subtask', 'Thêm công việc con')),
          ),
        ...widget.lists
            .where(
              (i) => i.kind == 'task' && i.data['parent_id'] == widget.item.id,
            )
            .map(
              (i) => ListTile(
                leading: Icon(
                  i.completed
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                ),
                title: Text(i.title),
                onTap: () => widget.onOpenTask?.call(i),
              ),
            ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(text('Urgent', 'Khẩn cấp')),
          value: widget.item.data['is_urgent'] == true,
          onChanged: (value) => save({'is_urgent': value}),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(text('Important', 'Quan trọng')),
          value: widget.item.data['is_important'] == true,
          onChanged: (value) => save({'is_important': value}),
        ),
        if (failed.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  text('Could not save changes', 'Không thể lưu thay đổi'),
                ),
              ),
              TextButton(
                onPressed: () => save({}),
                child: Text(text('Retry', 'Thử lại')),
              ),
            ],
          )
        else
          Text(
            pending > 0
                ? text('Saving locally…', 'Đang lưu trên thiết bị…')
                : text('Saved locally', 'Đã lưu trên thiết bị'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ),
  );
}
