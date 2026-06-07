import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api/client.dart';
import '../core/realtime/realtime_client.dart';
import '../ui/synapse_tokens.dart';

/// Transient status indicator for live council events that the durable
/// [DeliberationRoundsCard] doesn't surface in real time. Watches the
/// `council:{id}` channel for:
///
///   * `red_team_started`            → "Red team round in progress…"
///   * `red_team_complete`           → "Red team complete (N attacks)" — clears after 4 s
///   * `deliberation_round_started`  → "Deliberation round N in progress…"
///
/// Stays empty when the council runs in standard mode (no opt-in).
class LiveStatusBanner extends StatefulWidget {
  final SynapseApiClient client;
  final String councilId;

  const LiveStatusBanner({
    super.key,
    required this.client,
    required this.councilId,
  });

  @override
  State<LiveStatusBanner> createState() => _LiveStatusBannerState();
}

/// Sealed status type — exposed at package-level (not `_`-prefixed) so
/// the reducer in [liveStatusFor] can be unit-tested independently of the
/// widget machinery.
sealed class LiveStatus {}

class RedTeamInProgress extends LiveStatus {}

class RedTeamComplete extends LiveStatus {
  final int count;
  RedTeamComplete(this.count);
}

class DeliberationRound extends LiveStatus {
  final int round;
  DeliberationRound(this.round);
}

/// Pure reducer: maps a live event to the new status (or `null` for
/// unknown / no-op event types). Kept separate from the widget so the
/// event-to-UI mapping is tested without a full Flutter binding.
LiveStatus? liveStatusFor(NormalizedRealtimeEvent event) {
  switch (event.type) {
    case 'red_team_started':
      return RedTeamInProgress();
    case 'red_team_complete':
      final attacks = event.payload['attacks'];
      return RedTeamComplete(attacks is List ? attacks.length : 0);
    case 'deliberation_round_started':
      final round = event.payload['round'];
      return DeliberationRound(round is int ? round : 0);
    default:
      // Forward-compat: unknown event types are ignored silently so the
      // backend can add new live events without bumping the contract.
      return null;
  }
}

class _LiveStatusBannerState extends State<LiveStatusBanner> {
  SynapseRealtimeClient? _realtime;
  StreamSubscription<NormalizedRealtimeEvent>? _subscription;
  Timer? _autoClear;
  LiveStatus? _status;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final descriptor = await widget.client.getRealtimeDescriptor();
      _realtime = SynapseRealtimeClient.fromDescriptor(descriptor);
      await _realtime!.connect();
      final stream = _realtime!.subscribe('council:${widget.councilId}');
      _subscription = stream.listen(_onEvent);
    } catch (_) {
      // Realtime is not critical for this widget — silently no-op if the
      // descriptor / connection fails.
    }
  }

  void _onEvent(NormalizedRealtimeEvent event) {
    if (!mounted) return;
    final next = liveStatusFor(event);
    if (next == null) return;
    _autoClear?.cancel();
    setState(() => _status = next);
    if (next is RedTeamComplete) {
      // Auto-clear so the banner doesn't linger; the persisted
      // DeliberationRoundsCard takes over from here.
      _autoClear = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        setState(() => _status = null);
      });
    }
  }

  @override
  void dispose() {
    _autoClear?.cancel();
    _subscription?.cancel();
    _realtime?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();

    final (color, text) = switch (status) {
      RedTeamInProgress _ => (SynColors.red, 'Red team round in progress...'),
      RedTeamComplete s => (
        SynColors.red,
        'Red team complete: ${s.count} attack${s.count == 1 ? '' : 's'} recorded',
      ),
      DeliberationRound s => (
        SynColors.primary,
        'Deliberation round ${s.round} in progress...',
      ),
    };

    return Container(
      margin: const EdgeInsets.all(SynSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: SynSpacing.md,
        vertical: SynSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(SynRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }
}
