import 'package:flutter/material.dart';

import '../core/api/models.dart';

/// Type-ahead picker shown above the chat-input TextField when the user
/// types an `@partial` token. Mirrors the Svelte `MentionPicker.svelte`
/// component shipped in async-councils Slice 3b — same behaviour, same
/// row shape (workspace users first, "invite by email" tail row when
/// the query parses as an address).
///
/// Pure presentational + selection-callback widget. The parent owns the
/// fetched user list + the active query string, and debounces the
/// workspace-users lookup so we don't hammer the backend on each
/// keystroke.
class MentionPicker extends StatelessWidget {
  /// Current `@partial` query — drives the "invite by email" fallback
  /// row and is echoed in the empty-state hint.
  final String query;

  /// Pre-fetched workspace users (filtered server-side via the `q`
  /// param). Empty list is fine — the picker will still render the
  /// invite-by-email row when the query looks like an address.
  final List<WorkspaceUser> users;

  /// Spinner indicator — drawn in the header while a fetch is in flight.
  final bool loading;

  /// Called with the chosen human (workspace OR invite variant). The
  /// parent is responsible for inserting a chip + dismissing the picker.
  final void Function(PendingHuman) onSelect;

  const MentionPicker({
    super.key,
    required this.query,
    required this.users,
    required this.onSelect,
    this.loading = false,
  });

  // Sloppy on purpose. The picker only needs to know whether to offer
  // an invite-by-email row; the backend re-validates strictly via
  // `Synapse.Schemas.CouncilInvitation.changeset`.
  static final _emailLike = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  Widget build(BuildContext context) {
    final trimmed = query.trim();
    final inviteAvailable = _emailLike.hasMatch(trimmed);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Add human',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                if (loading) ...const [
                  Spacer(),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white38),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          if (users.isEmpty && !inviteAvailable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                trimmed.isEmpty
                    ? 'Type a name to search workspace users'
                    : 'No match. Type a full email address to invite externally.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in users)
                    _UserRow(user: u, onTap: () => _pickUser(u)),
                  if (inviteAvailable)
                    _InviteRow(
                      email: trimmed,
                      onTap: () => _pickInvite(trimmed),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _pickUser(WorkspaceUser u) {
    onSelect(PendingHumanWorkspace(name: u.displayName, sub: u.id));
  }

  void _pickInvite(String email) {
    // Local-part of the email is a sensible default display name. Better
    // than blank; users mostly recognise colleagues by handle anyway.
    final name = email.contains('@') ? email.split('@').first : email;
    onSelect(PendingHumanInvite(name: name, email: email));
  }
}

class _UserRow extends StatelessWidget {
  final WorkspaceUser user;
  final VoidCallback onTap;

  const _UserRow({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '@${user.displayName}',
              style: const TextStyle(
                color: Color(0xFFE4E4E7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              user.id,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  final String email;
  final VoidCallback onTap;

  const _InviteRow({required this.email, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.mail_outline, size: 14, color: Color(0xFF818CF8)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite $email',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE4E4E7),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Text(
                    'Sends a magic-link email',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
