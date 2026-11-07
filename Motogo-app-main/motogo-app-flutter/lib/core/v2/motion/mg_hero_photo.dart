import 'package:flutter/material.dart';

import 'mg_motion.dart';

/// Shared-element photo (design M1, V2 §5.3 / §5.11 / §6.3): the catalog
/// card / Home funnel photo flies into the bike detail hero, the Home ticket
/// / reservation card photo into the reservation detail — radius 16 → 0
/// during the flight, also on the iOS edge-swipe back. Only inside the shell
/// navigator, never into /success, ONE tagged source per route (tests:
/// `expectUniqueHeroTags`). Off under reduced motion or when ![enabled].
class MgHeroPhoto extends StatelessWidget {
  final Object tag;
  final Widget child;
  final bool enabled;
  const MgHeroPhoto({super.key, required this.tag, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled || MgMotion.reduced(context)) return child;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: mgHeroShuttle,
      child: child,
    );
  }
}

/// Flight look: the destination photo (as the default shuttle) clipped
/// r16 → r0 as it lands (r0 → r16 on the way back).
Widget mgHeroShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromContext,
  BuildContext toContext,
) {
  final to = (toContext.widget as Hero).child;
  return AnimatedBuilder(
    animation: animation,
    builder: (_, child) => ClipRRect(
      borderRadius: BorderRadius.circular(16 * (1 - MgMotion.emphasized.transform(animation.value))),
      child: child,
    ),
    child: to,
  );
}

/// Hero tag of a bike photo (catalog card / Home funnel → bike detail).
String mgHeroTagMoto(Object id) => 'moto-img-$id';

/// Hero tag of a reservation photo (Home ticket / list card → detail).
String mgHeroTagRes(Object id) => 'res-img-$id';
