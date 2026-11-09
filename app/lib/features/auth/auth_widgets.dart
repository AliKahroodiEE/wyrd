import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import 'auth_gateway.dart';

/// Length of the one-time codes Auth emails (`auth.email.otp_length`).
const codeLength = 6;

/// [input] with Persian and Arabic-Indic digits turned into ASCII ones, so
/// codes typed on a Persian keyboard still verify.
String asciiDigits(String input) {
  final out = StringBuffer();
  for (final unit in input.runes) {
    if (unit >= 0x06F0 && unit <= 0x06F9) {
      out.writeCharCode(0x30 + unit - 0x06F0);
    } else if (unit >= 0x0660 && unit <= 0x0669) {
      out.writeCharCode(0x30 + unit - 0x0660);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString();
}

/// The one-time code inside pasted text such as "Your code: 123 456", or
/// null when there is none.
String? extractCode(String? text) {
  if (text == null) return null;
  final normalized = asciiDigits(text);
  final run = RegExp('(?<![0-9])[0-9]{$codeLength}(?![0-9])').firstMatch(normalized);
  if (run != null) return run.group(0);
  final digits = normalized.replaceAll(RegExp('[^0-9]'), '');
  return digits.length == codeLength ? digits : null;
}

/// A deliberately loose check; Auth has the final word.
bool isValidEmail(String email) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

/// `auth.minimum_password_length`.
const minPasswordLength = 8;

/// Mirrors `auth.password_requirements = "letters_digits"`, so a new
/// password is turned down before a round trip: at least
/// [minPasswordLength] characters with a Latin letter and a digit 0-9 (Auth
/// counts only those, not Persian letters or digits).
bool isAcceptablePassword(String password) =>
    password.length >= minPasswordLength && password.contains(RegExp('[A-Za-z]')) && password.contains(RegExp('[0-9]'));

/// Keeps a code field to [codeLength] ASCII digits and pulls the code out
/// of pasted text.
class CodeInputFormatter extends TextInputFormatter {
  const CodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final pasted = newValue.text.length - oldValue.text.length > 1 ? extractCode(newValue.text) : null;
    var digits = pasted ?? asciiDigits(newValue.text).replaceAll(RegExp('[^0-9]'), '');
    if (digits.length > codeLength) digits = digits.substring(0, codeLength);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// Emblem, headline and a line on why to sign in.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, this.body, this.icon = Icons.local_fire_department_rounded});

  final String title;
  final String? body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [p.glow, p.sunken]),
              border: Border.all(color: p.hairline),
              boxShadow: AppShadows.glow(p.accent, strength: p.isDark ? 0.22 : 0.14, blur: 22),
            ),
            child: Icon(icon, size: 34, color: p.accent),
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          header: true,
          child: Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            body!,
            style: text.bodyMedium?.copyWith(color: p.inkMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Status line under a form. Announced by screen readers when it changes.
class AuthMessage extends StatelessWidget {
  const AuthMessage({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = isError ? p.accent : p.success;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: AppRadius.softAll,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.mark_email_read_outlined, size: 18, color: color),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or" between the email form and the provider buttons.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(child: Divider(color: p.hairline)),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.md),
          child: Text(context.l10n.authOr, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: p.inkMuted)),
        ),
        Expanded(child: Divider(color: p.hairline)),
      ],
    );
  }
}

/// Outlined button for a sign-in with another account.
class ProviderButton extends StatelessWidget {
  const ProviderButton({super.key, required this.label, required this.mark, required this.onPressed});

  final String label;
  final Widget mark;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ExcludeSemantics(child: mark),
        const SizedBox(width: AppSpace.sm + 2),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// A provider's own mark, painted from its published vector so no image is
/// fetched: Google's four-colour G on a white disc, GitHub's Invertocat in
/// the text colour.
class ProviderLogo extends StatelessWidget {
  const ProviderLogo(this.provider, {super.key, this.size = 24});

  final SocialProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: switch (provider) {
        SocialProvider.google => const _GoogleMarkPainter(),
        SocialProvider.github => _GitHubMarkPainter(context.palette.ink),
      },
    ),
  );
}

class _GoogleMarkPainter extends CustomPainter {
  const _GoogleMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawCircle(size.center(Offset.zero), side / 2, Paint()..color = const Color(0xFFFFFFFF));
    final g = side * 0.62;
    canvas
      ..save()
      ..translate((size.width - g) / 2, (size.height - g) / 2)
      ..scale(g / 48);
    for (final (color, path) in _googleG) {
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleMarkPainter oldDelegate) => false;
}

class _GitHubMarkPainter extends CustomPainter {
  const _GitHubMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.shortestSide / 16);
    canvas.drawPath(_githubMark, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GitHubMarkPainter oldDelegate) => oldDelegate.color != color;
}

