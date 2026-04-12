import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════
// MotoGo24 Design System — extracted pixel-perfect from Capacitor original
// Source: main.css :root variables + elements.css + screens.css
// ═══════════════════════════════════════════════════════════════════════

/// Color palette — every HEX from CSS --var() custom properties.
class MotoGoColors {
  MotoGoColors._();

  // ── Core brand ──
  static const Color green       = Color(0xFF74FB71); // --accent, .btn-g, calendar-avail
  static const Color greenDark   = Color(0xFF3DBA3A); // --accent-dark, links, active nav
  static const Color greenDarker = Color(0xFF1A8A18); // --accent-darker, info-banner text
  static const Color greenPale   = Color(0xFFE8FFE8); // --accent-pale, info-banner bg

  // ── Neutrals ──
  static const Color black = Color(0xFF0F1A14); // --black, body text
  static const Color dark  = Color(0xFF1A2E22); // --dark, headers, pricing table, toast bg
  static const Color white = Colors.white;

  // ── Gray scale (g = green-gray tints) ──
  static const Color g100 = Color(0xFFF1FAF7); // --g100, input fill, spec cell bg
  static const Color g200 = Color(0xFFD4E8E0); // --g200, borders, inactive chips
  static const Color g300 = Color(0xFFBDD9CE); // --g300, dividers
  static const Color g400 = Color(0xFF8AAB99); // --g400, secondary text, labels
  static const Color g500 = Color(0xFF6B8C7A); // --g500, placeholder text
  static const Color g600 = Color(0xFF4A6357); // --g600, description text

  // ── Backgrounds ──
  static const Color bg  = Color(0xFFDFF0EC); // --bg, scaffold background
  static const Color bg2 = Color(0xFFCDE8E2); // --bg2, secondary background

  // ── Semantic / status ──
  static const Color red    = Color(0xFFEF4444); // --red, cancel, SOS, errors
  static const Color redBg  = Color(0xFFFEE2E2); // storno bg, cancelled badge bg
  static const Color amber  = Color(0xFFD97706); // nadcházející status text
  static const Color amberBg   = Color(0xFFFEF3C7); // warning banner bg
  static const Color amberBorder = Color(0xFFFDE68A); // warning banner border

  // ── Calendar-specific ──
  static const Color calAvailable   = Color(0xFF1F3D2B); // available day cell
  static const Color calOccupied    = Color(0xFF1A2E22); // occupied day (= dark)
  static const Color calUnconfirmed = Color(0xFFD4E8E0); // unconfirmed (= g200)
  static const Color calToday       = Color(0xFF74FB71); // today border (= green)
  static const Color calRange       = Color(0x4074FB71); // selected range fill (green@25%)

  // ── Login gradient stops ──
  static const Color gradientTop = Color(0xFF0A1A10);
  static const Color gradientMid = Color(0xFF152A1C);
  static const Color gradientBot = Color(0xFF1A3524);
}

/// Spacing tokens — extracted from CSS padding/margin/gap values.
class MotoGoSpacing {
  MotoGoSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;
  static const double xxxl = 32.0;

  /// Standard screen horizontal padding.
  static const double screenH = 16.0;

  /// Card internal padding.
  static const double cardPad = 14.0;

  /// Section vertical gap.
  static const double sectionGap = 12.0;

  /// Form field vertical gap.
  static const double fieldGap = 10.0;
}

/// Border radius tokens — every radius used in the original CSS.
class MotoGoRadius {
  MotoGoRadius._();

  static const double xs   = 4.0;   // checkbox corners
  static const double sm   = 6.0;   // pricing table columns, spec badges
  static const double md   = 8.0;   // calendar day cells, small overlays
  static const double lg   = 10.0;  // back button, hamburger, time picker
  static const double xl   = 12.0;  // inputs, small cards, filter dropdowns
  static const double xxl  = 14.0;  // snackbar, reservation card, nav tab bg
  static const double card = 18.0;  // main cards, moto card, sections
  static const double hdr  = 24.0;  // header bottom corners
  static const double pill = 50.0;  // buttons, badges, chips (fully rounded)
  static const double login = 28.0; // login white card top corners
}

/// Shadow presets — extracted from CSS box-shadow declarations.
class MotoGoShadows {
  MotoGoShadows._();

