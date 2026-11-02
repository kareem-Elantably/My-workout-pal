import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../shared/notifications_button.dart';
import '../shared/plan_views.dart';

final _myPlansProvider = FutureProvider.autoDispose<(WorkoutPlan?, NutritionPlan?)>((ref) async {
  final me = ref.watch(myIdProvider);
  final results = await Future.wait<Object?>([
    ref.watch(workoutRepositoryProvider).activePlan(me),
    ref.watch(nutritionRepositoryProvider).activePlan(me),
  ]);
  return (results[0] as WorkoutPlan?, results[1] as NutritionPlan?);
});

/// The trainee's current plans, read-only.
class PlanTab extends ConsumerWidget {
  const PlanTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final plans = ref.watch(_myPlansProvider);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.myPlan),
          actions: const [NotificationsButton()],
          bottom: TabBar(tabs: [Tab(text: l10n.workout), Tab(text: l10n.nutrition)]),
        ),
        body: AsyncBody(
          value: plans,
          onRetry: () => ref.invalidate(_myPlansProvider),
          builder: (p) {
            final (workout, nutrition) = p;
            final workoutVersion = workout?.versionOn(today());
            final nutritionVersion = nutrition?.versionOn(today());
            return TabBarView(children: [
              workoutVersion == null
                  ? EmptyList(icon: Icons.fitness_center, title: l10n.workoutPlanPreparing)
                  : WorkoutVersionView(
                      version: workoutVersion,
                      header: ListTile(title: Text(workout!.name, style: Theme.of(context).textTheme.titleLarge)),
                    ),
              nutritionVersion == null
                  ? EmptyList(icon: Icons.restaurant, title: l10n.nutritionPlanPreparing)
                  : NutritionVersionView(
                      version: nutritionVersion,
                      showMacros: nutrition!.showMacros,
                      header: ListTile(title: Text(nutrition.name, style: Theme.of(context).textTheme.titleLarge)),
                    ),
            ]);
          },
        ),
      ),
    );
  }
}
