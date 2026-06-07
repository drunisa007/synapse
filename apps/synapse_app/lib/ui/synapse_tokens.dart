import 'package:flutter/material.dart';

abstract class SynSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract class SynRadii {
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double pill = 999;
}

abstract class SynColors {
  static const Color appBg = Color(0xFF0E1118);
  static const Color appBgAlt = Color(0xFF111520);
  static const Color chrome = Color(0xFF181B26);
  static const Color sidebar = Color(0xFF10141D);
  static const Color surface = Color(0xFF171B26);
  static const Color surfaceRaised = Color(0xFF1D2230);
  static const Color surfaceMuted = Color(0xFF121722);
  static const Color border = Color(0xFF2A3142);
  static const Color borderStrong = Color(0xFF3A4358);
  static const Color text = Color(0xFFF4F6FB);
  static const Color textMuted = Color(0xFF9EA7BA);
  static const Color textFaint = Color(0xFF667085);
  static const Color primary = Color(0xFF7C8CFF);
  static const Color primaryStrong = Color(0xFF6674E8);
  static const Color cyan = Color(0xFF38BDF8);
  static const Color green = Color(0xFF34D399);
  static const Color amber = Color(0xFFFBBF24);
  static const Color red = Color(0xFFF87171);
  static const Color magenta = Color(0xFFF472B6);
}

class SynStatusStyle {
  final String label;
  final Color color;
  final IconData icon;

  const SynStatusStyle({
    required this.label,
    required this.color,
    required this.icon,
  });
}

SynStatusStyle synStatusStyle(String status) {
  if (status == 'closed') {
    return const SynStatusStyle(
      label: 'Closed',
      color: SynColors.green,
      icon: Icons.check_circle_outline,
    );
  }
  if (status == 'failed') {
    return const SynStatusStyle(
      label: 'Failed',
      color: SynColors.red,
      icon: Icons.error_outline,
    );
  }
  if (status == 'pending_approval') {
    return const SynStatusStyle(
      label: 'Pending Approval',
      color: SynColors.amber,
      icon: Icons.rule_folder_outlined,
    );
  }
  if (status == 'waiting_contributions') {
    return const SynStatusStyle(
      label: 'Waiting Contributions',
      color: SynColors.magenta,
      icon: Icons.groups_2_outlined,
    );
  }
  if (status == 'scheduled') {
    return const SynStatusStyle(
      label: 'Scheduled',
      color: SynColors.cyan,
      icon: Icons.schedule,
    );
  }
  if (status == 'pending') {
    return const SynStatusStyle(
      label: 'Pending',
      color: SynColors.cyan,
      icon: Icons.pending_outlined,
    );
  }
  if (status.startsWith('stage_')) {
    final stage = status.split('_').last.toUpperCase();
    return SynStatusStyle(
      label: 'Stage $stage',
      color: SynColors.primary,
      icon: Icons.autorenew,
    );
  }
  return SynStatusStyle(
    label: status,
    color: SynColors.textMuted,
    icon: Icons.circle_outlined,
  );
}
