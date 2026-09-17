import 'package:flutter/material.dart';

/// Semantic colors shared across the app so a single source of truth
/// replaces the ad hoc hex literals scattered through the presentation
/// layer. Alarm colors (success/warning/danger) keep the same hue in both
/// brightness variants, per ISA-101 guidance, so their meaning doesn't
/// change when the operator switches theme.
class AirobotTokens extends ThemeExtension<AirobotTokens> {
  const AirobotTokens({
    required this.ink,
    required this.muted,
    required this.surfaceMuted,
    required this.cardBorder,
    required this.success,
    required this.warning,
    required this.danger,
    required this.axisX,
    required this.axisY,
    required this.axisZ,
    required this.axisGripper,
  });

  final Color ink;
  final Color muted;
  final Color surfaceMuted;
  final Color cardBorder;
  final Color success;
  final Color warning;
  final Color danger;
  final Color axisX;
  final Color axisY;
  final Color axisZ;
  final Color axisGripper;

  static const light = AirobotTokens(
    ink: Color(0xff17233b),
    muted: Color(0xff718096),
    surfaceMuted: Color(0xfff8fafc),
    cardBorder: Color(0xffe7ebf3),
    success: Color(0xff1e8e3e),
    warning: Color(0xfff59e0b),
    danger: Color(0xffb4233c),
    axisX: Color(0xff38bdf8),
    axisY: Color(0xff34d399),
    axisZ: Color(0xffa78bfa),
    axisGripper: Color(0xfff59e0b),
  );

  static const dark = AirobotTokens(
    ink: Color(0xffe5e9f0),
    muted: Color(0xff9aa5b8),
    surfaceMuted: Color(0xff1c2230),
    cardBorder: Color(0xff2a3242),
    success: Color(0xff1e8e3e),
    warning: Color(0xfff59e0b),
    danger: Color(0xffb4233c),
    axisX: Color(0xff38bdf8),
    axisY: Color(0xff34d399),
    axisZ: Color(0xffa78bfa),
    axisGripper: Color(0xfff59e0b),
  );

  @override
  AirobotTokens copyWith({
    Color? ink,
    Color? muted,
    Color? surfaceMuted,
    Color? cardBorder,
    Color? success,
    Color? warning,
    Color? danger,
    Color? axisX,
    Color? axisY,
    Color? axisZ,
    Color? axisGripper,
  }) => AirobotTokens(
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    cardBorder: cardBorder ?? this.cardBorder,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    axisX: axisX ?? this.axisX,
    axisY: axisY ?? this.axisY,
    axisZ: axisZ ?? this.axisZ,
    axisGripper: axisGripper ?? this.axisGripper,
  );

  @override
  AirobotTokens lerp(ThemeExtension<AirobotTokens>? other, double t) =>
      t < 0.5 ? this : (other is AirobotTokens ? other : this);
}

extension AirobotTokensContext on BuildContext {
  AirobotTokens get tokens =>
      Theme.of(this).extension<AirobotTokens>() ?? AirobotTokens.light;
}
