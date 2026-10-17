import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Markdown source remains the only persisted value in both display modes.
class MarkdownEditor extends StatefulWidget {
  final TextEditingController controller;
  final bool vietnamese;
  final ValueChanged<String>? onChanged;
  const MarkdownEditor({
    super.key,
    required this.controller,
    required this.vietnamese,
    this.onChanged,
  });
  @override
  State<MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<MarkdownEditor> {
  bool sourceMode = false;
  final sourceKey = GlobalKey();
  final sourceMenu = ContextMenuController();
  String t(String en, String vi) => widget.vietnamese ? vi : en;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(selectionChanged);
    _MarkdownBrowserMenu.acquire();
  }

  void selectionChanged() {
    if (sourceMode) {
      showMarkdownSelectionMenu(
        sourceKey,
        widget.controller.selection,
        sourceMenu,
        (editable) => menu(
          context,
          editable,
          editable.textEditingValue.selection,
          widget.controller.text,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(selectionChanged);
      widget.controller.addListener(selectionChanged);
    }
  }

  @override
  void dispose() {
    sourceMenu.remove();
    widget.controller.removeListener(selectionChanged);
    _MarkdownBrowserMenu.release();
    super.dispose();
  }

  void replace(TextSelection selection, String replacement) {
    final c = widget.controller;
    if (!selection.isValid || selection.end > c.text.length) return;
    final value = c.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    if (value.length > 20000) return;
    c.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
    );
    widget.onChanged?.call(value);
    setState(() {});
  }

  void format(TextSelection selection, String before, [String? after]) {
    final source = widget.controller.text;
    if (after != null) {
      final selected = selection.textInside(source);
      if (before == '==' && selected.contains('\n')) {
        final lines = selected.split('\n');
        final prefixPattern = RegExp(
          r'^(?:#{1,3} |[-*] \[[ xX]\] |[-*] |\d+\. |> )',
        );
        final unhighlight = lines.where((line) => line.isNotEmpty).every((
          line,
        ) {
          final content = line.replaceFirst(prefixPattern, '');
          return content.startsWith('==') &&
              content.endsWith('==') &&
              content.length >= 4;
        });
        replace(
          selection,
          lines
              .map((line) {
                final prefix = prefixPattern.firstMatch(line)?.group(0) ?? '';
                final content = line.substring(prefix.length);
                return content.isEmpty
                    ? line
                    : '$prefix${unhighlight ? content.substring(2, content.length - 2) : '==$content=='}';
              })
              .join('\n'),
        );
        return;
      }
      replace(
        selection,
        selected.startsWith(before) &&
                selected.endsWith(after) &&
                selected.length >= before.length + after.length
            ? selected.substring(before.length, selected.length - after.length)
            : '$before$selected$after',
      );
      return;
    }
    final start = selection.start == 0
        ? 0
        : source.lastIndexOf('\n', selection.start - 1) + 1;
    var end = selection.end;
    if (end > start && source[end - 1] == '\n') end--;
    final nextBreak = source.indexOf('\n', end);
    end = nextBreak < 0 ? source.length : nextBreak;
    final lines = source.substring(start, end).split('\n');
    final prefix = RegExp(r'^(?:#{1,3} |[-*] \[[ xX]\] |[-*] |\d+\. |> )');
    replace(
      TextSelection(baseOffset: start, extentOffset: end),
      [
        for (var i = 0; i < lines.length; i++)
          '${before == '- [ ] ' && RegExp(r'^[-*] \[[xX]\] ').hasMatch(lines[i])
              ? '- [x] '
              : before == '1. '
              ? '${i + 1}. '
              : before}${lines[i].replaceFirst(prefix, '')}',
      ].join('\n'),
    );
  }