/// Google's "G" (48 × 48), from its Sign in with Google button.
final _googleG = <(Color, Path)>[
  (
    const Color(0xFFEA4335),
    Path()
      ..moveTo(24, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
      ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
      ..lineTo(10.54, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
      ..close(),
  ),
  (
    const Color(0xFF4285F4),
    Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
      ..lineTo(24, 20)
      ..lineTo(24, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close(),
  ),
  (
    const Color(0xFFFBBC05),
    Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
      ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
      ..lineTo(2.55, 13.22)
      ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
      ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
      ..lineTo(10.53, 28.59)
      ..close(),
  ),
  (
    const Color(0xFF34A853),
    Path()
      ..moveTo(24, 48)
      ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
      ..lineTo(32.16, 36.19)
      ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
      ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
      ..lineTo(2.55, 34.77)
      ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
      ..close(),
  ),
];

/// GitHub's mark (16 × 16), from Octicons' mark-github.
final _githubMark = Path()
  ..fillType = PathFillType.evenOdd
  ..moveTo(8, 0)
  ..cubicTo(3.58, 0, 0, 3.58, 0, 8)
  ..cubicTo(0, 11.54, 2.29, 14.53, 5.47, 15.59)
  ..cubicTo(5.87, 15.66, 6.02, 15.42, 6.02, 15.21)
  ..cubicTo(6.02, 15.02, 6.01, 14.39, 6.01, 13.72)
  ..cubicTo(4, 14.09, 3.48, 13.23, 3.32, 12.78)
  ..cubicTo(3.23, 12.55, 2.84, 11.84, 2.5, 11.65)
  ..cubicTo(2.22, 11.5, 1.82, 11.13, 2.49, 11.12)
  ..cubicTo(3.12, 11.11, 3.57, 11.7, 3.72, 11.94)
  ..cubicTo(4.44, 13.15, 5.59, 12.81, 6.05, 12.6)
  ..cubicTo(6.12, 12.08, 6.33, 11.73, 6.56, 11.53)
  ..cubicTo(4.78, 11.33, 2.92, 10.64, 2.92, 7.58)
  ..cubicTo(2.92, 6.71, 3.23, 5.99, 3.74, 5.43)
  ..cubicTo(3.66, 5.23, 3.38, 4.41, 3.82, 3.31)
  ..cubicTo(3.82, 3.31, 4.49, 3.1, 6.02, 4.13)
  ..cubicTo(6.66, 3.95, 7.34, 3.86, 8.02, 3.86)
  ..cubicTo(8.7, 3.86, 9.38, 3.95, 10.02, 4.13)
  ..cubicTo(11.55, 3.09, 12.22, 3.31, 12.22, 3.31)
  ..cubicTo(12.66, 4.41, 12.38, 5.23, 12.3, 5.43)
  ..cubicTo(12.81, 5.99, 13.12, 6.7, 13.12, 7.58)
  ..cubicTo(13.12, 10.65, 11.25, 11.33, 9.47, 11.53)
  ..cubicTo(9.76, 11.78, 10.01, 12.26, 10.01, 13.01)
  ..cubicTo(10.01, 14.08, 10, 14.94, 10, 15.21)
  ..cubicTo(10, 15.42, 10.15, 15.67, 10.55, 15.59)
  ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(8.013))
  ..cubicTo(16, 3.58, 12.42, 0, 8, 0)
  ..close();

/// Password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  /// Hints password managers to suggest a new password instead of filling
  /// the saved one.
  final bool newPassword;
  final VoidCallback? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
      textDirection: TextDirection.ltr,
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        suffixIcon: IconButton(
          tooltip: _visible ? l10n.authHidePassword : l10n.authShowPassword,
          icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

/// Email address field.
class EmailField extends StatelessWidget {
  const EmailField({super.key, required this.controller, this.autofocus = false, this.onSubmitted});

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    keyboardType: TextInputType.emailAddress,
    autofillHints: const [AutofillHints.email, AutofillHints.username],
    autocorrect: false,
    enableSuggestions: false,
    textDirection: TextDirection.ltr,
    textInputAction: onSubmitted == null ? TextInputAction.next : TextInputAction.go,
    onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    decoration: InputDecoration(
      labelText: context.l10n.authEmail,
      prefixIcon: const Icon(Icons.alternate_email_rounded),
    ),
  );
}

/// The 6-digit code: one wide field so paste, the keyboard's code
/// suggestion and screen readers all work as usual. Verifies itself when
/// the last digit lands.
class CodeField extends StatelessWidget {
  const CodeField({super.key, required this.controller, required this.onCompleted, this.enabled = true});

  final TextEditingController controller;
  final VoidCallback onCompleted;
  final bool enabled;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final code = extractCode(data?.text);
    if (code == null) return;
    controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final style = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontFamily: 'Inter',
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 10,
      fontWeight: FontWeight.w600,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: const [CodeInputFormatter()],
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      textInputAction: TextInputAction.done,
      style: style,
      onChanged: (v) {
        if (v.length == codeLength) onCompleted();
      },
      onSubmitted: (_) => onCompleted(),
      decoration: InputDecoration(
        labelText: l10n.authCodeLabel,
        hintText: '••••••',
        floatingLabelAlignment: FloatingLabelAlignment.center,
        contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpace.xxxl, vertical: AppSpace.lg),
        suffixIcon: IconButton(
          tooltip: l10n.authPasteCode,
          icon: const Icon(Icons.content_paste_rounded),
          onPressed: enabled ? _paste : null,
        ),
      ),
    );
  }
}
