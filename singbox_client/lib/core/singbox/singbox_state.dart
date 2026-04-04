enum SingboxRunPhase { stopped, starting, running, stopping, error }

class SingboxState {
  const SingboxState({
    required this.phase,
    this.message,
  });

  final SingboxRunPhase phase;
  final String? message;

  static const SingboxState stopped = SingboxState(phase: SingboxRunPhase.stopped);
}
