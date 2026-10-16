import '../../../core/i18n/i18n_provider.dart';
import '../branches_info_provider.dart' show branchesInfoDefaults;

/// CMS keys of the Pobočky texts that are app chrome (labels, buttons,
/// headings) → v2 app keys in 8 languages.
const Map<String, String> _chromeKeys = {
  'h1': 'v2BrH1',
  'branches.0.badge': 'v2BrBadgeStaffed',
  'branches.1.badge': 'v2BrBadgeSelf',
  'branches.0.steps_title': 'v2BrStepsTitle',
  'branches.1.steps_title': 'v2BrStepsTitle',
  'branches.0.video_title': 'v2BrVideoStaffed',
  'branches.1.video_title': 'v2BrVideoSelf',
  'cta.title': 'v2BrCtaTitle',
  'cta.text': 'v2BrCtaText',
  'cta.button': 'v2BrCtaButton',
  'detail_button': 'v2BrDetail',
};

/// The Pobočky texts (`branchesInfoProvider`, owner-editable in Velín) for
/// the v2 screens: in cs exactly as loaded; in another language a label /
/// button / heading that is still the built-in Czech default (CMS offline,
/// or no translation yet) is replaced by the app's own translation — never
/// Czech chrome in en / de… Edited CMS values and translations stay as they
/// are; long CMS texts keep the provider's fallback.
Map<String, String> v2BranchTexts(AppTranslations tr, Map<String, String> tx) {
  if (tr.lang == 'cs') return tx;
  final out = Map<String, String>.from(tx);
  _chromeKeys.forEach((cms, key) {
    final v = tx[cms];
    if (v == null || v.trim().isEmpty || v == branchesInfoDefaults[cms]) out[cms] = tr.tr(key);
  });
  return out;
}