  Widget menu(
    BuildContext context,
    EditableTextState editable,
    TextSelection selection,
    String snapshot,
  ) {
    final capturedDisplayRange = editable.textEditingValue.selection;
    void apply(String before, [String? after]) {
      ContextMenuController.removeAny();
      editable.hideToolbar();
      // An external update must never apply old rendered offsets to new source.
      if (widget.controller.text != snapshot) return;
      final rich = editable.widget.controller;
      if (after != null && rich is RichMarkdownController) {
        final displayRange = capturedDisplayRange;
        final rawRange = rich.projection.sourceSelection(displayRange);
        final start = selection.start - rawRange.start;
        if (start >= 0 &&
            start + rich.source.length <= snapshot.length &&
            snapshot.substring(start, start + rich.source.length) ==
                rich.source) {
          replace(
            TextSelection(
              baseOffset: start,
              extentOffset: start + rich.source.length,
            ),
            rich.toggleMark(displayRange, before, after),
          );
        }
      } else {
        format(selection, before, after);
      }
    }

    if (selection.isCollapsed) return const SizedBox.shrink();
    final lineStart = selection.start == 0
        ? 0
        : snapshot.lastIndexOf('\n', selection.start - 1) + 1;
    final line = snapshot.substring(lineStart).split('\n').first;
    final prefix =
        RegExp(r'^(#{1,3} |[-*] \[[ xX]\] |[-*] |\d+\. |> )')
            .firstMatch(line)
            ?.group(0) ??
        '';
    final currentStyle = prefix.contains('[')
        ? '- [ ] '
        : RegExp(r'^\d').hasMatch(prefix)
        ? '1. '
        : prefix == '* '
        ? '- '
        : prefix;
    final styleIcon = switch (currentStyle) {
      '# ' || '## ' || '### ' => Icons.title,
      '- [ ] ' => Icons.check_box_outlined,
      '- ' => Icons.format_list_bulleted,
      '1. ' => Icons.format_list_numbered,
      '> ' => Icons.format_quote,
      _ => Icons.text_fields,
    };
    final anchors = editable.contextMenuAnchors;
    return TextFieldTapRegion(
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: false,
        child: TextSelectionToolbar(
          anchorAbove: anchors.primaryAnchor,
          anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
          children: [
            PopupMenuButton<String>(
              tooltip: t('Text style', 'Kiểu văn bản'),
              icon: currentStyle.startsWith('#')
                  ? Text(
                      'H${currentStyle.trim().length}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    )
                  : Icon(styleIcon),
              initialValue: currentStyle,
              onSelected: (value) => apply(value),
              itemBuilder: (_) => [
                for (final entry in {
                  '': t('Text', 'Văn bản'),
                  '# ': t('Heading 1', 'Tiêu đề 1'),
                  '## ': t('Heading 2', 'Tiêu đề 2'),
                  '### ': t('Heading 3', 'Tiêu đề 3'),
                  '- ': t('Bulleted list', 'Danh sách dấu đầu dòng'),
                  '1. ': t('Numbered list', 'Danh sách đánh số'),
                  '- [ ] ': t('Check item', 'Mục kiểm tra'),
                  '> ': t('Quote', 'Trích dẫn'),
                }.entries)
                  CheckedPopupMenuItem(
                    value: entry.key,
                    checked: currentStyle == entry.key,
                    child: Text(entry.value),
                  ),
              ],
            ),
            IconButton(
              tooltip: t('Bold', 'Đậm'),
              onPressed: () => apply('**', '**'),
              icon: const Icon(Icons.format_bold),
            ),
            IconButton(
              tooltip: t('Italic', 'Nghiêng'),
              onPressed: () => apply('*', '*'),
              icon: const Icon(Icons.format_italic),
            ),
            IconButton(
              tooltip: t('Strikethrough', 'Gạch ngang'),
              onPressed: () => apply('~~', '~~'),
              icon: const Icon(Icons.strikethrough_s),
            ),
            IconButton(
              tooltip: t('Link', 'Liên kết'),
              onPressed: () => apply('[', '](https://)'),
              icon: const Icon(Icons.link),
            ),
            IconButton(
              tooltip: t('Highlight', 'Tô sáng'),
              onPressed: () => apply('==', '=='),
              icon: const Icon(Icons.highlight, color: Color(0xFFB58A00)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            ContextMenuController.removeAny();
            setState(() => sourceMode = !sourceMode);
          },
          icon: Icon(sourceMode ? Icons.visibility_outlined : Icons.code),
          label: Text(
            sourceMode
                ? t('Rendered view', 'Xem định dạng')
                : t('Markdown code', 'Mã Markdown'),
          ),
        ),
      ),
      if (sourceMode)
        TextField(
          key: sourceKey,
          controller: widget.controller,
          onTapOutside: (_) {
            sourceMenu.remove();
            FocusManager.instance.primaryFocus?.unfocus();
          },
          minLines: 5,
          maxLines: null,
          maxLength: 20000,
          decoration: InputDecoration(
            labelText: t('Notes · Markdown', 'Ghi chú · Markdown'),
          ),
          contextMenuBuilder: (context, editable) => routeMarkdownMenu(
            editable,
            sourceMenu,
            menu(
              context,
              editable,
              editable.textEditingValue.selection,
              widget.controller.text,
            ),
          ),
          onChanged: widget.onChanged,
        )
      else
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => MarkdownPreview(
            source: value.text,
            onEdit: (source) {
              if (widget.controller.text == value.text) {
                replace(
                  TextSelection(baseOffset: 0, extentOffset: value.text.length),
                  source,
                );
              }
            },
            onToggleCheck: (offset) {
              if (widget.controller.text != value.text) return;
              ContextMenuController.removeAny();
              replace(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
                value.text[offset] == ' ' ? 'x' : ' ',
              );
            },
            emptyLabel: t('Write a note…', 'Viết ghi chú…'),
            contextMenuBuilder: (context, editable, selection) =>
                menu(context, editable, selection, value.text),
          ),
        ),
    ],
  );
}

/// Native long-press/right-click requests use the same independent overlay.
Widget routeMarkdownMenu(
  EditableTextState editable,
  ContextMenuController controller,
  Widget contents,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!editable.mounted) return;
    if (!editable.textEditingValue.selection.isValid ||
        editable.textEditingValue.selection.isCollapsed) {
      controller.remove();
      return;
    }
    editable.hideToolbar();
    controller.show(
      context: editable.context,
      contextMenuBuilder: (_) => contents,
    );
  });
  return const SizedBox.shrink();
}

