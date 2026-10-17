import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../app/providers.dart';
import '../features/tasks/domain/item.dart';
import '../features/tasks/domain/organization.dart';
import '../features/tasks/presentation/organization_fields.dart';
import '../features/tasks/presentation/task_controls.dart';
import '../features/tasks/presentation/task_details.dart';
import '../features/tasks/presentation/markdown_editor.dart';
import '../features/tasks/domain/task_query.dart';
import '../features/tasks/data/local_repository.dart';

class MindFlowShell extends ConsumerStatefulWidget {
  final String view, status;
  final String? warning;
  final VoidCallback sync, toggleTheme, toggleLanguage;
  final Future<void> Function() logout;
  final bool vietnamese;
  const MindFlowShell({
    super.key,
    required this.view,
    required this.status,
    this.warning,
    required this.sync,
    required this.logout,
    required this.toggleTheme,
    required this.toggleLanguage,
    required this.vietnamese,
  });
  @override
  ConsumerState<MindFlowShell> createState() => _MindFlowShellState();
}

class _MindFlowShellState extends ConsumerState<MindFlowShell> {
  static const routes = [
    'tasks',
    'matrix',
    'habits',
    'calendar',
    'focus',
    'search',
  ];
  static const icons = [
    Icons.check_circle_outline,
    Icons.grid_view_outlined,
    Icons.eco_outlined,
    Icons.calendar_month_outlined,
    Icons.timelapse_outlined,
    Icons.search,
  ];
  String? activeTaskId;
  bool inlineDetails = false;
  String filter = 'All';
  String search = '';
  String taskSort = 'priority';
  int? priorityFilter;
  bool selecting = false;
  final selectedTasks = <String>{};
  String? listId;
  String? projectId, tagId;
  bool includeArchived = false;
  bool showArchivedTags = false;
  DateTime date = DateTime.now();
  Timer? ticker;
  bool finishing = false;
  int focusMinutes = 25;
  String focusKind = 'focus';
  String label(String en, String vi) => widget.vietnamese ? vi : en;
  List<String> get names => widget.vietnamese
      ? ['Công việc', 'Ma trận', 'Thói quen', 'Lịch', 'Tập trung', 'Tìm kiếm']
      : ['Tasks', 'Matrix', 'Habits', 'Calendar', 'Focus', 'Search'];
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.view == 'focus') {
        setState(() {});
        final all = ref.read(itemsProvider).asData?.value ?? <Item>[];
        final active = all
            .where(
              (i) => i.kind == 'focus_session' && i.data['state'] == 'running',
            )
            .firstOrNull;
        if (active != null &&
            !finishing &&
            elapsed(active) >= active.data['duration_seconds']) {
          finishing = true;
          perform(
            () => repo.save('focus_session', {
              ...LocalRepository.clean(active.data),
              'elapsed_seconds': active.data['duration_seconds'],
              'state': 'finished',
              'anchor': null,
            }, id: active.id),
          ).whenComplete(() => finishing = false);
        }
      }
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  LocalRepository get repo => ref.read(repositoryProvider);
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              label(
                'Could not save. Your existing data is retained.',
                'Không thể lưu. Dữ liệu hiện tại vẫn được giữ.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<T?> managedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) async {
    final route = DialogRoute<T>(context: context, builder: builder);
    final result = await Navigator.of(context).push(route);
    await route.completed;
    return result;
  }

  Future<bool> editor({
    Item? item,
    String kind = 'task',
    String initialTitle = '',
    String? parentTaskId,
    String? initialDue,
    String? initialDueAt,
    int initialPriority = 0,
  }) async {
    final title = TextEditingController(text: item?.title ?? initialTitle);
    final notes = TextEditingController(text: item?.notes ?? '');
    var urgent = item?.data['is_urgent'] == true;
    var important = item?.data['is_important'] == true;
    var due = item?.dueDate ?? initialDue;
    var dueAt = item?.data['due_at'] as String? ?? initialDueAt;
    var priority = item?.data['priority'] as int? ?? initialPriority;
    final organizationDraft = <String, dynamic>{...?item?.data};
    if (item == null && kind == 'project' && listId != null) {
      organizationDraft['space_id'] = listId;
    }
    if (item == null && (kind == 'task' || kind == 'note')) {
      organizationDraft.addAll({
        'list_id': projectId == null ? listId : null,
        'project_id': projectId,
      });
    }
    if (parentTaskId != null) {
      organizationDraft.addAll({
        'parent_id': parentTaskId,
        'list_id': null,
        'project_id': null,
      });
    }
    final all = ref.read(itemsProvider).asData?.value ?? <Item>[];
    final form = GlobalKey<FormState>();
    var saved = false;
    var saving = false;
    await managedDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            item == null
                ? label(
                    'Create ${(kind == 'task_list' ? 'Space' : kind.replaceAll('_', ' '))}',
                    'Tạo mới',
                  )
                : label('Edit', 'Chỉnh sửa'),
          ),
          content: SizedBox(
            width: 460,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kind == 'task') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TaskDateButton(
                              value: due,
                              vietnamese: widget.vietnamese,
                              dueAt: dueAt,
                              onChanged: (value, at) => update(() {
                                due = value;
                                dueAt = at;
                              }),
                            ),
                          ),
                          TaskPriorityButton(
                            value: priority,
                            vietnamese: widget.vietnamese,
                            onChanged: (value) =>
                                update(() => priority = value),
                          ),
                        ],
                      ),
                    ],
                    TextFormField(
                      controller: title,
                      autofocus: true,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: label('Title', 'Tiêu đề'),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? label('Add a title', 'Nhập tiêu đề')
                          : null,
                    ),
                    if (kind == 'task' || kind == 'note')
                      MarkdownEditor(
                        controller: notes,
                        vietnamese: widget.vietnamese,
                      ),
                    if (kind == 'task') ...[
                      SwitchListTile(
                        title: Text(label('Urgent', 'Khẩn cấp')),
                        value: urgent,
                        onChanged: (v) => update(() => urgent = v),
                      ),
                      SwitchListTile(
                        title: Text(label('Important', 'Quan trọng')),
                        value: important,
                        onChanged: (v) => update(() => important = v),
                      ),
                    ],
                    if (['task', 'task_list', 'project', 'tag'].contains(kind))
                      OrganizationFields(
                        item: Item(
                          item?.id ?? '',
                          kind,
                          item?.version ?? 0,
                          organizationDraft,
                        ),
                        all: all,
                        vietnamese: widget.vietnamese,
                        onChanged: (patch) =>
                            update(() => organizationDraft.addAll(patch)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(label('Cancel', 'Hủy')),
            ),
            FilledButton(
              onPressed: () async {
                if (saving || !form.currentState!.validate()) return;
                update(() => saving = true);
                try {
                  await repo.save(kind, {
                    ...LocalRepository.clean(organizationDraft),
                    'title': title.text.trim(),
                    if (kind == 'task' || kind == 'note') 'notes': notes.text,
                    if (kind == 'task') ...{
                      'priority': priority,
                      'due_date': due,
                      'due_at': dueAt,
                      'completed': item?.completed ?? false,
                      'is_urgent': urgent,
                      'is_important': important,
                    },
                    if (kind == 'habit') ...{
                      'timezone': 'Etc/UTC',
                      'target': 1,
                    },
                  }, id: item?.id);
                  saved = true;
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          label(
                            'Could not save. Try again.',
                            'Không thể lưu. Hãy thử lại.',
                          ),
                        ),
                      ),
                    );
                  }
                  if (context.mounted) update(() => saving = false);
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(label('Save', 'Lưu')),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    notes.dispose();
    return saved;
  }

  Future<void> deleteNote(Item note) async {
    final confirmed = await managedDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label('Delete note?', 'Xóa ghi chú?')),
        content: Text(note.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(label('Cancel', 'Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label('Delete', 'Xóa')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await repo.save(
          'note',
          LocalRepository.clean(note.data),
          id: note.id,
          delete: true,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                label(
                  'Could not delete. Try again.',
                  'Không thể xóa. Hãy thử lại.',
                ),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> archive(Item item) => repo.save(item.kind, {
    ...LocalRepository.clean(item.data),
    'archived_at': item.data['archived_at'] == null
        ? DateTime.now().toUtc().toIso8601String()
        : null,
  }, id: item.id);

  Future<void> addSubtask(Item parent) async {
    await editor(kind: 'task', parentTaskId: parent.id);
  }

  Future<void> openTaskDetails(Item item) => managedDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: SizedBox(
        width: 500,
        child: Consumer(
          builder: (context, ref, _) {
            final all = ref.watch(itemsProvider).asData?.value ?? <Item>[];
            final current =
                all
                    .where((i) => i.kind == 'task' && i.id == item.id)
                    .firstOrNull ??
                item;
            return TaskDetails(
              key: ValueKey(item.id),
              item: current,
              lists: all,
              onOpenTask: openTaskDetails,
              onAddSubtask: () => addSubtask(item),
              vietnamese: widget.vietnamese,
              onSave: (patch) => repo.updateTasks([item.id], patch),
              onClose: () => Navigator.pop(dialogContext),
            );
          },
        ),
      ),
    ),
  );

  Future<void> remove(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label('Delete “${item.title}”?', 'Xóa “${item.title}”?')),
        content: Text(
          label(
            'This deletion includes subtasks and will sync to your devices.',
            'Thao tác xóa gồm công việc con và sẽ đồng bộ với các thiết bị.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(label('Cancel', 'Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label('Delete', 'Xóa')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await perform(
        () => item.kind == 'task'
            ? repo.updateTasks([item.id], {}, delete: true)
            : repo.save(
                item.kind,
                LocalRepository.clean(item.data),
                id: item.id,
                delete: true,
              ),
      );
    }
  }

  Future<void> bulkDelete(List<Item> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          label(
            'Delete ${items.length} tasks?',
            'Xóa ${items.length} công việc?',
          ),
        ),
        content: Text(
          label(
            'This deletion includes subtasks and will sync to your devices.',
            'Thao tác xóa gồm công việc con và sẽ đồng bộ với các thiết bị.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(label('Cancel', 'Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label('Delete', 'Xóa')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await perform(() async {
        await repo.updateTasks(items.map((i) => i.id), {}, delete: true);
        if (mounted) setState(selectedTasks.clear);
      });
    }
  }

  Widget taskTile(Item item, {bool selectable = false}) => Card(
    margin: EdgeInsets.only(
      bottom: 1,
      left:
          Organization(ref.read(itemsProvider).asData?.value ?? <Item>[])
              .ancestors(item)
              .where((i) => i.kind == 'task')
              .length
              .clamp(0, 3) *
          12.0,
    ),
    elevation: 0,
    child: ListTile(
      dense: true,
      selected: widget.view == 'tasks' && activeTaskId == item.id,
      leading: Checkbox(
        value: selectable ? selectedTasks.contains(item.id) : item.completed,
        onChanged: (value) => selectable
            ? setState(() {
                if (value == true) {
                  selectedTasks.add(item.id);
                } else {
                  selectedTasks.remove(item.id);
                }
              })
            : perform(
                () => repo.save('task', {
                  ...LocalRepository.clean(item.data),
                  'completed': value,
                }, id: item.id),
              ),
      ),
      title: Text(
        item.title,
        style: TextStyle(
          decoration: item.completed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle:
          item.dueDate != null ||
              item.notes.isNotEmpty ||
              (item.data['tag_ids'] as List? ?? []).isNotEmpty
          ? Text(
              [
                if (item.dueDate != null)
                  item.dueDate! +
                      (item.data['due_at'] == null
                          ? ''
                          : ', ${DateFormat('HH:mm').format(DateTime.parse(item.data['due_at'] as String).toLocal())}'),
                if (item.notes.isNotEmpty)
                  MarkdownProjection(
                    item.notes,
                    Theme.of(context).textTheme,
                  ).text,
                ...(item.data['tag_ids'] as List? ?? []).map(
                  (id) =>
                      '#${(ref.read(itemsProvider).asData?.value ?? <Item>[]).where((i) => i.kind == 'tag' && i.id == id).firstOrNull?.title ?? id}',
                ),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => inlineDetails && widget.view == 'tasks'
          ? setState(() => activeTaskId = item.id)
          : openTaskDetails(item),
      trailing: PopupMenuButton<String>(
        tooltip: label('Task actions', 'Thao tác'),
        onSelected: (_) => remove(item),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'delete', child: Text(label('Delete', 'Xóa'))),
        ],
      ),
    ),
  );
  Widget empty(String text, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
  Widget taskOrganization(List<Item> all) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          label('My tasks', 'Công việc của tôi'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      ...['All', 'Inbox', 'Today', 'Upcoming', 'Completed'].map(
        (view) => ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          selected: filter == view && listId == null,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          leading: Icon(
            const {
              'All': Icons.layers_outlined,
              'Inbox': Icons.inbox_outlined,
              'Today': Icons.today_outlined,
              'Upcoming': Icons.date_range_outlined,
              'Completed': Icons.task_alt,
            }[view],
          ),
          title: Text(
            label(
              view,
              const {
                'All': 'Tất cả',
                'Inbox': 'Hộp thư',
                'Today': 'Hôm nay',
                'Upcoming': 'Sắp tới',
                'Completed': 'Hoàn thành',
              }[view]!,
            ),
          ),
          onTap: () => setState(() {
            filter = view;
            listId = null;
            projectId = null;
          }),
        ),
      ),
      const Divider(height: 32),
      ListTile(
        dense: true,
        title: Text(label('All Spaces', 'Mọi không gian')),
        selected: listId == null,
        onTap: () => setState(() {
          listId = null;
          projectId = null;
        }),
      ),
      ...all
          .where(
            (i) =>
                i.kind == 'task_list' &&
                (includeArchived || !Organization(all).archived(i)),
          )
          .map(
            (i) => ListTile(
              dense: true,
              leading: const Icon(Icons.list_alt_outlined),
              title: Text(
                i.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: listId == i.id,
              onTap: () => setState(() {
                listId = i.id;
                projectId = null;
                filter = 'All';
              }),
              trailing: PopupMenuButton<String>(
                tooltip: label('Space actions', 'Thao tác không gian'),
                onSelected: (value) => value == 'edit'
                    ? editor(item: i, kind: 'task_list')
                    : perform(() => archive(i)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(label('Edit', 'Chỉnh sửa')),
                  ),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(
                      i.data['archived_at'] == null
                          ? label('Archive', 'Lưu trữ')
                          : label('Restore', 'Khôi phục'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(label('New Space', 'Không gian mới')),
        onTap: () => editor(kind: 'task_list'),
      ),
      SwitchListTile(
        title: Text(label('Include archived', 'Hiện mục lưu trữ')),
        value: includeArchived,
        onChanged: (v) => setState(() => includeArchived = v),
      ),
      ...all
          .where(
            (i) =>
                i.kind == 'project' &&
                (listId == null || i.data['space_id'] == listId) &&
                (includeArchived || !Organization(all).archived(i)),
          )
          .map(
            (i) => ListTile(
              leading: const Icon(Icons.work_outline),
              title: Text(i.title),
              subtitle: Text(i.data['status'] as String? ?? 'active'),
              selected: projectId == i.id,
              onTap: () => setState(() {
                projectId = i.id;
                listId = null;
                filter = 'All';
              }),
              trailing: IconButton(
                icon: const Icon(Icons.more_horiz),
                tooltip: label('Project details', 'Chi tiết dự án'),
                onPressed: () => editor(item: i, kind: 'project'),
              ),
            ),
          ),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(label('New Project', 'Dự án mới')),
        onTap: () => editor(kind: 'project'),
      ),
      const Divider(),
      SwitchListTile(
        title: Text(label('Show archived tags', 'Hiện nhãn lưu trữ')),
        value: showArchivedTags,
        onChanged: (v) => setState(() {
          showArchivedTags = v;
          tagId = null;
        }),
      ),
      ListTile(
        title: Text(label('All tags', 'Mọi nhãn')),
        selected: tagId == null,
        onTap: () => setState(() => tagId = null),
      ),
      ...all
          .where(
            (i) =>
                i.kind == 'tag' &&
                (showArchivedTags || i.data['archived_at'] == null),
          )
          .map(
            (i) => ListTile(
              leading: const Icon(Icons.tag),
              title: Text(i.title),
              selected: tagId == i.id,
              onTap: () => setState(() => tagId = i.id),
              trailing: IconButton(
                icon: const Icon(Icons.more_horiz),
                tooltip: label('Tag details', 'Chi tiết nhãn'),
                onPressed: () => editor(item: i, kind: 'tag'),
              ),
            ),
          ),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(label('New Tag', 'Nhãn mới')),
        onTap: () => editor(kind: 'tag'),
      ),
    ],
  );

  Widget taskWorkspace(List<Item> all) => LayoutBuilder(
    builder: (context, box) {
      final showLists = box.maxWidth >= 850;
      inlineDetails = box.maxWidth >= 1100;
      final active = all
          .where((i) => i.id == activeTaskId && !i.deleted)
          .firstOrNull;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLists) ...[
            SizedBox(width: 230, child: taskOrganization(all)),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (!showLists)
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: label(
                              'Spaces and filters',
                              'Không gian và bộ lọc',
                            ),
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          label(
                            filter,
                            const {
                              'All': 'Tất cả',
                              'Inbox': 'Hộp thư',
                              'Today': 'Hôm nay',
                              'Upcoming': 'Sắp tới',
                              'Completed': 'Hoàn thành',
                            }[filter]!,
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  QuickTaskEntry(
                    vietnamese: widget.vietnamese,
                    onDetails: (title, due, priority, dueAt) => editor(
                      initialDueAt: dueAt,
                      initialTitle: title,
                      initialDue: due,
                      initialPriority: priority,
                    ),
                    onSave: (title, due, priority, dueAt) async {
                      await repo.save('task', {
                        'title': title,
                        'notes': '',
                        'priority': priority,
                        'list_id': projectId == null ? listId : null,
                        'project_id': projectId,
                        'due_date': due,
                        'due_at': dueAt,
                        'completed': false,
                        'is_urgent': false,
                        'is_important': false,
                      });
                    },
                  ),
                  if (listId != null || projectId != null) ...[
                    Row(
                      children: [
                        Expanded(child: Text(label('Notes', 'Ghi chú'))),
                        TextButton.icon(
                          onPressed: () => editor(kind: 'note'),
                          icon: const Icon(Icons.note_add_outlined),
                          label: Text(label('Add note', 'Thêm ghi chú')),
                        ),
                      ],
                    ),
                    for (final note in all.where(
                      (i) =>
                          i.kind == 'note' &&
                          (includeArchived || !Organization(all).archived(i)) &&
                          (projectId != null
                              ? i.data['project_id'] == projectId
                              : i.data['list_id'] == listId),
                    ))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(note.title),
                          subtitle: Text(
                            MarkdownProjection(
                              note.notes,
                              Theme.of(context).textTheme,
                            ).text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => editor(item: note, kind: 'note'),
                          trailing: IconButton(
                            tooltip: label('Delete note', 'Xóa ghi chú'),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteNote(note),
                          ),
                        ),
                      ),
                  ],
                  tasks(all),
                ],
              ),
            ),
          ),
          if (inlineDetails) ...[
            const VerticalDivider(width: 1),
            SizedBox(
              width: 330,
              child: active == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          label(
                            'Select a task to see its details',
                            'Chọn công việc để xem chi tiết',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : TaskDetails(
                      key: ValueKey(active.id),
                      item: active,
                      lists: all,
                      onOpenTask: openTaskDetails,
                      onAddSubtask: () => addSubtask(active),
                      vietnamese: widget.vietnamese,
                      onSave: (patch) => repo.updateTasks([active.id], patch),
                      onClose: () => setState(() => activeTaskId = null),
                    ),
            ),
          ],
        ],
      );
    },
  );

  Widget accountMenu() => PopupMenuButton<String>(
    tooltip: label('Account and settings', 'Tài khoản và cài đặt'),
    icon: const CircleAvatar(
      radius: 16,
      child: Icon(Icons.person_outline, size: 20),
    ),
    onSelected: (value) {
      if (value == 'theme') {
        widget.toggleTheme();
      } else if (value == 'language') {
        widget.toggleLanguage();
      } else {
        logout();
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'theme', child: Text(label('Theme', 'Giao diện'))),
      const PopupMenuItem(
        value: 'language',
        child: Text('English / Tiếng Việt'),
      ),
      PopupMenuItem(
        value: 'logout',
        child: Text(label('Sign out', 'Đăng xuất')),
      ),
    ],
  );

  Widget utilities(bool attention, int pending) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Sync: ${widget.status} · $pending pending',
        onPressed: attention ? showConflicts : widget.sync,
        icon: Icon(attention ? Icons.warning_amber : Icons.sync),
      ),
      accountMenu(),
    ],
  );

  Widget tasks(List<Item> all) {
    final tasks = TaskQuery(
      view: filter,
      listId: listId,
      projectId: projectId,
      tagId: tagId,
      includeArchived: includeArchived,
      priority: priorityFilter,
      sort: taskSort,
    ).apply(all, DateTime.now());
    final visibleSelected = tasks
        .where((i) => selectedTasks.contains(i.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: taskSort,
              hint: Text(label('Sort by', 'Sắp xếp')),
              items: [
                DropdownMenuItem(
                  value: 'priority',
                  child: Text(label('Priority', 'Ưu tiên')),
                ),
                DropdownMenuItem(
                  value: 'due',
                  child: Text(label('Due date', 'Ngày đến hạn')),
                ),
                DropdownMenuItem(
                  value: 'title',
                  child: Text(label('Title', 'Tiêu đề')),
                ),
                DropdownMenuItem(
                  value: 'newest',
                  child: Text(label('Newest first', 'Mới nhất')),
                ),
              ],
              onChanged: (value) => setState(() => taskSort = value!),
            ),
            DropdownButton<int>(
              value: priorityFilter ?? -1,
              items: [
                DropdownMenuItem(
                  value: -1,
                  child: Text(label('Any priority', 'Mọi mức ưu tiên')),
                ),
                ...List.generate(
                  4,
                  (p) => DropdownMenuItem(
                    value: p,
                    child: Text(
                      label(
                        ['No priority', 'Low', 'Medium', 'High'][p],
                        ['Không ưu tiên', 'Thấp', 'Trung bình', 'Cao'][p],
                      ),
                    ),
                  ),
                ),
              ],
              onChanged: (value) =>
                  setState(() => priorityFilter = value == -1 ? null : value),
            ),
            FilterChip(
              label: Text(label('Select tasks', 'Chọn công việc')),
              selected: selecting,
              onSelected: (value) => setState(() {
                selecting = value;
                selectedTasks.clear();
              }),
            ),
            Text(label('${tasks.length} tasks', '${tasks.length} công việc')),
          ],
        ),
        if (selecting)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  if (visibleSelected.length == tasks.length) {
                    selectedTasks.removeAll(tasks.map((i) => i.id));
                  } else {
                    selectedTasks.addAll(tasks.map((i) => i.id));
                  }
                }),
                child: Text(label('Select all', 'Chọn tất cả')),
              ),
              TextButton(
                onPressed: visibleSelected.isEmpty
                    ? null
                    : () => perform(() async {
                        await repo.updateTasks(
                          visibleSelected.map((i) => i.id),
                          {'completed': filter != 'Completed'},
                        );
                        if (mounted) setState(selectedTasks.clear);
                      }),
                child: Text(
                  filter == 'Completed'
                      ? label('Reopen selected', 'Mở lại đã chọn')
                      : label('Complete selected', 'Hoàn thành đã chọn'),
                ),
              ),
              TextButton(
                onPressed: visibleSelected.isEmpty
                    ? null
                    : () => bulkDelete(visibleSelected),
                child: Text(label('Delete selected', 'Xóa đã chọn')),
              ),
            ],
          ),
        const SizedBox(height: 24),
        if (tasks.isEmpty)
          empty(
            label(
              'A little space to breathe.\nAdd your next step when you’re ready.',
              'Thêm công việc tiếp theo khi bạn sẵn sàng.',
            ),
            Icons.check_circle_outline,
          ),
        ...tasks.map((item) => taskTile(item, selectable: selecting)),
      ],
    );
  }

  Widget matrix(List<Item> all) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth > 640;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: List.generate(4, (q) {
          final urgent = q < 2;
          final important = q % 2 == 0;
          final tasks = all
              .where(
                (i) =>
                    i.kind == 'task' &&
                    !Organization(all).archived(i) &&
                    !i.completed &&
                    (i.data['is_urgent'] == true) == urgent &&
                    (i.data['is_important'] == true) == important,
              )
              .toList();
          return SizedBox(
            width: wide ? (box.maxWidth - 16) / 2 : box.maxWidth,
            child: DragTarget<Item>(
              onAcceptWithDetails: (details) => perform(
                () => repo.save('task', {
                  ...LocalRepository.clean(details.data.data),
                  'is_urgent': urgent,
                  'is_important': important,
                }, id: details.data.id),
              ),
              builder: (context, candidates, rejected) => Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer
                      .withValues(alpha: candidates.isEmpty ? .6 : 1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ['Do now', 'Delegate', 'Schedule', 'Let go'][q],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${urgent ? 'Urgent' : 'Not urgent'} · ${important ? 'Important' : 'Not important'}',
                    ),
                    const SizedBox(height: 16),
                    if (tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Drop a task here'),
                      ),
                    ...tasks.map(
                      (i) => LongPressDraggable<Item>(
                        data: i,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 260,
                            child: ListTile(title: Text(i.title)),
                          ),
                        ),
                        child: taskTile(i),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      );
    },
  );
  Widget habits(List<Item> all) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now().toUtc());
    final habits = all.where((i) => i.kind == 'habit').toList();
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => editor(kind: 'habit'),
            icon: const Icon(Icons.add),
            label: Text(label('New habit', 'Thói quen mới')),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Daily check-ins currently use UTC calendar days.'),
        if (habits.isEmpty)
          empty(
            label('Small steps, repeated.', 'Từng bước nhỏ mỗi ngày.'),
            Icons.eco_outlined,
          ),
        ...habits.map((habit) {
          final checks = all
              .where(
                (i) =>
                    i.kind == 'habit_checkin' &&
                    i.data['habit_id'] == habit.id &&
                    i.data['local_date'] == today,
              )
              .toList();
          return Card(
            elevation: 0,
            child: ListTile(
              title: Text(habit.title),
              subtitle: Text(
                '${all.where((i) => i.kind == 'habit_checkin' && i.data['habit_id'] == habit.id).length} check-ins',
              ),
              onTap: () => editor(item: habit, kind: 'habit'),
              leading: IconButton(
                tooltip: 'Check in today (UTC)',
                icon: Icon(
                  checks.isEmpty
                      ? Icons.radio_button_unchecked
                      : Icons.check_circle,
                ),
                onPressed: () => perform(() async {
                  if (checks.isEmpty) {
                    await repo.save('habit_checkin', {
                      'habit_id': habit.id,
                      'local_date': today,
                      'timezone': 'Etc/UTC',
                      'count': 1,
                    });
                  }
                }),
              ),
              trailing: IconButton(
                tooltip: 'Delete habit',
                onPressed: () => remove(habit),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget calendar(List<Item> all) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final tasks = all
        .where(
          (i) =>
              i.kind == 'task' &&
              !Organization(all).archived(i) &&
              i.dueDate == key,
        )
        .toList();
    return Column(
      children: [
        CalendarDatePicker(
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
          onDateChanged: (v) => setState(() => date = v),
        ),
        const SizedBox(height: 16),
        Text(
          DateFormat.yMMMMd().format(date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (tasks.isEmpty)
          empty(
            label(
              'No tasks scheduled for this day.',
              'Không có công việc cho ngày này.',
            ),
            Icons.event_available,
          ),
        ...tasks.map((item) => taskTile(item, selectable: selecting)),
      ],
    );
  }

  int elapsed(Item session) => ref.read(focusClockProvider).elapsed(session);
  Widget focus(List<Item> all) {
    final sessions = all.where((i) => i.kind == 'focus_session').toList()
      ..sort(
        (a, b) => (b.data['started_at'] as String).compareTo(
          a.data['started_at'] as String,
        ),
      );
    final active = sessions
        .where((i) => i.data['state'] != 'finished')
        .firstOrNull;
    final remaining = active == null
        ? focusMinutes * 60
        : ((active.data['duration_seconds'] as int) - elapsed(active)).clamp(
            0,
            86400,
          );
    return Column(
      children: [
        const SizedBox(height: 32),
        const Icon(Icons.spa_outlined, size: 56),
        const SizedBox(height: 24),
        Text(
          '${(remaining ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}',
          style: Theme.of(context).textTheme.displayLarge
              ?.copyWith(fontWeight: FontWeight.w300, fontSize: 80),
        ),
        const SizedBox(height: 16),
        Text(
          label('One thing at a time.', 'Tập trung vào một việc.'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        if (active == null)
          Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: focusKind,
                items: const [
                  DropdownMenuItem(value: 'focus', child: Text('Focus')),
                  DropdownMenuItem(
                    value: 'short_break',
                    child: Text('Short break'),
                  ),
                  DropdownMenuItem(
                    value: 'long_break',
                    child: Text('Long break'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  focusKind = value ?? 'focus';
                  focusMinutes = focusKind == 'short_break'
                      ? 5
                      : focusKind == 'long_break'
                      ? 15
                      : 25;
                }),
              ),
              DropdownButton<int>(
                value: focusMinutes,
                items: [5, 15, 25, 45, 60]
                    .map(
                      (m) =>
                          DropdownMenuItem(value: m, child: Text('$m minutes')),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => focusMinutes = value ?? 25),
              ),
            ],
          ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              icon: Icon(
                active?.data['state'] == 'running'
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                active == null
                    ? 'Start $focusMinutes minutes'
                    : active.data['state'] == 'running'
                    ? 'Pause'
                    : 'Resume',
              ),
              onPressed: () => perform(() async {
                final now = DateTime.now().toUtc().toIso8601String();
                await repo.save(
                  'focus_session',
                  active == null
                      ? {
                          'title': 'Focus',
                          'started_at': now,
                          'duration_seconds': focusMinutes * 60,
                          'elapsed_seconds': 0,
                          'state': 'running',
                          'anchor': now,
                          'kind': focusKind,
                        }
                      : {
                          ...LocalRepository.clean(active.data),
                          'elapsed_seconds': elapsed(active),
                          'state': active.data['state'] == 'running'
                              ? 'paused'
                              : 'running',
                          'anchor': now,
                        },
                  id: active?.id,
                );
              }),
            ),
            if (active != null)
              OutlinedButton(
                onPressed: () => perform(
                  () => repo.save('focus_session', {
                    ...LocalRepository.clean(active.data),
                    'elapsed_seconds': elapsed(active)
                        .clamp(0, active.data['duration_seconds']),
                    'state': 'finished',
                    'anchor': null,
                  }, id: active.id),
                ),
                child: const Text('Finish'),
              ),
          ],
        ),
        const SizedBox(height: 40),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Session history',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ...sessions
            .where((i) => i.data['state'] == 'finished')
            .map(
              (i) => ListTile(
                leading: const Icon(Icons.timelapse),
                title: Text(
                  '${(i.data['elapsed_seconds'] as int) ~/ 60} minutes',
                ),
                subtitle: Text(
                  DateFormat.yMMMd().add_Hm().format(
                    DateTime.parse(i.data['started_at']).toLocal(),
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget searchPage(List<Item> all) {
    final resultState = ref.watch(searchProvider(search));
    final organization = Organization(all);
    final results = (resultState.asData?.value ?? <Item>[])
        .where(
          (i) =>
              (includeArchived ||
                  (i.kind == 'tag' && showArchivedTags) ||
                  !organization.archived(i)) &&
              (i.kind != 'tag' ||
                  showArchivedTags ||
                  i.data['archived_at'] == null) &&
              (tagId == null || organization.tagSources(i).containsKey(tagId)),
        )
        .toList();
    return Column(
      children: [
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: label(
              'Search tasks, Spaces, projects, tags and habits',
              'Tìm công việc, danh sách và thói quen',
            ),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: Text(label('Include archived', 'Hiện mục lưu trữ')),
              selected: includeArchived,
              onSelected: (v) => setState(() => includeArchived = v),
            ),
            FilterChip(
              label: Text(label('Archived tags', 'Nhãn lưu trữ')),
              selected: showArchivedTags,
              onSelected: (v) => setState(() {
                showArchivedTags = v;
                tagId = null;
              }),
            ),
            DropdownButton<String>(
              value: all.any((i) => i.kind == 'tag' && i.id == tagId)
                  ? tagId
                  : null,
              hint: Text(label('Filter by tag', 'Lọc theo nhãn')),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(label('All tags', 'Mọi nhãn')),
                ),
                ...all
                    .where(
                      (i) =>
                          i.kind == 'tag' &&
                          (showArchivedTags ||
                              i.data['archived_at'] == null ||
                              i.id == tagId),
                    )
                    .map(
                      (i) => DropdownMenuItem(
                        value: i.id,
                        child: Text('#${i.title}'),
                      ),
                    ),
              ],
              onChanged: (v) => setState(() => tagId = v),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (results.isEmpty)
          empty(
            label('No matches. Try another word.', 'Không tìm thấy kết quả.'),
            Icons.search_off,
          ),
        ...results.map(
          (i) => i.kind == 'task'
              ? taskTile(i)
              : Card(
                  child: ListTile(
                    title: Text(i.title),
                    subtitle: Text(
                      i.kind == 'task_list'
                          ? label('Space', 'Không gian')
                          : i.kind == 'project'
                          ? label('Project', 'Dự án')
                          : i.kind == 'tag'
                          ? label('Tag', 'Nhãn')
                          : i.kind,
                    ),
                    onTap: () => editor(item: i, kind: i.kind),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> showConflicts() async {
    final conflicts = ref.read(conflictsProvider).asData?.value ?? [];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync needs your attention'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: conflicts
                  .map(
                    (conflict) => Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            jsonDecode(conflict.local)['title'] ??
                                conflict.kind,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(conflict.reason),
                          if (LocalRepository.isValidationFailure(conflict))
                            Text(
                              label(
                                'The API rejected these changes. Your local data is safe. For invalid_payload, update the API to match this app, then retry. Other validation errors may require editing the record.',
                                'API từ chối thay đổi. Dữ liệu cục bộ vẫn được giữ. Với invalid_payload, cập nhật API rồi thử lại. Lỗi kiểm tra khác có thể cần chỉnh sửa bản ghi.',
                              ),
                            ),
                          ExpansionTile(
                            title: const Text('Review differences'),
                            children: [
                              SelectableText(
                                'Mine:\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(conflict.local))}\n\nServer:\n${const JsonEncoder.withIndent('  ').convert(jsonDecode(conflict.remote))}',
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  await perform(
                                    () => repo.resolve(conflict, mine: true),
                                  );
                                  if (context.mounted) Navigator.pop(context);
                                  widget.sync();
                                },
                                child: Text(
                                  LocalRepository.isValidationFailure(conflict)
                                      ? label(
                                          'Retry my changes',
                                          'Thử lại thay đổi',
                                        )
                                      : label('Keep mine', 'Giữ của tôi'),
                                ),
                              ),
                              if (!LocalRepository.isValidationFailure(
                                    conflict,
                                  ) ||
                                  jsonDecode(conflict.remote) != null)
                                TextButton(
                                  onPressed: () async {
                                    await perform(
                                      () => repo.resolve(conflict, mine: false),
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                    widget.sync();
                                  },
                                  child: const Text('Keep server'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> logout() async {
    final pending = ref.read(pendingProvider).asData?.value ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          '$pending pending operations. Your local data and unsynced changes will be retained for this account.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
              widget.sync();
            },
            child: const Text('Sync first'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out and retain'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.logout();
  }

  @override
  Widget build(BuildContext context) {
    final index = routes.indexOf(widget.view).clamp(0, 5);
    final pending = ref.watch(pendingProvider).asData?.value ?? 0;
    final attention =
        ref.watch(conflictsProvider).asData?.value.isNotEmpty ?? false;
    final items = ref.watch(itemsProvider);
    final mobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final wide = !mobile;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            editor(),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
            editor(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            context.go('/search'),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            context.go('/search'),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          drawer: Drawer(
            child: SafeArea(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.spa_outlined),
                    title: Text('MindFlow'),
                  ),
                  Expanded(child: taskOrganization(items.asData?.value ?? [])),
                  if (mobile) ...[
                    Wrap(
                      children: List.generate(
                        6,
                        (i) => IconButton(
                          tooltip: names[i],
                          icon: Icon(icons[i]),
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.go('/${routes[i]}');
                          },
                        ),
                      ),
                    ),
                    utilities(attention, pending),
                  ],
                ],
              ),
            ),
          ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 64,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          const Tooltip(
                            message: 'MindFlow',
                            child: Icon(Icons.spa_outlined),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: List.generate(
                                  6,
                                  (i) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: IconButton(
                                      tooltip: names[i],
                                      isSelected: index == i,
                                      style: IconButton.styleFrom(
                                        backgroundColor: index == i
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .secondaryContainer
                                            : null,
                                      ),
                                      onPressed: () =>
                                          context.go('/${routes[i]}'),
                                      icon: Icon(icons[i]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          utilities(attention, pending),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          wide ? 32 : 16,
                          20,
                          16,
                          12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                names[index],
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (mobile)
                              Builder(
                                builder: (context) => IconButton(
                                  tooltip: label('Menu', 'Menu'),
                                  icon: const Icon(Icons.menu),
                                  onPressed: () =>
                                      Scaffold.of(context).openDrawer(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Icon(
                              widget.status == 'synced'
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_off_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.status} · $pending ${label('pending', 'chờ đồng bộ')}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            if (widget.status == 'sign_in_required')
                              TextButton(
                                onPressed: logout,
                                child: const Text('Sign in again'),
                              ),
                            if (attention)
                              TextButton(
                                onPressed: showConflicts,
                                child: const Text('Resolve conflicts'),
                              ),
                          ],
                        ),
                      ),
                      if (widget.warning != null)
                        MaterialBanner(
                          content: Text(widget.warning!),
                          actions: [
                            TextButton(
                              onPressed: widget.sync,
                              child: const Text('Sync now'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: items.when(
                          data: (all) => routes[index] == 'tasks'
                              ? taskWorkspace(all)
                              : SingleChildScrollView(
                                  padding: EdgeInsets.all(wide ? 32 : 16),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1200,
                                      ),
                                      child: switch (routes[index]) {
                                        'matrix' => matrix(all),
                                        'habits' => habits(all),
                                        'calendar' => calendar(all),
                                        'focus' => focus(all),
                                        'search' => searchPage(all),
                                        _ => tasks(all),
                                      },
                                    ),
                                  ),
                                ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, _) => Center(
                            child: Text(
                              label(
                                'Could not open local storage. Retry by restarting.',
                                'Không thể mở bộ nhớ cục bộ.',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: widget.view == 'tasks'
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => editor(),
                  icon: const Icon(Icons.add),
                  label: Text(label('Add task', 'Thêm việc')),
                ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: (i) => context.go('/${routes[i]}'),
                  destinations: List.generate(
                    6,
                    (i) => NavigationDestination(
                      icon: Icon(icons[i]),
                      label: names[i],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
