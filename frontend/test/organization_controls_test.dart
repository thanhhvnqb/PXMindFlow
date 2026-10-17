import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/features/tasks/domain/item.dart';
import 'package:mindflow/features/tasks/presentation/organization_fields.dart';

void main() {
  testWidgets(
    'direct tag edits omit inherited and archived suggestions; location uses one reference',
    (tester) async {
      final all = [
        Item('space', 'task_list', 0, {
          'title': 'Teaching',
          'tag_ids': ['inherited'],
        }),
        Item('project', 'project', 0, {
          'title': 'Semester',
          'space_id': 'space',
        }),
        Item('inherited', 'tag', 0, {'title': 'QBU'}),
        Item('direct', 'tag', 0, {'title': 'Preparation'}),
        Item('archived', 'tag', 0, {
          'title': 'Old',
          'archived_at': '2026-10-17T00:00:00Z',
        }),
      ];
      var data = <String, dynamic>{'title': 'Prepare', 'list_id': 'space'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => SingleChildScrollView(
                child: OrganizationFields(
                  item: Item('task', 'task', 0, data),
                  all: all,
                  vietnamese: false,
                  onChanged: (patch) =>
                      update(() => data = {...data, ...patch}),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('#Old'), findsNothing);
      final inherited = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, '#QBU'),
      );
      expect(inherited.selected, isFalse);
      await tester.tap(find.widgetWithText(FilterChip, '#Preparation'));
      await tester.pumpAndSettle();
      expect(data['tag_ids'], ['direct']);
      await tester.tap(find.text('Inherited tags and sources'));
      await tester.pumpAndSettle();
      expect(find.text('Teaching'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Project: Semester').last);
      await tester.pumpAndSettle();
      expect(data['project_id'], 'project');
      expect(data['list_id'], isNull);
      expect(data['parent_id'], isNull);
    },
  );

  testWidgets(
    'project requires Space and archive preserves independent status',
    (tester) async {
      final form = GlobalKey<FormState>();
      var data = <String, dynamic>{'title': 'Semester', 'status': 'completed'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Form(
                key: form,
                child: OrganizationFields(
                  item: Item('p', 'project', 0, data),
                  all: const [],
                  vietnamese: false,
                  onChanged: (patch) =>
                      update(() => data = {...data, ...patch}),
                ),
              ),
            ),
          ),
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Choose a Space'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(data['archived_at'], isNotNull);
      expect(data['status'], 'completed');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(data['archived_at'], isNull);
      expect(data['status'], 'completed');
    },
  );
}