/// Show outside EditableText's follower layer so hover/tooltip layout is safe.
void showMarkdownSelectionMenu(
  GlobalKey key,
  TextSelection selection,
  ContextMenuController controller,
  Widget Function(EditableTextState) buildMenu,
) {
  if (selection.isCollapsed || !selection.isValid) {
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.remove());
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final root = key.currentContext;
    if (root == null) return;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        final state = element.state as EditableTextState;
        final selection = state.textEditingValue.selection;
        if (!selection.isValid || selection.isCollapsed) {
          controller.remove();
          return;
        }
        // Build once to capture source offsets before toolbar focus/hover events.
        final contents = buildMenu(state);
        controller.show(
          context: state.context,
          contextMenuBuilder: (_) => contents,
        );
      } else {
        element.visitChildren(visit);
      }
    }

    (root as Element).visitChildren(visit);
  });
}

class _MarkdownMark {
  final String open, close;
  const _MarkdownMark(this.open, this.close);
  bool same(_MarkdownMark other) => open == other.open && close == other.close;
}

class _MarkdownCharacter {
  final String text, block;
  final List<_MarkdownMark> marks;
  final bool marker;
  const _MarkdownCharacter(this.text, this.marks, this.block, this.marker);
}

/// Editable display text and its formatting map back to canonical Markdown.
class RichMarkdownController extends TextEditingController {
  late MarkdownProjection projection;
  String source;
  TextTheme theme;
  final ValueChanged<String> onSourceChanged;
  bool updating = false;
  RichMarkdownController(this.source, this.theme, this.onSourceChanged) {
    projection = MarkdownProjection(source, theme);
    value = TextEditingValue(text: projection.text);
    addListener(_changed);
  }
  void updateSource(String next, TextTheme nextTheme) {
    if (source == next && theme == nextTheme) return;
    updating = true;
    source = next;
    theme = nextTheme;
    projection = MarkdownProjection(source, theme);
    value = TextEditingValue(
      text: projection.text,
      selection: TextSelection.collapsed(
        offset: selection.extentOffset.clamp(0, projection.text.length),
      ),
    );
    updating = false;
  }

  String toggleMark(TextSelection range, String open, String close) {
    final mark = _MarkdownMark(open, close);
    final selected = projection.characters
        .sublist(range.start, range.end)
        .where((c) => !c.marker && c.text != '\n');
    final remove =
        selected.isNotEmpty &&
        selected.every((c) => c.marks.any((m) => m.same(mark)));
    return _encodeCharacters([
      for (var i = 0; i < projection.characters.length; i++)
        if (i >= range.start &&
            i < range.end &&
            !projection.characters[i].marker &&
            projection.characters[i].text != '\n')
          _MarkdownCharacter(
            projection.characters[i].text,
            remove
                ? projection.characters[i].marks
                      .where((m) => !m.same(mark))
                      .toList()
                : [
                    ...projection.characters[i].marks.where(
                      (m) => !m.same(mark),
                    ),
                    mark,
                  ],
            projection.characters[i].block,
            false,
          )
        else
          projection.characters[i],
    ]);
  }

