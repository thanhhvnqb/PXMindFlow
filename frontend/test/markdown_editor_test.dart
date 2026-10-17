import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mindflow/features/tasks/presentation/markdown_editor.dart';

void main() {
  testWidgets(
    'Rendered text edits persist while retaining Markdown formatting',
    (tester) async {
      final source = TextEditingController(text: '# Heading\nKeep **this**');
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownEditor(
              controller: source,
              vietnamese: false,
              onChanged: (value) => saved = value,
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Heading\nKeep this');
      await tester.enterText(find.byType(TextField), 'Heading\nKeep these');
      await tester.pumpAndSettle();
      expect(saved, '# Heading\nKeep **these**');
      await tester.tap(find.text('Markdown code'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        saved,
      );
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );

  testWidgets(
    'Floating highlight menu tolerates mouse hover and hides after deselection',
    (tester) async {
      final source = TextEditingController(text: 'Select this');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: MarkdownEditor(controller: source, vietnamese: false),
          ),
        ),
      );
      var editable = tester.state<EditableTextState>(find.byType(EditableText));
      editable.userUpdateTextEditingValue(
        const TextEditingValue(
          text: 'Select this',
          selection: TextSelection(baseOffset: 7, extentOffset: 11),
        ),
        SelectionChangedCause.drag,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Text color'), findsNothing);
      expect(find.text('Copy'), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(tester.getCenter(find.byTooltip('Highlight')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Highlight'));
      await tester.pumpAndSettle();
      expect(source.text, 'Select ==this==');
      editable = tester.state<EditableTextState>(find.byType(EditableText));
      editable.userUpdateTextEditingValue(
        const TextEditingValue(
          text: 'Select this',
          selection: TextSelection(baseOffset: 7, extentOffset: 11),
        ),
        SelectionChangedCause.drag,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Highlight'), findsOneWidget);
      editable.userUpdateTextEditingValue(
        const TextEditingValue(
          text: 'Select this',
          selection: TextSelection.collapsed(offset: 11),
        ),
        SelectionChangedCause.tap,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Highlight'), findsNothing);
      await tester.tap(find.text('Markdown code'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      source.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Highlight'), findsOneWidget);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Highlight'), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    },
  );

  testWidgets('Rendered style dropdown keeps selection and applies heading', (
    tester,
  ) async {
    final source = TextEditingController(text: 'Hello');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(controller: source, vietnamese: false),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.userUpdateTextEditingValue(
      const TextEditingValue(
        text: 'Hello',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      ),
      SelectionChangedCause.drag,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Text style'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == '## ',
      ),
    );
    await tester.pumpAndSettle();
    expect(source.text, '## Hello');
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('Checklist supports direct text edits and toggles', (
    tester,
  ) async {
    final source = TextEditingController(text: '- [ ] Buy milk');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownEditor(controller: source, vietnamese: false),
        ),
      ),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(source.text, '- [x] Buy milk');
    await tester.enterText(find.byType(TextField), 'Buy tea');
    await tester.pumpAndSettle();
    expect(source.text, '- [x] Buy tea');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(source.text, '- [ ] Buy tea');
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  test('Partial highlight toggles and multiline marks stay balanced', () {
    final theme = ThemeData().textTheme;
    final controller = RichMarkdownController('==yellow==', theme, (_) {});
    expect(
      controller.toggleMark(
        const TextSelection(baseOffset: 1, extentOffset: 5),
        '==',
        '==',
      ),
      '==y==ello==w==',
    );
    controller.updateSource('## One\nTwo', theme);
    expect(
      controller.toggleMark(
        const TextSelection(baseOffset: 0, extentOffset: 7),
        '==',
        '==',
      ),
      '## ==One==\n==Two==',
    );
    controller.dispose();
  });

  test('Highlight renders yellow and old color HTML remains literal', () {
    const source = '==**Yellow**==';
    final projection = MarkdownProjection(source, ThemeData().textTheme);
    expect(projection.text, 'Yellow');
    expect(
      projection
          .sourceSelection(const TextSelection(baseOffset: 0, extentOffset: 6))
          .textInside(source),
      source,
    );
    final span = projection.spans.whereType<TextSpan>().singleWhere(
      (s) => s.text == 'Yellow',
    );
    expect(span.style!.backgroundColor, const Color(0xFFFFE066));
    expect(span.style!.fontWeight, FontWeight.bold);
    const html = '<span style="color:#B3261E">old</span>';
    expect(MarkdownProjection(html, ThemeData().textTheme).text, html);
  });

  test('Rendered controller preserves styles across deletion, paste and composing text', () {
    String? saved;
    final controller = RichMarkdownController(
      'A **bold** and ==yellow==',
      ThemeData().textTheme,
      (value) => saved = value,
    );
    controller.value = const TextEditingValue(
      text: 'A bo and yellow',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(saved, 'A **bo** and ==yellow==');
    controller.value = const TextEditingValue(
      text: 'A bo và yellow',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 5, end: 7),
    );
    expect(saved, 'A **bo** và ==yellow==');
    expect(controller.value.composing, const TextRange(start: 5, end: 7));
    controller.dispose();
  });
}
