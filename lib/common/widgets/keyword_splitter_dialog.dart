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

/// Shows a dialog that auto-splits a video title into keyword candidates
/// and lets the user select which ones to add to the banWord filter.
///
/// Returns the merged keyword string (existing + new selections)
/// or null if the user cancelled.
Future<String?> showKeywordSplitterDialog({
  required BuildContext context,
  required String title,
  required String currentKeywords,
}) async {
  final candidates = _splitKeywords(title);
  if (candidates.isEmpty) {
    return null;
  }

  final existingSet = currentKeywords.isNotEmpty
      ? currentKeywords
          .split('|')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
      : <String>{};

  final selected = <String>{};

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final mergedKeywords = [...existingSet, ...selected].join('|');
          return AlertDialog(
            constraints: const BoxConstraints(maxWidth: 420),
            title: const Text('添加标题关键词过滤'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '提取到的关键词（点击选择）',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: candidates.map((keyword) {
                    final isSelected = selected.contains(keyword);
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
                      selected: isSelected || isExisting,
                      onSelected: isExisting
                          ? null
                          : (value) {
                              setState(() {
                                if (value) {
                                  selected.add(keyword);
                                } else {
                                  selected.remove(keyword);
                                }
                              });
                            },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
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
                        '当前过滤词',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentKeywords.isEmpty ? '（空）' : currentKeywords,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (selected.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '追加后',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mergedKeywords,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
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
                onPressed: selected.isNotEmpty || currentKeywords.isEmpty
                    ? () => Get.back(result: mergedKeywords)
                    : null,
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
