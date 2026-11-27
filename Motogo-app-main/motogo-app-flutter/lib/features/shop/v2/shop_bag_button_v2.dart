import 'package:flutter/material.dart';

import '../../../core/i18n/i18n_provider.dart';
import '../../../core/v2/icons/mg_icon.dart';
import '../../../core/v2/motion/mg_anim.dart';
import '../../../core/v2/widgets/mg_buttons.dart';

/// Bag button of the v2 shop: 44 disc + count badge that bumps when the
/// count rises (PS-20); tap = the screen's own cart route. In the dark app
/// bar by default; [photo] = the over-photo disc of a full-screen product
/// card (the same action while the header is scrolled away).
class ShopBagButtonV2 extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final bool photo;
  const ShopBagButtonV2({super.key, required this.count, required this.onTap, this.photo = false});

  @override
  Widget build(BuildContext context) => MgBump(
        trigger: count,
        child: MgIconButton(
          key: photo ? null : const ValueKey('shop-v2-bag'),
          icon: MgIcons.bag,
          badge: count,
          onTap: onTap,
          style: photo ? MgIconButtonStyle.photo : MgIconButtonStyle.dark,
          semanticLabel: '${t(context).tr('cartTitle')}${count > 0 ? ', $count' : ''}',
        ),
      );
}
