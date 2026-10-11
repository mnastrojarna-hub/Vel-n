import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/web_links.dart';
import '../../../core/i18n/app_lang.dart';
import '../../../core/i18n/i18n_provider.dart' show lastKnownAppLang;
import '../../../core/widgets/logo_header.dart' show appVersion;

/// Footer widget for the login screen: phone, website link, and app version.
class LoginFooter extends StatelessWidget {
  const LoginFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.phone, size: 14, color: MotoGoColors.g400),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('tel:+420774256271')),
                child: const Text(
                  '+420 774 256 271',
                  style: TextStyle(
                    fontSize: 12,
                    color: MotoGoColors.g400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(
                '  ·  ',
                style: TextStyle(fontSize: 12, color: MotoGoColors.g400),
              ),
              GestureDetector(
                // Web v jazyce appky (doména dle jazyka, uk = .com?lang=uk).
                onTap: () => launchUrl(Uri.parse(WebLinks.home(normalizeAppLang(
                    Localizations.maybeLocaleOf(context)?.languageCode ??
                        lastKnownAppLang)))),
                child: const Text(
                  'motogo24.CZ',
                  style: TextStyle(
                    fontSize: 12,
                    color: MotoGoColors.greenDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            appVersion,
            style: TextStyle(
              fontSize: 11,
              color: MotoGoColors.g400,
            ),
          ),
        ],
      ),
    );
  }
}
