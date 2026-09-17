import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/widgets/list_item_card.dart';
import '../../../planner/schedule/presentation/screens/study_session_screen.dart';

/// "What should I study right now?" (blueprint §29) — the new landing tab.
/// Auto-loads a default 60-minute, all-projects plan plus upcoming goals;
/// reuses PlanPhasesView (planner/schedule) rather than re-rendering
/// phases a second way. Duration/scope controls stay on the full Planner
/// tab, not duplicated here — [onOpenPlanner] jumps there. [onOpenProjects]
/// backs the fresh-account hero CTA, since a project is the prerequisite
/// for everything else this screen shows.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.apiClient, required this.onOpenPlanner, required this.onOpenProjects});

  final ApiClient apiClient;
  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenProjects;

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

  Widget _sectionHeader(BuildContext context, {required IconData icon, required String title, Widget? trailing}) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (trailing != null) trailing,
      ],
    );
  }

  /// A smaller, inline version of the app's icon+text empty-state shape
  /// (see `AsyncListView`/`NexoraEmptyState`) sized for sitting inside a
  /// section rather than filling the whole screen.
  Widget _inlineEmpty(BuildContext context, {required IconData icon, required String message}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildFreshAccountHero(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(gradient: StudyOsColors.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            Text('Let\'s get you started', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Create a project and add material to it — Study OS will turn it into concepts, a study plan, and mastery tracking.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GradientButton(label: 'Create a project', icon: Icons.add, onPressed: widget.onOpenProjects),
          ],
        ),
      ),
    );
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
            final goals = _goals ?? [];

            if (concepts == 0 && goals.isEmpty) {
              return ListView(children: [_buildFreshAccountHero(context)]);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionHeader(
                  context,
                  icon: Icons.auto_awesome_rounded,
                  title: 'What to study right now',
                  trailing: TextButton(onPressed: widget.onOpenPlanner, child: const Text('Adjust')),
                ),
                if (concepts == 0)
                  _inlineEmpty(
                    context,
                    icon: Icons.insights_outlined,
                    message: 'Nothing to study yet — add concepts to a project to get a plan here.',
                  )
                else ...[
                  const SizedBox(height: 8),
                  PlanPhasesView(plan: _plan!),
                ],
                const SizedBox(height: 16),
                _sectionHeader(context, icon: Icons.flag_rounded, title: 'Upcoming goals'),
                if (goals.isEmpty)
                  _inlineEmpty(context, icon: Icons.flag_outlined, message: 'No goals set yet.')
                else ...[
                  const SizedBox(height: 8),
                  for (final goal in goals.take(5))
                    ListItemCard(
                      icon: Icons.flag_outlined,
                      iconColor: Theme.of(context).colorScheme.secondary,
                      title: goal['title'] as String,
                      subtitle: goal['target_date'] == null
                          ? null
                          : 'Due ${DateTime.parse(goal['target_date'] as String).toLocal().toString().split(' ')[0]}',
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
