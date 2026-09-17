import 'package:flutter/material.dart';

/// The loading/error/empty/list 4-branch pattern every list screen in
/// this app (Concepts, Flashcards, Notes, Goals, Projects, ...) already
/// wrote by hand, extracted once it was clearly the same shape
/// everywhere rather than up front — see blueprint Section 55.12,
/// "don't overengineer." Adopted in the two newest list screens so far
/// (Flashcards, Notes) as the real "not over-specialized to one call
/// site" check; the older screens are untouched, working code and not
/// worth touching just to use this.
class AsyncListView<T> extends StatelessWidget {
  const AsyncListView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.items,
    required this.itemBuilder,
    required this.emptyMessage,
    this.onRefresh,
    this.header,
  });

  /// True while a fetch is in flight. Only shows the loading spinner when
  /// `items` is also still null (a pull-to-refresh mid-flight keeps
  /// showing the previous list, not a spinner replacing it).
  final bool isLoading;
  final String? error;
  final List<T>? items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyMessage;
  final Future<void> Function()? onRefresh;

  /// Optional widget rendered above the list/empty-state (e.g. Flashcards'
  /// "Review due cards" button) — still shown even when `items` is empty,
  /// unlike `itemBuilder` rows.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (isLoading && items == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      child = ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      );
    } else {
      final list = items ?? [];
      child = ListView(
        children: [
          if (header != null) header!,
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(emptyMessage)),
            )
          else
            for (final item in list) itemBuilder(context, item),
        ],
      );
    }
    if (onRefresh == null) return child;
    return RefreshIndicator(onRefresh: onRefresh!, child: child);
  }
}
