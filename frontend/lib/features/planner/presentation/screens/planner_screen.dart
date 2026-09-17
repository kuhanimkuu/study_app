import 'package:flutter/material.dart';

import '../../../../core/api/api_client.dart';
import '../../../progress/presentation/screens/progress_screen.dart';
import '../../calendar/presentation/screens/planner_calendar_screen.dart';
import '../../goals/presentation/screens/goals_list_screen.dart';
import '../../schedule/presentation/screens/study_plan_screen.dart';

/// Top-level Planner tab (blueprint Sections 21-22, 39) — "Plan" (generate
/// a prioritized study plan, start a session), "Goals" (create/delete
/// study goals), and "Progress" (mastery/weak-spots/activity — folded in
/// here rather than a 4th bottom-nav tab; see STUDY_OS_PROGRESS.md's
/// Frontend Phase 3 entry for that call). Same TabBar/TabBarView container
/// shape as ProjectWorkspaceScreen.
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Planner'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Plan'), Tab(text: 'Goals'), Tab(text: 'Progress'), Tab(text: 'Calendar')],
          ),
        ),
        body: TabBarView(
          children: [
            StudyPlanScreen(apiClient: apiClient),
            GoalsListScreen(apiClient: apiClient),
            ProgressScreen(apiClient: apiClient),
            PlannerCalendarScreen(apiClient: apiClient),
          ],
        ),
      ),
    );
  }
}
