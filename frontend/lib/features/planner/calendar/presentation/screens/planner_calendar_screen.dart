import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/api/api_client.dart';
import '../../../../../core/widgets/empty_state.dart';
import '../../../../../core/widgets/list_item_card.dart';

class _CalendarEvent {
  _CalendarEvent({required this.label, required this.type});
  final String label;
  final String type; // 'goal' | 'review' | 'flashcard'
}

/// A month-grid calendar (blueprint Section 22) marking Goal deadlines,
/// Concept review dates (Mastery's FSRS `next_review`), and Flashcard due
/// dates — a 4th tab on PlannerScreen. Deliberately a plain custom grid,
/// not a calendar package: this project has no calendar dependency yet,
/// and a month grid is simple enough not to need one (see blueprint
/// Section 55.12, "don't overengineer").
///
/// All three data sources are account-wide endpoints that already
/// existed (listGoals/getMastery) or were a one-line sibling of an
/// existing endpoint (listAllFlashcards, mirroring getDueFlashcards
/// without the due-date filter) — no new "calendar" backend concept.
class PlannerCalendarScreen extends StatefulWidget {
  const PlannerCalendarScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<PlannerCalendarScreen> createState() => _PlannerCalendarScreenState();
}

class _PlannerCalendarScreenState extends State<PlannerCalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  bool _isLoading = false;
  String? _error;
  final Map<DateTime, List<_CalendarEvent>> _eventsByDay = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _addEvent(String? isoDate, _CalendarEvent event) {
    if (isoDate == null) return;
    final day = _dateOnly(DateTime.parse(isoDate).toLocal());
    _eventsByDay.putIfAbsent(day, () => []).add(event);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _eventsByDay.clear();
    });
    try {
      final goals = await widget.apiClient.listGoals();
      for (final raw in goals['goals'] as List<dynamic>) {
        final goal = raw as Map<String, dynamic>;
        _addEvent(goal['target_date'] as String?, _CalendarEvent(label: goal['title'] as String, type: 'goal'));
      }

      final mastery = await widget.apiClient.getMastery();
      for (final raw in mastery['mastery'] as List<dynamic>) {
        final m = raw as Map<String, dynamic>;
        _addEvent(
          m['next_review'] as String?,
          _CalendarEvent(label: 'Review: ${m['concept_name']}', type: 'review'),
        );
      }

      final flashcards = await widget.apiClient.listAllFlashcards();
      for (final raw in flashcards['flashcards'] as List<dynamic>) {
        final f = raw as Map<String, dynamic>;
        _addEvent(f['due'] as String?, _CalendarEvent(label: 'Flashcard: ${f['front']}', type: 'flashcard'));
      }
      setState(() {});
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selectedDay = null;
    });
  }

  Color _dotColor(String type, BuildContext context) {
    switch (type) {
      case 'goal':
        return StudyOsColors.amber;
      case 'flashcard':
        return const Color(0xFF0EA5E9);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _eventsByDay.isEmpty) return const Center(child: CircularProgressIndicator());

    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    // Monday-first grid — firstOfMonth.weekday is 1 (Mon) - 7 (Sun).
    final leadingBlanks = firstOfMonth.weekday - 1;

    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _changeMonth(-1)),
              Text('${_monthName(_month.month)} ${_month.year}', style: Theme.of(context).textTheme.titleMedium),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _changeMonth(1)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
            itemCount: leadingBlanks + daysInMonth,
            itemBuilder: (context, index) {
              if (index < leadingBlanks) return const SizedBox.shrink();
              final day = DateTime(_month.year, _month.month, index - leadingBlanks + 1);
              final events = _eventsByDay[day] ?? [];
              final isSelected = _selectedDay != null && _dateOnly(_selectedDay!) == day;
              final isToday = _dateOnly(DateTime.now()) == day;
              return InkWell(
                onTap: events.isEmpty ? null : () => setState(() => _selectedDay = day),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (isToday ? Theme.of(context).colorScheme.primaryContainer : null),
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? Colors.white : (isToday ? Theme.of(context).colorScheme.primary : null),
                        ),
                      ),
                      if (events.isNotEmpty)
                        Wrap(
                          spacing: 2,
                          children: [
                            for (final e in events.take(3))
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(color: _dotColor(e.type, context), shape: BoxShape.circle),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 24),
        Expanded(
          child: _selectedDay == null
              ? const EmptyState(icon: Icons.event_outlined, message: 'Tap a marked day to see what\'s due.')
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final e in _eventsByDay[_dateOnly(_selectedDay!)] ?? [])
                      ListItemCard(
                        icon: e.type == 'goal'
                            ? Icons.flag_outlined
                            : e.type == 'flashcard'
                                ? Icons.style_outlined
                                : Icons.school_outlined,
                        iconColor: _dotColor(e.type, context),
                        title: e.label,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  String _monthName(int month) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month - 1];
}