  String _encodeCharacters(List<_MarkdownCharacter> result) {
    final output = StringBuffer();
    var active = <_MarkdownMark>[];
    var lineStart = true;
    void close() {
      for (final mark in active.reversed) {
        output.write(mark.close);
      }
      active = [];
    }

    for (final char in result) {
      if (lineStart) {
        output.write(char.block);
        lineStart = false;
      }
      if (char.text == '\n') {
        close();
        output.write('\n');
        lineStart = true;
        continue;
      }
      if (char.marker) continue;
      var common = 0;
      while (common < active.length &&
          common < char.marks.length &&
          active[common].same(char.marks[common])) {
        common++;
      }
      for (final mark in active.skip(common).toList().reversed) {
        output.write(mark.close);
      }
      for (final mark in char.marks.skip(common)) {
        output.write(mark.open);
      }
      active = char.marks;
      output.write(char.text);
    }
    close();
    return output.toString();
  }

  void _changed() {
    if (updating || text == projection.text) return;
    final old = projection.text;
    final next = text;
    var start = 0;
    while (start < old.length &&
        start < next.length &&
        old[start] == next[start]) {
      start++;
    }
    var end = old.length, nextEnd = next.length;
    while (end > start &&
        nextEnd > start &&
        old[end - 1] == next[nextEnd - 1]) {
      end--;
      nextEnd--;
    }
    final chars = projection.characters;
    final inherited = chars.isEmpty
        ? const _MarkdownCharacter('', [], '', false)
        : chars[(start < chars.length ? start : start - 1).clamp(
            0,
            chars.length - 1,
          )];
    final result = <_MarkdownCharacter>[
      ...chars.take(start),
      for (final unit in next.substring(start, nextEnd).split(''))
        _MarkdownCharacter(unit, inherited.marks, inherited.block, false),
      ...chars.skip(end),
    ];
    final encoded = _encodeCharacters(result);
    if (encoded.length > 20000) {
      updating = true;
      value = TextEditingValue(
        text: old,
        selection: TextSelection.collapsed(offset: start),
      );
      updating = false;
      return;
    }
    source = encoded;
    projection = MarkdownProjection(source, theme);
    updating = true;
    final oldSelection = selection;
    value = TextEditingValue(
      text: projection.text,
      selection: TextSelection(
        baseOffset: oldSelection.baseOffset.clamp(0, projection.text.length),
        extentOffset: oldSelection.extentOffset.clamp(
          0,
          projection.text.length,
        ),
      ),
      composing: composingRangeFor(projection.text),
    );
    updating = false;
    onSourceChanged(source);
  }

  TextRange composingRangeFor(String text) =>
      value.composing.isValid && value.composing.end <= text.length
      ? value.composing
      : TextRange.empty;
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => TextSpan(style: style, children: projection.spans);
}

