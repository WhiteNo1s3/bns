import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';

/// Reusable gentle confetti for completes and wins.
/// Soft pastel colors preferred (never harsh).
class ConfettiOverlay extends StatelessWidget {
  final ConfettiController controller;

  const ConfettiOverlay({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConfettiWidget(
        confettiController: controller,
        blastDirectionality: BlastDirectionality.explosive,
        shouldLoop: false,
        emissionFrequency: 0.05,
        numberOfParticles: 25,
        gravity: 0.2,
        colors: const [
          Color(0xFF14B8A6), // teal
          Color(0xFF8B5CF6), // lavender
          Color(0xFFFDE047), // pill morning
          Color(0xFFFB923C), // pill noon
        ],
      ),
    );
  }
}