  /// .bcard — main card shadow.
  static List<BoxShadow> card = [
    BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.08), blurRadius: 16),
  ];

  /// .bcard-sm — small card / inner section shadow.
  static List<BoxShadow> cardSmall = [
    BoxShadow(color: MotoGoColors.black.withValues(alpha: 0.06), blurRadius: 8),
  ];

  /// Moto card — slightly offset down.
  static List<BoxShadow> motoCard = [
    BoxShadow(
      color: MotoGoColors.black.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  /// Filter card — subtle with offset.
  static List<BoxShadow> filter = [
    BoxShadow(
      color: MotoGoColors.black.withValues(alpha: 0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// Sticky bottom bar — upward shadow.
  static List<BoxShadow> stickyBar = [
    BoxShadow(
      color: MotoGoColors.black.withValues(alpha: 0.1),
      blurRadius: 10,
      offset: const Offset(0, -4),
    ),
  ];
}

/// Gradient presets — extracted from CSS linear-gradient() declarations.
class MotoGoGradients {
  MotoGoGradients._();

  /// Login screen header gradient (top → bottom).
  static const LinearGradient loginHeader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      MotoGoColors.gradientTop, // #0A1A10
      MotoGoColors.gradientMid, // #152A1C
      MotoGoColors.gradientBot, // #1A3524
    ],
  );

  /// Image overlay gradient (transparent → black 85%).
  static LinearGradient imageOverlay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Colors.transparent,
      MotoGoColors.black.withValues(alpha: 0.85),
    ],
  );
}

/// Typography constants — Montserrat font family with exact CSS weights/sizes.
class MotoGoTypo {
  MotoGoTypo._();

  // ── Font weights used (CSS font-weight) ──
  static const FontWeight w500 = FontWeight.w500; // italic tagline
  static const FontWeight w600 = FontWeight.w600; // body, labels
  static const FontWeight w700 = FontWeight.w700; // bold labels, nav, badges
  static const FontWeight w800 = FontWeight.w800; // buttons, titles, section headers
  static const FontWeight w900 = FontWeight.w900; // hero titles, prices, main headings

  // ── Font sizes used (CSS font-size in px) ──
  static const double sizeXxs = 8.0;   // Kč/den tiny label
  static const double sizeXs  = 9.0;   // PŮJČOVNA MOTOREK, pilot label
  static const double sizeSm  = 10.0;  // version, tiny labels, spec keys
  static const double sizeMd  = 11.0;  // nav labels, form labels, secondary text
  static const double sizeBase = 12.0; // body, filter text, banner
  static const double sizeLg  = 13.0;  // description, section titles, buttons
  static const double sizeXl  = 14.0;  // card titles, month name, buttons
  static const double sizeXxl = 15.0;  // login button text
  static const double sizeH3  = 16.0;  // MOTO GO 24 logo text, section heads
  static const double sizeH2  = 18.0;  // moto detail name overlay
  static const double sizeH1  = 20.0;  // screen titles (Vyhledávání, etc.)
  static const double sizeHero = 22.0; // login heading, card price large
  static const double sizeLogo = 24.0; // MOTO GO 24 login
  static const double sizePrice = 28.0; // big price display

  // ── Letter spacing ──
  static const double lsNone   = 0.0;
  static const double lsTight  = -0.5;  // MOTO GO 24 header
  static const double lsNormal = 0.3;   // nav labels, badges
  static const double lsMedium = 0.5;   // buttons, form labels
  static const double lsWide   = 1.0;   // PŘIHLÁSIT SE
  static const double lsXwide  = 2.5;   // PŮJČOVNA MOTOREK
  static const double lsXxwide = 3.0;   // PŮJČOVNA MOTOREK login
}

/// Dimension constants — fixed sizes from CSS.
class MotoGoDimens {
  MotoGoDimens._();

  // ── Bottom navigation ── (120px logická = content + SafeArea bottom)
  static const double bnavHeight       = 80.0;  // .bnav content height (inside SafeArea)
  static const double bnavIconSize     = 26.0;  // nav icon size
  static const double bnavTabMarginH   = 4.0;   // horizontal margin per tab
  static const double bnavTabMarginV   = 6.0;   // vertical margin per tab
  static const double bnavBorderWidth  = 1.0;   // top border width

  // ── Header banner ──
  static const double bannerHeight     = 28.0;  // .header-banner height
  static const double bannerFontSize   = 12.0;

  // ── Buttons ──
  static const double btnPrimaryHeight = 52.0;  // .btn-g height
  static const double btnSecondaryHeight = 48.0; // secondary button height
  static const double btnBorderWidth   = 2.0;   // outlined button border

  // ── Back button ──
  static const double backBtnSize      = 36.0;  // .bk-c width/height
  static const double backBtnRadius    = 10.0;  // .bk-c border-radius

  // ── Hamburger menu button ──
  static const double menuBtnSize      = 40.0;  // hamburger button w/h
  static const double menuBtnRadius    = 12.0;

