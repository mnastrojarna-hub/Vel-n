/// v2 spacing, radii and component sizes (PLAN §1.2).
abstract final class MgSpace {
  static const double s2 = 2, s4 = 4, s6 = 6, s8 = 8, s10 = 10, s12 = 12;
  static const double s16 = 16, s20 = 20, s24 = 24, s32 = 32, s40 = 40;
  static const double gutter = 16;
  static const double section = 24;
  static const double card = 16;

  /// Dark hero padding (vertical / horizontal).
  static const double heroV = 20, heroH = 16;
}

abstract final class MgRadius {
  static const double tag = 6;
  static const double mapChip = 8;
  static const double thumb = 10;
  static const double day = 11;
  static const double action = 12;
  static const double button = 14;
  static const double card = 16;
  static const double receipt = 18;
  static const double hero = 20;
  static const double sheet = 22;
  static const double header = 24;
  static const double pill = 999;
}

abstract final class MgSize {
  static const double touch = 44;
  static const double hit = 48;
  static const double chip = 40;
  static const double choiceChip = 44;
  static const double button = 52;
  static const double cta = 56;
  static const double ctaSticky = 60;
  static const double nav = 64;
  static const double dock = 72;
  static const double fab = 56;
  static const double fabMini = 44;
  static const double strip = 52;
}
