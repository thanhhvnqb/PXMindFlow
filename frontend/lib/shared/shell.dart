import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../app/providers.dart';
import '../features/tasks/domain/item.dart';
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
  String filter = 'All';
  String search = '';
  String? listId;
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

  Future<void> editor({Item? item, String kind = 'task'}) async {
    final title = TextEditingController(text: item?.title ?? '');
    final notes = TextEditingController(text: item?.notes ?? '');
    var urgent = item?.data['is_urgent'] == true;
    var important = item?.data['is_important'] == true;
    var due = item?.dueDate;
    var priority = item?.data['priority'] as int? ?? 0;
    var project = item?.data['list_id'] as String? ?? listId;
    final lists =
        ref
            .read(itemsProvider)
            .asData
            ?.value
            .where((i) => i.kind == 'task_list')
            .toList() ??
        [];
    final form = GlobalKey<FormState>();
    await managedDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            item == null
                ? label('Create ${kind.replaceAll('_', ' ')}', 'Tạo mới')
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
                    if (kind == 'task') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText: label('Notes', 'Ghi chú'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: lists.any((l) => l.id == project)
                            ? project
                            : null,
                        decoration: InputDecoration(
                          labelText: label('List', 'Danh sách'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(label('Inbox', 'Hộp thư')),
                          ),
                          ...lists.map(
                            (l) => DropdownMenuItem(
                              value: l.id,
                              child: Text(l.title),
                            ),
                          ),
                        ],
                        onChanged: (value) => project = value,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: priority,
                        decoration: InputDecoration(
                          labelText: label('Priority', 'Ưu tiên'),
                        ),
                        items: List.generate(
                          4,
                          (p) => DropdownMenuItem(
                            value: p,
                            child: Text(['None', 'Low', 'Medium', 'High'][p]),
                          ),
                        ),
                        onChanged: (p) => priority = p ?? 0,
                      ),
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
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.event),
                              label: Text(
                                due ?? label('Set due date', 'Chọn ngày'),
                              ),
                              onPressed: () async {
                                final value = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                  initialDate: due == null
                                      ? DateTime.now()
                                      : DateTime.parse(due!),
                                );
                                if (value != null) {
                                  update(
                                    () => due = DateFormat(
                                      'yyyy-MM-dd',
                                    ).format(value),
                                  );
                                }
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: label('Clear date', 'Xóa ngày'),
                            onPressed: () => update(() => due = null),
                            icon: const Icon(Icons.clear),
                          ),
                        ],
                      ),
                    ],
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
                if (!form.currentState!.validate()) return;
                await perform(
                  () => repo.save(kind, {
                    ...?item?.data,
                    'title': title.text.trim(),
                    if (kind == 'task') ...{
                      'notes': notes.text,
                      'priority': priority,
                      'list_id': project,
                      'due_date': due,
                      'completed': item?.completed ?? false,
                      'is_urgent': urgent,
                      'is_important': important,
                    },
                    if (kind == 'habit') ...{
                      'timezone': 'Etc/UTC',
                      'target': 1,
                    },
                  }, id: item?.id),
                );
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
  }

  Future<void> remove(Item item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label('Delete “${item.title}”?', 'Xóa “${item.title}”?')),
        content: Text(
          label(
            'This deletion will sync to your devices.',
            'Thao tác xóa sẽ đồng bộ với các thiết bị.',
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
        () => repo.save(
          item.kind,
          LocalRepository.clean(item.data),
          id: item.id,
          delete: true,
        ),
      );
    }
  }

  Widget taskTile(Item item) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    elevation: 0,
    child: ListTile(
      leading: Checkbox(
        value: item.completed,
        onChanged: (value) => perform(
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
      subtitle: item.dueDate != null || item.notes.isNotEmpty
          ? Text(
              [
                if (item.dueDate != null) item.dueDate!,
                if (item.notes.isNotEmpty) item.notes,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => editor(item: item),
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
  Widget tasks(List<Item> all) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tasks =
        all
            .where(
              (i) =>
                  i.kind == 'task' &&
                  (listId == null || i.data['list_id'] == listId),
            )
            .where(
              (i) => switch (filter) {
                'Today' =>
                  !i.completed &&
                      i.dueDate != null &&
                      i.dueDate!.compareTo(today) <= 0,
                'Upcoming' =>
                  !i.completed &&
                      i.dueDate != null &&
                      i.dueDate!.compareTo(today) > 0,
                'Completed' => i.completed,
                _ => !i.completed,
              },
            )
            .toList()
          ..sort(
            (a, b) => (b.data['priority'] as int? ?? 0).compareTo(
              a.data['priority'] as int? ?? 0,
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['All', 'Today', 'Upcoming', 'Completed']
              .map(
                (v) => ChoiceChip(
                  label: Text(v),
                  selected: filter == v,
                  onSelected: (_) => setState(() => filter = v),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(label('All lists', 'Mọi danh sách')),
              selected: listId == null,
              onSelected: (_) => setState(() => listId = null),
            ),
            ...all
                .where((i) => i.kind == 'task_list')
                .map(
                  (i) => InputChip(
                    label: Text(i.title),
                    selected: listId == i.id,
                    onPressed: () => setState(() => listId = i.id),
                    onDeleted: () => remove(i),
                  ),
                ),
            ActionChip(
              label: Text(label('New list', 'Danh sách mới')),
              avatar: const Icon(Icons.add, size: 18),
              onPressed: () => editor(kind: 'task_list'),
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
        ...tasks.map(taskTile),
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
        .where((i) => i.kind == 'task' && i.dueDate == key)
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
        ...tasks.map(taskTile),
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
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w300,
            fontSize: 80,
          ),
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
                    'elapsed_seconds': elapsed(
                      active,
                    ).clamp(0, active.data['duration_seconds']),
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
    final results = resultState.asData?.value ?? <Item>[];
    return Column(
      children: [
        TextField(
          autofocus: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: label(
              'Search your tasks, lists and habits',
              'Tìm công việc, danh sách và thói quen',
            ),
          ),
          onChanged: (v) => setState(() => search = v),
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
                    subtitle: Text(i.kind),
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
                                child: const Text('Keep mine'),
                              ),
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
    final wide = MediaQuery.sizeOf(context).width >= 800;
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
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 224,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.spa_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'MindFlow',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          ...List.generate(
                            6,
                            (i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                selected: index == i,
                                selectedTileColor: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                leading: Icon(icons[i]),
                                title: Text(names[i]),
                                onTap: () => context.go('/${routes[i]}'),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            label(
                              'A calmer kind of productive.',
                              'Làm việc nhẹ nhàng hơn.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
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
                            IconButton(
                              tooltip: label(
                                'Sync: ${widget.status} · $pending pending',
                                'Đồng bộ: ${widget.status} · $pending chờ',
                              ),
                              onPressed: attention
                                  ? showConflicts
                                  : widget.sync,
                              icon: Icon(
                                attention ? Icons.warning_amber : Icons.sync,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Theme',
                              onPressed: widget.toggleTheme,
                              icon: const Icon(Icons.brightness_6_outlined),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Settings',
                              onSelected: (v) => v == 'language'
                                  ? widget.toggleLanguage()
                                  : logout(),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'language',
                                  child: Text('English / Tiếng Việt'),
                                ),
                                PopupMenuItem(
                                  value: 'logout',
                                  child: Text(label('Sign out', 'Đăng xuất')),
                                ),
                              ],
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
                          data: (all) => SingleChildScrollView(
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
          floatingActionButton: FloatingActionButton.extended(
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
