import 'package:flutter/material.dart';

import '../domain/item.dart';
import '../domain/organization.dart';

/// Shared controls for direct relationships; inherited tags are read-only.
class OrganizationFields extends StatelessWidget {
  final Item item;
  final List<Item> all;
  final bool vietnamese;
  final void Function(Map<String, dynamic>) onChanged;
  const OrganizationFields({
    super.key,
    required this.item,
    required this.all,
    required this.vietnamese,
    required this.onChanged,
  });
  String text(String en, String vi) => vietnamese ? vi : en;
  @override
  Widget build(BuildContext context) {
    final organization = Organization(all);
    final direct = organization.directTags(item);
    final candidates = all.where(
      (i) =>
          !i.deleted &&
          (item.kind == 'project'
              ? i.kind == 'task_list'
              : i.kind == 'task_list' ||
                    i.kind == 'project' ||
                    (i.kind == 'task' &&
                        i.id != item.id &&
                        !organization
                            .ancestors(i)
                            .any((a) => a.kind == 'task' && a.id == item.id))),
    );
    final location = item.kind == 'project'
        ? item.data['space_id']
        : item.data['parent_id'] ??
              item.data['project_id'] ??
              item.data['list_id'];
    final tags = all.where(
      (i) =>
          i.kind == 'tag' &&
          (i.data['archived_at'] == null || direct.contains(i.id)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.kind == 'task' || item.kind == 'project')
          DropdownButtonFormField<String>(
            key: ValueKey('location-$location'),
            initialValue: candidates.any((i) => i.id == location)
                ? location as String?
                : null,
            isExpanded: true,
            validator: (value) => item.kind == 'project' && value == null
                ? text('Choose a Space', 'Chọn không gian')
                : null,
            decoration: InputDecoration(labelText: text('Location', 'Vị trí')),
            items: [
              if (item.kind == 'task')
                DropdownMenuItem(
                  value: null,
                  child: Text(text('Inbox', 'Hộp thư')),
                ),
              ...candidates.map(
                (i) => DropdownMenuItem(
                  value: i.id,
                  child: Text(
                    '${i.kind == 'task_list'
                        ? text('Space', 'Không gian')
                        : i.kind == 'project'
                        ? text('Project', 'Dự án')
                        : text('Parent task', 'Công việc cha')}: ${i.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              final target = candidates.where((i) => i.id == value).firstOrNull;
              onChanged(
                item.kind == 'project'
                    ? {'space_id': value}
                    : {
                        'list_id': target?.kind == 'task_list' ? value : null,
                        'project_id': target?.kind == 'project' ? value : null,
                        'parent_id': target?.kind == 'task' ? value : null,
                      },
              );
            },
          ),
        if (item.kind == 'project')
          DropdownButtonFormField<String>(
            initialValue: item.data['status'] as String? ?? 'active',
            decoration: InputDecoration(
              labelText: text('Status', 'Trạng thái'),
            ),
            items: ['active', 'on_hold', 'completed', 'cancelled']
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      vietnamese
                          ? {
                              'active': 'Đang làm',
                              'on_hold': 'Tạm dừng',
                              'completed': 'Hoàn thành',
                              'cancelled': 'Đã hủy',
                            }[s]!
                          : s.replaceAll('_', ' '),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => onChanged({'status': v}),
          ),
        if (['task_list', 'project', 'tag'].contains(item.kind))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text('Archived', 'Đã lưu trữ')),
            value: item.data['archived_at'] != null,
            onChanged: (v) => onChanged({
              'archived_at': v
                  ? DateTime.now().toUtc().toIso8601String()
                  : null,
            }),
          ),
        if (item.kind != 'tag') ...[
          const SizedBox(height: 12),
          Text(text('Direct tags', 'Nhãn trực tiếp')),
          Wrap(
            spacing: 6,
            children: tags
                .map(
                  (tag) => FilterChip(
                    label: Text(
                      '#${tag.title}${tag.data['archived_at'] != null ? text(' (archived)', ' (lưu trữ)') : ''}',
                    ),
                    selected: direct.contains(tag.id),
                    onSelected:
                        tag.data['archived_at'] != null &&
                            !direct.contains(tag.id)
                        ? null
                        : (v) {
                            final next = {...direct};
                            if (v) {
                              next.add(tag.id);
                            } else {
                              next.remove(tag.id);
                            }
                            onChanged({'tag_ids': next.toList()});
                          },
                  ),
                )
                .toList(),
          ),
          if (organization
              .ancestors(item)
              .any((i) => organization.directTags(i).isNotEmpty))
            ExpansionTile(
              title: Text(
                text('Inherited tags and sources', 'Nhãn kế thừa và nguồn'),
              ),
              children: organization
                  .ancestors(item)
                  .expand(
                    (source) => organization
                        .directTags(source)
                        .map(
                          (id) => ListTile(
                            dense: true,
                            title: Text(
                              '#${organization.find('tag', id)?.title ?? id}',
                            ),
                            subtitle: Text(source.title),
                          ),
                        ),
                  )
                  .toList(),
            ),
        ],
      ],
    );
  }
}