/// A displayed character retains its source range, including hidden delimiters.
class MarkdownProjection {
  final List<InlineSpan> spans = [];
  final List<int> starts = [], ends = [];
  String text = '';
  final characters = <_MarkdownCharacter>[];
  MarkdownProjection(String source, TextTheme theme) {
    var blockPrefix = '';
    void add(
      String value,
      int start,
      int end,
      TextStyle style, {
      List<_MarkdownMark> marks = const [],
      bool marker = false,
    }) {
      spans.add(TextSpan(text: value, style: style));
      text += value;
      for (var i = 0; i < value.length; i++) {
        characters.add(
          _MarkdownCharacter(value[i], marks, blockPrefix, marker),
        );
        starts.add(start + (i < end - start ? i : 0));
        ends.add(start + i + 1 <= end ? start + i + 1 : end);
      }
    }

    void parse(
      String content,
      int contentOffset,
      TextStyle style, [
      List<_MarkdownMark> marks = const [],
    ]) {
      final pattern = RegExp(
        r'==(.+?)==|\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*|\[([^\]]+)\]\(([^)]+)\)',
      );
      var cursor = 0;
      for (final match in pattern.allMatches(content)) {
        add(
          content.substring(cursor, match.start),
          contentOffset + cursor,
          contentOffset + match.start,
          style,
          marks: marks,
        );
        final highlighted = match.group(1) != null;
        final bold = match.group(2) != null;
        final strike = match.group(3) != null;
        final italic = match.group(4) != null;
        final value =
            match.group(1) ??
            match.group(2) ??
            match.group(3) ??
            match.group(4) ??
            match.group(5)!;
        final open = highlighted
            ? '=='
            : bold
            ? '**'
            : strike
            ? '~~'
            : italic
            ? '*'
            : '[';
        final close = match.group(5) != null ? '](${match.group(6)})' : open;
        final decorated = highlighted
            ? style.copyWith(
                backgroundColor: const Color(0xFFFFE066),
                color: const Color(0xFF211F16),
              )
            : bold
            ? style.copyWith(fontWeight: FontWeight.bold)
            : strike
            ? style.copyWith(decoration: TextDecoration.lineThrough)
            : italic
            ? style.copyWith(fontStyle: FontStyle.italic)
            : style.copyWith(decoration: TextDecoration.underline);
        final displayStart = starts.length;
        parse(value, contentOffset + match.start + open.length, decorated, [
          ...marks,
          _MarkdownMark(open, close),
        ]);
        if (starts.length > displayStart) {
          starts[displayStart] = contentOffset + match.start;
          ends[ends.length - 1] = contentOffset + match.end;
        }
        cursor = match.end;
      }
      add(
        content.substring(cursor),
        contentOffset + cursor,
        contentOffset + content.length,
        style,
        marks: marks,
      );
    }

    var offset = 0;
    for (final line in source.split('\n')) {
      var content = line;
      var contentOffset = offset;
      var style = theme.bodyMedium!;
      final block = RegExp(r'^(#{1,3} |[-*] \[[ xX]\] |[-*] |\d+\. |> )')
          .firstMatch(line);
      blockPrefix = block?.group(0) ?? '';
      if (block != null) {
        final prefix = block.group(0)!;
        content = line.substring(prefix.length);
        contentOffset += prefix.length;
        if (prefix.startsWith('#')) {
          style = [
            theme.headlineSmall!,
            theme.titleLarge!,
            theme.titleMedium!,
          ][prefix.trim().length - 1];
        } else {
          final marker = prefix.contains('[')
              ? (prefix.toLowerCase().contains('x') ? '☑ ' : '☐ ')
              : prefix == '> '
              ? '│ '
              : prefix == '- ' || prefix == '* '
              ? '• '
              : prefix;
          add(marker, offset, contentOffset, style, marker: true);
        }
      }
      parse(content, contentOffset, style);
      offset += line.length;
      if (offset < source.length) {
        add('\n', offset, offset + 1, style);
        offset++;
      }
    }
  }
  TextSelection sourceSelection(TextSelection selection) {
    if (!selection.isValid ||
        selection.isCollapsed ||
        selection.end > starts.length) {
      return const TextSelection.collapsed(offset: 0);
    }
    return TextSelection(
      baseOffset: starts[selection.start],
      extentOffset: ends[selection.end - 1],
    );
  }
}