  // ── Logo ──
  static const double logoSmall        = 36.0;  // header logo (home)
  static const double logoLarge        = 80.0;  // login logo
  static const double logoRadius       = 20.0;  // login logo border-radius
  static const double logoSmallRadius  = 10.0;  // header logo border-radius

  // ── Image carousel ──
  static const double carouselHeight   = 260.0; // moto detail carousel
  static const double overlayHeight    = 100.0; // gradient overlay height

  // ── Cards ──
  static const double motoCardAspect   = 16.0 / 9.0; // image aspect ratio

  // ── Inputs ──
  static const double inputRadius      = 14.0;  // login inputs
  static const double inputBorder      = 1.5;   // default border width
  static const double inputFocusBorder = 2.0;   // focused border width

  // ── Calendar ──
  static const double calCellMargin    = 1.0;   // day cell margin
  static const double calCellRadius    = 8.0;   // day cell border-radius
  static const double calTodayBorder   = 2.0;   // today border width

  // ── Marquee animation ──
  static const Duration marqueeSpeed   = Duration(seconds: 18);
}

/// Complete Material theme — wires all tokens into Flutter ThemeData.
class MotoGoTheme {
  MotoGoTheme._();

  // Convenience aliases used across the app
  static const double radiusLg = MotoGoRadius.card;
  static const double radiusSm = MotoGoRadius.xl;

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.montserratTextTheme(base.textTheme);

    return base.copyWith(
      scaffoldBackgroundColor: MotoGoColors.bg,
      colorScheme: ColorScheme.dark(
        primary: MotoGoColors.green,
        onPrimary: MotoGoColors.black,
        secondary: MotoGoColors.greenDark,
        surface: MotoGoColors.bg,
        onSurface: MotoGoColors.black,
        error: MotoGoColors.red,
      ),
      textTheme: textTheme.apply(
        bodyColor: MotoGoColors.black,
        displayColor: MotoGoColors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: MotoGoColors.dark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 4,
        shadowColor: MotoGoColors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MotoGoColors.green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          minimumSize: const Size.fromHeight(MotoGoDimens.btnPrimaryHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MotoGoRadius.pill),
          ),
          textStyle: const TextStyle(
            fontWeight: MotoGoTypo.w800,
            fontSize: MotoGoTypo.sizeXl,
            letterSpacing: MotoGoTypo.lsMedium,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MotoGoColors.black,
          side: const BorderSide(color: MotoGoColors.g200, width: MotoGoDimens.btnBorderWidth),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: MotoGoColors.g100,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          borderSide: const BorderSide(color: MotoGoColors.g200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          borderSide: const BorderSide(color: MotoGoColors.g200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.xl),
          borderSide: const BorderSide(color: MotoGoColors.green, width: MotoGoDimens.inputFocusBorder),
        ),
        labelStyle: const TextStyle(
          fontSize: MotoGoTypo.sizeMd,
          fontWeight: MotoGoTypo.w600,
          color: MotoGoColors.g400,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: MotoGoColors.greenDark,
        unselectedItemColor: MotoGoColors.g400,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: MotoGoTypo.sizeMd,
          fontWeight: MotoGoTypo.w700,
          letterSpacing: MotoGoTypo.lsNormal,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: MotoGoTypo.sizeMd,
          fontWeight: MotoGoTypo.w700,
          letterSpacing: MotoGoTypo.lsNormal,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: MotoGoColors.dark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.xxl),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: MotoGoColors.g200,
        thickness: 1,
        space: 16,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: MotoGoColors.dark,
        headerForegroundColor: Colors.white,
        dayForegroundColor: WidgetStatePropertyAll(MotoGoColors.black),
        yearForegroundColor: WidgetStatePropertyAll(MotoGoColors.black),
        todayForegroundColor: WidgetStatePropertyAll(MotoGoColors.greenDark),
        todayBorder: const BorderSide(color: MotoGoColors.greenDark, width: 2),
        dayOverlayColor: WidgetStatePropertyAll(MotoGoColors.green.withValues(alpha: 0.15)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MotoGoRadius.card),
        ),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: MotoGoColors.dark,
          textStyle: const TextStyle(
            fontSize: MotoGoTypo.sizeXl,
            fontWeight: MotoGoTypo.w700,
          ),
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: MotoGoColors.greenDark,
          textStyle: const TextStyle(
            fontSize: MotoGoTypo.sizeXl,
            fontWeight: MotoGoTypo.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: MotoGoColors.dark,
        ),
      ),
    );
  }
}
