import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';
import 'tokens.dart';

/// Lebanese phone field with a fixed +961 prefix (LTR even in Arabic).
class MkPhoneField extends StatelessWidget {
  const MkPhoneField({required this.controller, this.onSubmitted, this.autofocus = true, this.hint, super.key});

  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.done,
        onSubmitted: onSubmitted,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        style: t.titleLarge?.copyWith(letterSpacing: 1.2),
        decoration: InputDecoration(
          hintText: hint ?? '70 123 456',
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LebanonFlag(),
                const SizedBox(width: 8),
                Text('+961', style: t.titleMedium),
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: MkColors.line),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Lebanese flag, drawn (red, white, red, with a green cedar).
class _LebanonFlag extends StatelessWidget {
  const _LebanonFlag();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 24,
        height: 16,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Column(
              children: [
                Expanded(child: ColoredBox(color: Color(0xFFE62E2E), child: SizedBox.expand())),
                Expanded(flex: 2, child: ColoredBox(color: Colors.white, child: SizedBox.expand())),
                Expanded(child: ColoredBox(color: Color(0xFFE62E2E), child: SizedBox.expand())),
              ],
            ),
            Transform.rotate(
              angle: 0.785,
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: const Color(0xFF1C8C3B), borderRadius: BorderRadius.circular(1))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Six-box OTP input backed by one hidden text field (supports paste/autofill).
class MkOtpField extends StatefulWidget {
  const MkOtpField({required this.onCompleted, this.length = 6, this.error = false, super.key});

  final ValueChanged<String> onCompleted;
  final int length;
  final bool error;

  @override
  State<MkOtpField> createState() => MkOtpFieldState();
}

class MkOtpFieldState extends State<MkOtpField> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  void clear() {
    _c.clear();
    setState(() {});
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final text = _c.text;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.length)],
              onChanged: (v) {
                setState(() {});
                if (v.length == widget.length) widget.onCompleted(v);
              },
            ),
          ),
          GestureDetector(
            onTap: () => _focus.requestFocus(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(widget.length, (i) {
                final filled = i < text.length;
                final active = i == text.length && _focus.hasFocus;
                final color = widget.error
                    ? MkColors.danger
                    : active
                        ? MkColors.purple700
                        : filled
                            ? MkColors.purple900
                            : MkColors.line;
                return AnimatedContainer(
                  duration: MkMotion.fast,
                  width: 48,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filled ? MkColors.yellow50 : MkColors.surface,
                    borderRadius: MkRadius.all(MkRadius.md),
                    border: Border.all(color: color, width: active || widget.error ? 2 : 1.3),
                  ),
                  child: AnimatedScale(
                    scale: filled ? 1 : 0.6,
                    duration: MkMotion.fast,
                    child: Text(filled ? text[i] : '', style: t.headlineSmall),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Numeric keypad for PIN entry and counter amounts on touch screens.
class MkKeypad extends StatelessWidget {
  const MkKeypad({required this.onKey, this.onBackspace, this.extraKey, super.key});

  final ValueChanged<String> onKey;
  final VoidCallback? onBackspace;

  /// Optional key in the bottom-left slot (for example "." for amounts).
  final String? extraKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: MkPressable(
              onTap: onTap,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: onTap == null ? Colors.transparent : MkColors.surface,
                  borderRadius: MkRadius.all(MkRadius.md),
                  border: onTap == null ? null : Border.all(color: MkColors.line),
                ),
                child: child ?? Text(label, style: t.headlineSmall),
              ),
            ),
          ),
        );
    Widget row(List<String> ks) => Row(children: [for (final k in ks) key(k, onTap: () => onKey(k))]);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(['1', '2', '3']),
          row(['4', '5', '6']),
          row(['7', '8', '9']),
          Row(
            children: [
              extraKey == null ? key('') : key(extraKey!, onTap: () => onKey(extraKey!)),
              key('0', onTap: () => onKey('0')),
              key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, color: MkColors.ink2)),
            ],
          ),
        ],
      ),
    );
  }
}

/// PIN dots.
class MkPinDots extends StatelessWidget {
  const MkPinDots({required this.length, required this.filled, this.error = false, super.key});

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: MkMotion.fast,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: on ? 18 : 14,
          height: on ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error ? MkColors.danger : (on ? MkColors.purple900 : MkColors.line),
          ),
        );
      }),
    );
  }
}
