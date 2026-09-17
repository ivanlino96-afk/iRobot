import 'package:flutter/material.dart';

/// Canonical software-stop disclaimer, shown wherever a stop/disarm control
/// could be mistaken for cutting power to the servos.
class SafetyNotice extends StatelessWidget {
  const SafetyNotice({super.key, this.style, this.textAlign});
  final TextStyle? style;
  final TextAlign? textAlign;

  static const text =
      'Parada por software. No corta la alimentación de los servos.';

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: textAlign,
    style: style ?? Theme.of(context).textTheme.bodySmall,
  );
}
