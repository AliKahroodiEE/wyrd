import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/config.dart';
import '../../design/tokens.dart';

/// "Privacy · Terms": the policy pages the web app ships (app/web).
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = context.palette;
    final style = Theme.of(context).textTheme.bodySmall;
    Widget link(String label, String page) => TextButton(
      style: TextButton.styleFrom(foregroundColor: p.inkMuted, textStyle: style),
      onPressed: () => launchUrl(SiteConfig.page(page)),
      child: Text(label),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        link(l10n.legalPrivacy, 'privacy'),
        Text('·', style: style?.copyWith(color: p.inkMuted)),
        link(l10n.legalTerms, 'terms'),
      ],
    );
  }
}
