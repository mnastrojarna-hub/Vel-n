-- MotoGo24 — nové kategorie katalogu bodů zájmu pro cílovku (muži 40–50)
-- military (vojenství a opevnění), aviation (letectví), tech (technické
-- památky), moto (motorismus). Viz ANALYZA_CILOVKA_POI.md.
-- Část 2: reklasifikace bodů, které Wikidata import zařadil pod castle/sights,
-- protože specializované kategorie tehdy neexistovaly (bunkry = "Hrad či zámek").

-- 1) Rozšíření CHECK constraintu o nové kategorie
alter table public.points_of_interest
  drop constraint if exists points_of_interest_category_check;
alter table public.points_of_interest
  add constraint points_of_interest_category_check
  check (category in ('food','castle','lookout','water','sights','nature','other',
                      'military','aviation','tech','moto'));

-- 2) Reklasifikace existujících bodů dle názvu (bez zásahu do překladů)
-- 2a) military: bunkry, sruby, řopíky, čs. opevnění, vojenská muzea
update public.points_of_interest set category = 'military'
where category in ('castle','sights','other')
  and (name ~* '\mbunkr|\mbunker|řopík|pěchotní srub|dělostřeleck[áý]|minometn[áo]u?'
    or name ~* 'opevnění|opevnenie|fortifik|festung(swerk)?\M|fortyfikac'
    or name ~* 'vojensk|militar|militär|military|armádní|armadni'
    or name ~* 'atlantikwall|maginot|westwall|panzerwerk');

-- 2b) aviation: letecká muzea, letiště (v katalogu zatím jen pasivně)
update public.points_of_interest set category = 'aviation'
where category in ('castle','sights','other')
  and name ~* 'leteck[éý]|letiště|letisko|aviatik|aviation|luftfahrt|flugplatz|aérodrome|aerodrom';

-- 2c) tech: doly, hornická/železniční/technická muzea, elektrárny
update public.points_of_interest set category = 'tech'
where category in ('castle','sights','other')
  and (name ~* '\mdůl\M|\mdul\M|hornick|hornícke|štola|stollen|bergwerk|kopalnia'
    or name ~* 'technick[éá] (muzeum|múzeum|pamiatk)|eisenbahnmuseum|železničn[íé] muzeum'
    or name ~* 'elektrárn|elektráreň|kraftwerk|úzkokolejk|úzkokoľajk');

-- 2d) moto: závodní okruhy, moto/auto muzea, veterán galerie
update public.points_of_interest set category = 'moto'
where category in ('castle','sights','other')
  and (name ~* 'autodrom|závodní okruh|racing circuit|rennstrecke|circuit de'
    or name ~* 'moto(cyklov|rcycle|galerie)|automobilov[éá]|automuseum|veteran ar[eé]na|veterán');

-- 3) Komentář tabulky (dokumentace kategorií)
comment on column public.points_of_interest.category is
  'food/castle/lookout/water/sights/nature/other + cílovka: military/aviation/tech/moto';