class MarkdownPreview extends StatefulWidget {
  final String source, emptyLabel;
  final ValueChanged<int>? onToggleCheck;
  final ValueChanged<String>? onEdit;
  final Widget Function(BuildContext, EditableTextState, TextSelection)?
  contextMenuBuilder;
  const MarkdownPreview({
    super.key,
    required this.source,
    this.emptyLabel = '',
    this.onToggleCheck,
    this.onEdit,
    this.contextMenuBuilder,
  });
  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final selectionKey = GlobalKey();
  RichMarkdownController? rich;
  final menuController = ContextMenuController();
  @override
  void dispose() {
    menuController.remove();
    rich?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (RegExp(r'^[-*] \[[ xX]\] ', multiLine: true).hasMatch(widget.source)) {
      var offset = 0;
      final children = <Widget>[];
      for (final line in widget.source.split('\n')) {
        final lineOffset = offset;
        final check = RegExp(r'^[-*] \[[ xX]\] ').hasMatch(line);
        final contentOffset = lineOffset + (check ? 6 : 0);
        final content = check ? line.substring(6) : line;
        final preview = MarkdownPreview(
          source: content,
          onEdit: widget.onEdit == null
              ? null
              : (value) => widget.onEdit!(
                  widget.source.replaceRange(
                    contentOffset,
                    lineOffset + line.length,
                    value,
                  ),
                ),
          contextMenuBuilder: widget.contextMenuBuilder == null
              ? null
              : (context, editable, selection) => widget.contextMenuBuilder!(
                  context,
                  editable,
                  TextSelection(
                    baseOffset: contentOffset + selection.start,
                    extentOffset: contentOffset + selection.end,
                  ),
                ),
        );
        children.add(
          check
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: line[3].toLowerCase() == 'x',
                      semanticLabel: MarkdownProjection(
                        content,
                        Theme.of(context).textTheme,
                      ).text,
                      onChanged: widget.onToggleCheck == null
                          ? null
                          : (_) => widget.onToggleCheck!(lineOffset + 3),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: line[3].toLowerCase() == 'x'
                            ? Theme(
                                data: Theme.of(context).copyWith(
                                  textTheme: Theme.of(context).textTheme
                                      .copyWith(
                                        bodyMedium: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(
                                              decoration:
                                                  TextDecoration.lineThrough,
                                            ),
                                      ),
                                ),
                                child: preview,
                              )
                            : preview,
                      ),
                    ),
                  ],
                )
              : preview,
        );
        offset += line.length + 1;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final projection = MarkdownProjection(
      widget.source,
      Theme.of(context).textTheme,
    );
    if (widget.onEdit != null) {
      if (rich == null) {
        rich = RichMarkdownController(
          widget.source,
          Theme.of(context).textTheme,
          (value) => widget.onEdit?.call(value),
        );
        rich!.addListener(() {
          showMarkdownSelectionMenu(
            selectionKey,
            rich!.selection,
            menuController,
            (editable) => widget.contextMenuBuilder!(
              context,
              editable,
              rich!.projection.sourceSelection(
                editable.textEditingValue.selection,
              ),
            ),
          );
        });
      }
      rich!.updateSource(widget.source, Theme.of(context).textTheme);
      return TextField(
        key: selectionKey,
        controller: rich,
        minLines: 1,
        maxLines: null,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: widget.emptyLabel,
        ),
        onTapOutside: (_) {
          menuController.remove();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        contextMenuBuilder: (context, editable) => routeMarkdownMenu(
          editable,
          menuController,
          widget.contextMenuBuilder!(
            context,
            editable,
            rich!.projection.sourceSelection(
              editable.textEditingValue.selection,
            ),
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 24),
      child: widget.source.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.emptyLabel),
            )
          : SelectableText.rich(
              key: selectionKey,
              TextSpan(children: projection.spans),
              onSelectionChanged: widget.contextMenuBuilder == null
                  ? null
                  : (selection, _) => showMarkdownSelectionMenu(
                      selectionKey,
                      selection,
                      menuController,
                      (editable) => widget.contextMenuBuilder!(
                        context,
                        editable,
                        projection.sourceSelection(
                          editable.textEditingValue.selection,
                        ),
                      ),
                    ),
              contextMenuBuilder: widget.contextMenuBuilder == null
                  ? null
                  : (context, editable) => routeMarkdownMenu(
                      editable,
                      menuController,
                      widget.contextMenuBuilder!(
                        context,
                        editable,
                        projection.sourceSelection(
                          editable.textEditingValue.selection,
                        ),
                      ),
                    ),
            ),
    );
  }
}

// Flutter requires the browser menu to be disabled for custom text
// selection toolbars. Scope that change to mounted editors and preserve prior state.
class _MarkdownBrowserMenu {
  static int users = 0;
  static bool restore = false;
  static Future<void> queue = Future.value();
  static void acquire() {
    if (!kIsWeb || users++ > 0) return;
    queue = queue.then((_) async {
      restore = BrowserContextMenu.enabled;
      await BrowserContextMenu.disableContextMenu();
    });
    unawaited(queue);
  }

  static void release() {
    if (!kIsWeb || --users > 0) return;
    queue = queue.then((_) async {
      if (restore) await BrowserContextMenu.enableContextMenu();
    });
    unawaited(queue);
  }
}
