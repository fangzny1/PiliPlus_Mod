import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Splits a title into keyword candidates by common delimiters.
List<String> _splitKeywords(String title) {
  final delimiters = RegExp(
    r'[，、。！？：；·/\s\-–—()（）【】\[\]「」{}《》""''　]',
  );
  final segments = title
      .split(delimiters)
      .map((s) => s.trim())
      .where((s) => s.length >= 2 && s.isNotEmpty)
      .toSet()
      .toList();
  return segments;
}

/// Shows a scrollable dialog that auto-splits a video title into keyword
/// candidates (chips) and provides a free-form text field for manual editing.
///
/// Tapping a chip appends/removes the keyword to/from the text field.
/// The user can also type or paste `|`-separated keywords directly.
/// Returns the merged keyword string, or null if cancelled.
Future<String?> showKeywordSplitterDialog({
  required BuildContext context,
  required String title,
  required String currentKeywords,
}) async {
  final candidates = _splitKeywords(title);
  if (candidates.isEmpty) {
    return null;
  }

  final controller = TextEditingController(text: currentKeywords);
  final existingSet = currentKeywords.isNotEmpty
      ? currentKeywords
          .split('|')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
      : <String>{};

  // Track which candidates are already in the text field
  // (existing keywords are present from the start)
  bool isInText(String keyword) {
    final parts = controller.text
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    return parts.any((p) => p == keyword);
  }

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
            title: const Text('添加标题关键词过滤'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Video title ──
                  Text(
                    '视频标题',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),

                  // ── Auto-split chips ──
                  const SizedBox(height: 16),
                  Text(
                    '提取到的关键词（点击添加/移除）',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: candidates.map((keyword) {
                      final present = isInText(keyword);
                      final isExisting = existingSet.contains(keyword);
                      return FilterChip(
                        label: Text(
                          isExisting ? '$keyword (已存在)' : keyword,
                          style: TextStyle(
                            fontSize: 13,
                            color: isExisting
                                ? Theme.of(context).colorScheme.outline
                                : null,
                          ),
                        ),
                        selected: present,
                        onSelected: isExisting
                            ? null
                            : (value) {
                                setState(() {
                                  final parts = controller.text
                                      .split('|')
                                      .map((e) => e.trim())
                                      .where((e) => e.isNotEmpty)
                                      .toList();
                                  if (value) {
                                    parts.add(keyword);
                                  } else {
                                    parts.remove(keyword);
                                  }
                                  controller
                                    ..text = parts.join('|')
                                    ..selection = TextSelection.fromPosition(
                                      TextPosition(
                                        offset: controller.text.length,
                                      ),
                                    );
                                });
                              },
                      );
                    }).toList(),
                  ),

                  // ── Manual edit field ──
                  const SizedBox(height: 16),
                  Text(
                    '编辑过滤词（可手动输入，| 分隔多个）',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    minLines: 2,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.all(8),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() {}),
                  ),

                  // ── Preview ──
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '原有过滤词',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentKeywords.isEmpty ? '（空）' : currentKeywords,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (controller.text != currentKeywords) ...[
                          const SizedBox(height: 6),
                          Text(
                            '保存后',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            controller.text.isEmpty ? '（空）' : controller.text,
                            style: TextStyle(
                              fontSize: 12,
                              color:
                                  Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Get.back(result: null),
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Get.back(result: controller.text),
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );

  return result;
}
