import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/overview_cards.dart';
import 'stage_wizard_screen.dart';

/// Stage Configuration Screen
///
/// Shows a brief overview of the current growth stage (mirroring the compact
/// Environmental Data card on the Monitoring tab), followed by the full stage
/// wizard for configuring all three growth stages (Incubation, Pinning,
/// Fruiting) in one flow.
class StageScreen extends ConsumerWidget {
  const StageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: StageOverviewCard(),
        ),
        const Expanded(child: StageWizardScreen()),
      ],
    );
  }
}