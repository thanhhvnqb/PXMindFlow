import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TaskPriorityButton extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool vietnamese;
  const TaskPriorityButton({
    super.key,
    required this.value,
    required this.onChanged,
    required this.vietnamese,
  });
  @override
  Widget build(BuildContext context) {
    final labels = vietnamese
        ? ['Không', 'Thấp', 'Trung bình', 'Cao']
        : ['None', 'Low', 'Medium', 'High'];
    final colors = [
      Theme.of(context).colorScheme.outline,
      Colors.blue,
      Colors.orange,
      Colors.red,
    ];
    return PopupMenuButton<int>(
      tooltip: vietnamese ? 'Ưu tiên' : 'Priority',
      initialValue: value,
      icon: Icon(
        value == 0 ? Icons.outlined_flag : Icons.flag,
        color: colors[value],
      ),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final p in [3, 2, 1, 0])
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(
                  p == 0 ? Icons.outlined_flag : Icons.flag,
                  color: colors[p],
                ),
                const SizedBox(width: 12),
                Text(labels[p]),
                const Spacer(),
                if (p == value) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

class TaskDateButton extends StatelessWidget {
  final String? value;
  final void Function(String? date, String? dueAt) onChanged;
  final String? dueAt;
  final bool vietnamese;
  const TaskDateButton({
    super.key,
    required this.value,
    required this.onChanged,
    required this.vietnamese,
    this.dueAt,
  });
  @override
  Widget build(BuildContext context) {
    final instant = DateTime.tryParse(dueAt ?? '')?.toLocal();
    final displayDate = instant == null
        ? value
        : DateFormat('yyyy-MM-dd').format(instant);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return TextButton.icon(
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        (displayDate == today
                ? (vietnamese ? 'Hôm nay' : 'Today')
                : displayDate ?? (vietnamese ? 'Chọn ngày' : 'Set due date')) +
            (instant == null ? '' : ', ${DateFormat('HH:mm').format(instant)}'),
      ),
      onPressed: () async {
        var selected =
            instant ?? DateTime.tryParse(value ?? '') ?? DateTime.now();
        TimeOfDay? time = instant == null
            ? null
            : TimeOfDay.fromDateTime(instant);
        final result = await showDialog<({String? date, String? at})>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: Text(vietnamese ? 'Ngày đến hạn' : 'Due date'),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final days in [0, 1, 7])
                            ActionChip(
                              label: Text(
                                (vietnamese
                                    ? ['Hôm nay', 'Ngày mai', 'Tuần sau']
                                    : ['Today', 'Tomorrow', 'Next week'])[[
                                  0,
                                  1,
                                  7,
                                ].indexOf(days)],
                              ),
                              onPressed: () => update(
                                () => selected = DateTime.now().add(
                                  Duration(days: days),
                                ),
                              ),
                            ),
                        ],
                      ),
                      CalendarDatePicker(
                        key: ValueKey(
                          DateFormat('yyyy-MM-dd').format(selected),
                        ),
                        initialDate: selected,
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                        onDateChanged: (date) => selected = date,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.schedule),
                              label: Text(
                                time == null
                                    ? (vietnamese ? 'Chọn giờ' : 'Set time')
                                    : time!.format(context),
                              ),
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      time ??
                                      const TimeOfDay(hour: 9, minute: 0),
                                );
                                if (picked != null && context.mounted) {
                                  update(() => time = picked);
                                }
                              },
                            ),
                          ),
                          if (time != null)
                            IconButton(
                              tooltip: vietnamese ? 'Xóa giờ' : 'Clear time',
                              onPressed: () => update(() => time = null),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, (date: null, at: null)),
                  child: Text(vietnamese ? 'Xóa ngày' : 'Clear'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(vietnamese ? 'Hủy' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    date: DateFormat('yyyy-MM-dd').format(selected),
                    at: time == null
                        ? null
                        : DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            time!.hour,
                            time!.minute,
                          ).toUtc().toIso8601String(),
                  )),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
        if (result != null) onChanged(result.date, result.at);
      },
    );
  }
}

class QuickTaskEntry extends StatefulWidget {
  final bool vietnamese;
  final Future<void> Function(
    String title,
    String? due,
    int priority,
    String? dueAt,
  )
  onSave;
  final Future<bool> Function(
    String title,
    String? due,
    int priority,
    String? dueAt,
  )
  onDetails;
  const QuickTaskEntry({
    super.key,
    required this.vietnamese,
    required this.onSave,
    required this.onDetails,
  });
  @override
  State<QuickTaskEntry> createState() => _QuickTaskEntryState();
}

class _QuickTaskEntryState extends State<QuickTaskEntry> {
  final title = TextEditingController();
  final focus = FocusNode();
  String? due = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String? dueAt;
  int priority = 0;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || title.text.trim().isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(title.text.trim(), due, priority, dueAt);
      if (!mounted) return;
      title.clear();
      focus.requestFocus();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = widget.vietnamese
              ? 'Không thể lưu. Hãy thử lại.'
              : 'Could not save. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: title,
        focusNode: focus,
        maxLength: 500,
        enabled: !saving,
        onSubmitted: (_) => save(),
        decoration: InputDecoration(
          hintText: widget.vietnamese ? 'Thêm việc' : 'Add task',
          counterText: '',
          errorText: error,
          prefixIcon: const Icon(Icons.add),
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TaskDateButton(
                value: due,
                dueAt: dueAt,
                vietnamese: widget.vietnamese,
                onChanged: (value, at) => setState(() {
                  due = value;
                  dueAt = at;
                }),
              ),
              IconButton(
                tooltip: widget.vietnamese ? 'Thêm việc' : 'Add task',
                onPressed: save,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.keyboard_return),
              ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          TaskPriorityButton(
            value: priority,
            onChanged: (value) => setState(() => priority = value),
            vietnamese: widget.vietnamese,
          ),
          IconButton(
            tooltip: widget.vietnamese ? 'Chi tiết công việc' : 'Task details',
            onPressed: saving
                ? null
                : () async {
                    final saved = await widget.onDetails(
                      title.text,
                      due,
                      priority,
                      dueAt,
                    );
                    if (mounted && saved) title.clear();
                  },
            icon: const Icon(Icons.open_in_full, size: 18),
          ),
        ],
      ),
    ],
  );
}
