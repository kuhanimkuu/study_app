import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../planner/schedule/presentation/screens/study_session_screen.dart';

/// "What should I study right now?" (blueprint §29) — the new landing tab.
/// Auto-loads a default 60-minute, all-projects plan plus upcoming goals;
/// reuses PlanPhasesView (planner/schedule) rather than re-rendering
/// phases a second way. Duration/scope controls stay on the full Planner
/// tab, not duplicated here — [onOpenPlanner] jumps there.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.apiClient, required this.onOpenPlanner});

  final ApiClient apiClient;
  final VoidCallback onOpenPlanner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _plan;
  List<dynamic>? _goals;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.apiClient.getPlan(durationMinutes: 60),
        widget.apiClient.listGoals(),
      ]);
      final goals = (results[1]['goals'] as List<dynamic>).cast<Map<String, dynamic>>();
      goals.sort((a, b) {
        final aDate = a['target_date'] as String?;
        final bDate = b['target_date'] as String?;
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1; // no-date goals sort last
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });
      setState(() {
        _plan = results[0];
        _goals = goals;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Builder(
          builder: (context) {
            if (_isLoading && _plan == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              );
            }
            final concepts = (_plan?['concepts_considered'] as int?) ?? 0;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('What to study right now', style: Theme.of(context).textTheme.titleMedium),
                    TextButton(onPressed: widget.onOpenPlanner, child: const Text('Adjust')),
                  ],
                ),
                const SizedBox(height: 8),
                if (concepts == 0)
                  const Text('Nothing to study yet — add concepts to a project to get a plan here.')
                else
                  PlanPhasesView(plan: _plan!),
                const SizedBox(height: 24),
                Text('Upcoming goals', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if ((_goals ?? []).isEmpty)
                  const Text('No goals set yet.')
                else
                  for (final goal in _goals!.take(5))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(goal['title'] as String),
                        subtitle: goal['target_date'] == null
                            ? null
                            : Text('Due ${DateTime.parse(goal['target_date'] as String).toLocal().toString().split(' ')[0]}'),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
