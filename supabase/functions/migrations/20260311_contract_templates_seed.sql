-- ============================================================================
-- SEED: Smluvní texty do document_templates (VOP, Smlouva, Předávací protokol)
-- Datum: 2026-03-11
-- ============================================================================

-- 1. VOP (Obchodní podmínky)
INSERT INTO public.document_templates (name, type, content_html, version)
VALUES (
  'Obchodní podmínky (VOP)',
  'vop',
  '<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>Obchodní podmínky – MotoGo24</title>
<style>
body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:13px;line-height:1.6}
.wrap{max-width:780px;margin:0 auto;padding:32px}
h1{text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px;margin-bottom:24px}
h2{font-size:14px;margin:20px 0 8px;color:#1a8a18}
ol{padding-left:20px} ol ol{list-style-type:lower-alpha} ol ol ol{list-style-type:lower-roman}
li{margin-bottom:4px}
.footer{margin-top:40px;text-align:center;font-size:11px;color:#888;border-top:1px solid #ddd;padding-top:16px}
</style></head>
<body><div class="wrap">
<h1>Obchodní podmínky</h1>
<p>Tyto všeobecné obchodní podmínky (Dále jen VOP) upravují podmínky nájmu motocyklů mezi společností Petra Semorádová (dále jen pronajímatel) a zákazníkem (dále jen nájemce).</p>

<h2>1. Předmět nájmu</h2>
<ol type="a">
<li>Předmětem nájmu je motocykl specifikovaný v nájemní smlouvě.</li>
<li>Spolu s předmětem nájmu jsou součástí nájmu vždy také klíče, zelená karta, malý technický průkaz, 2x reflexní vesta, motolékárnička, záznam o dopravní nehodě, kukla a případně další vybavení specifikované v Předávacím protokolu, který je součástí nájemní smlouvy.</li>
</ol>

<h2>2. Podmínky užívání</h2>
<ol type="a">
<li>Nájemce se zavazuje užívat předmět nájmu řádně, v souladu s platnými právními předpisy ČR a pokyny pronajímatele.</li>
<li>Nájemce se zavazuje dodržovat pravidla silničního provozu, používat předepsané ochranné pomůcky a přizpůsobit jízdu aktuálním podmínkám. Pronajímatel doporučuje používat přilbu, reflexní prvky a chránit se před nepříznivým počasím.</li>
<li>Nájemce je povinen seznámit se při převzetí předmětu nájmu s jeho technickým stavem a obsluhou a zkontrolovat převzatou výbavu.</li>
<li>Předmět nájmu nesmí být používán k:
<ol type="i">
<li>účasti na závodech, soutěžích nebo jiných extrémních aktivitách,</li>
<li>přepravě nebezpečných látek nebo nadměrného nákladu,</li>
<li>řízení pod vlivem alkoholu, drog či jiných omamných látek,</li>
<li>pronájmu (zapůjčení) dalším osobám.</li>
</ol></li>
<li>Předmět nájmu a jeho příslušenství je zakázáno jakkoli upravovat, vyměňovat díly a zasahovat do jeho technického stavu.</li>
<li>Nájemce je povinen zdržet se jakéhokoli zásahu do technického stavu předmětu nájmu či jeho příslušenství, zejména:
<ol type="i">
<li>manipulace s tachometrem či jeho odpojení,</li>
<li>resetování chybových hlášení,</li>
<li>úpravy řídicí jednotky,</li>
<li>zásahy do elektroinstalace,</li>
<li>úpravy provedené za účelem zatajení najetých kilometrů nebo technického stavu,</li>
<li>zásahy do GPS jednotky, pokud je motocykl vybaven sledovacím systémem.</li>
</ol></li>
<li>Nájemce nesmí zakrývat, odstranit ani jinak ztěžovat funkčnost případného lokalizačního zařízení.</li>
<li>Porušení tohoto ustanovení zakládá povinnost nájemce uhradit pronajímateli smluvní pokutu ve výši 20 000 Kč, a zároveň hradit škodu v plném rozsahu.</li>
<li>V případě důvodného podezření na manipulaci je pronajímatel oprávněn:
<ol type="i">
<li>provést kontrolu předmětu nájmu,</li>
<li>jednostranně ukončit nájemní smlouvu,</li>
<li>požadovat okamžité vrácení předmětu nájmu.</li>
</ol></li>
<li>Nájemce je povinen po celou dobu nájmu kontrolovat stav provozních kapalin (např. motorový olej, chladicí kapalinu, brzdovou kapalinu) a v případě potřeby je doplnit, aby nedošlo k poškození předmětu nájmu. Náklady na doplnění těchto kapalin (s výjimkou pohonných hmot, které hradí nájemce vždy) mohou být nájemci proplaceny pouze po předchozím odsouhlasení pronajímatelem a předložením platného daňového dokladu. Bez tohoto odsouhlasení a dokladu nárok na proplacení nevzniká. Nedoplní-li nájemce provozní kapaliny a tím způsobí škodu, odpovídá za tuto škodu v plné výši.</li>
<li>Předmět nájmu smí řídit pouze osoba uvedená ve smlouvě, s platným řidičským oprávněním odpovídající skupiny.</li>
<li>Nájemce odpovídá za škody způsobené nevhodným užíváním, nedbalostí či porušením podmínek uvedených ve smlouvě o pronájmu.</li>
<li>Předmět nájmu je možné užívat i mimo ČR, a to v rámci států uvedených na platné zelené kartě (mezinárodní karta pojištění odpovědnosti z provozu vozidla). Nájemce je povinen se před cestou do zahraničí seznámit se seznamem těchto států a řídit se jím. Doporučuje se o zamýšlené cestě informovat pronajímatele při převzetí vozidla. Při cestě do zahraničí s sebou nájemce musí mít kopii nájemní smlouvy.</li>
</ol>

<h2>3. Doba nájmu</h2>
<ol type="a">
<li>Doba nájmu je doba, po kterou má nájemce předmět nájmu fyzicky užívat. Začíná převzetím předmětu nájmu nájemcem a končí jeho vrácením pronajímateli v souladu s nájemní smlouvou.</li>
<li>Nájemce je povinen vrátit pronajímateli předmět nájmu včetně pronajatého příslušenství nepoškozené, ve sjednaném termínu a ve stavu odpovídajícím běžnému opotřebení.</li>
<li>Požaduje-li nájemce přistavení předmětu nájmu na jinou adresu, než je provozovna pronajímatele, a je toto přistavení výslovně sjednáno v nájemní smlouvě, nájemní doba začíná běžet až v okamžiku, kdy si nájemce motocykl skutečně převezme.</li>
<li>Pokud nájemce nevrátí předmět nájmu ve sjednaný den vrácení (tj. do 24:00 daného dne), je povinen uhradit:
<ol type="i">
<li>výši půjčovného za každý další započatý den, ve kterém má předmět nájmu v držení, a</li>
<li>smluvní poplatek za pozdní vrácení ve výši 500 Kč za každou další započatou hodinu nad rámec sjednané doby nájmu. Tento poplatek se účtuje vedle běžného denního nájemného a nezávisle na něm. Obě částky budou nájemci zúčtovány formou dodatečného daňového dokladu (faktury), která mu bude zaslána e-mailem na kontaktní adresu uvedenou ve smlouvě. Faktura bude mít splatnost 7 dní ode dne vystavení. Nájemné za dobu prodlouženého užívání, poplatek za pozdní vrácení a případná náhrada škody (včetně ušlého zisku) představují tři samostatné a na sobě nezávislé nároky, z nichž každý sleduje jiný účel; jejich současné uplatnění proto nepředstavuje nepřiměřenou sankci ani dvojí postih.</li>
</ol></li>
</ol>

<h2>4. Rezervace a storno</h2>
<ol type="a">
<li>Rezervace motocyklu je možná telefonicky, prostřednictvím rezervačního systému na webových stránkách, e-mailem nebo přes sociální sítě motopůjčovny.</li>
<li>Rezervace je závazná ve chvíli, kdy je potvrzena oběma stranami.</li>
<li>Zrušení rezervace je možné bez sankce nejpozději 48 hodin před sjednaným termínem převzetí předmětu nájmu.</li>
<li>V případě zrušení rezervace méně než 48 hodin před dohodnutým termínem výpůjčky si pronajímatel vyhrazuje právo účtovat storno poplatek až do výše 50 % sjednaného nájemného.</li>
<li>Pokud si nájemce předmět nájmu v dohodnutém termínu nepřevezme bez předchozího zrušení rezervace, má pronajímatel právo účtovat plnou výši sjednaného nájemného za celou rezervovanou dobu nájmu.</li>
<li>V případě účtování storno poplatku nebo náhrady škody v souladu s těmito podmínkami bude nájemci vystavena faktura, splatná do 7 dní od jejího vystavení, pokud není dohodnuto jinak. Úhrada probíhá bezhotovostně převodem na účet pronajímatele, který bude uveden na faktuře.</li>
<li>V případě, že nájemce vrátí motocykl pozdě nebo v nepojízdném stavu v důsledku porušení svých povinností a tím znemožní předání dalšímu zákazníkovi, odpovídá za škodu vzniklou pronajímateli z titulu zmařené rezervace.</li>
<li>Škoda zahrnuje zejména:
<ol type="i">
<li>refundace dalšímu zákazníkovi;</li>
<li>ušlé nájemné z navazující rezervace (Ušlým nájemným se rozumí nájemné z potvrzené rezervace jiného zákazníka, kterou nebylo možné realizovat z důvodu pozdního vrácení či nepojízdného stavu. Výše škody bude doložena potvrzením o existující rezervaci.);</li>
<li>přímé náklady spojené se situací (doprava, přesun stroje apod.).</li>
</ol></li>
<li>Škoda bude nájemci vyúčtována formou daňového dokladu se splatností 7 dnů.</li>
</ol>

<h2>5. Platby a kauce</h2>
<ol type="a">
<li>Cena za nájem motocyklu se řídí aktuálním ceníkem pronajímatele zveřejněným na jeho webových stránkách. Pro daný nájem je závazná cena platná ke dni uzavření nájemní smlouvy.</li>
<li>Úhrada nájmu se provádí bezhotovostním převodem na bankovní účet pronajímatele 670100-2225851630/6210 dle platebních instrukcí, které nájemce obdrží e-mailem po odeslání rezervačního formuláře. Splatnost nájemného je uvedena v nájemní smlouvě. Neuhradí-li nájemce nájemné ve stanoveném termínu, je pronajímatel oprávněn rezervaci jednostranně zrušit.</li>
<li>Pronajímatel nevyžaduje složení vratné kauce. Tím není dotčena povinnost nájemce uhradit případnou škodu vzniklou na předmětu nájmu během doby nájmu.</li>
</ol>

<h2>6. Stav předmětu nájmu při převzetí a vrácení</h2>
<ol type="a">
<li>Předání i vrácení předmětu nájmu probíhá na předem dohodnutém místě a v předem stanovený čas, v den zahájení a ukončení výpůjčky.</li>
<li>Při převzetí motocyklu pronajímatel vyhotoví jednostranný Předávací protokol, který obsahuje zejména informace o stavu tachometru, stavu paliva, technickém stavu motocyklu, zapůjčené výbavě a případných existujících poškozeních. Nájemce převzetím předmětu nájmu potvrzuje, že se s Předávacím protokolem seznámil a souhlasí s jeho obsahem, i když protokol fyzicky nepodepisuje. Má-li nájemce k Protokolu výhrady, je povinen je oznámit pronajímateli při převzetí předmětu nájmu, jinak se má za to, že s uvedeným stavem souhlasí. Nájemce má možnost seznámit se s Předávacím protokolem a fotodokumentací přímo při převzetí předmětu nájmu. Tím je zajištěno, že stav motocyklu je objektivně doložen v okamžiku předání.</li>
<li>Výpůjčka končí vždy k 24:00 hodin posledního dne nájemní doby, pokud není dohodnuto jinak.</li>
<li>Předmět nájmu je nájemci předán čistý, natankovaný a ve stavu způsobilém k provozu.</li>
<li>Nájemce souhlasí s tím, že při převzetí i vrácení bude provedena fotodokumentace.</li>
<li>Nájemce bere na vědomí a souhlasí s tím, že fotodokumentace pořízená při převzetí a vrácení předmětu nájmu může zachycovat jeho podobu, osobní údaje či jiné identifikátory. Fotodokumentace slouží výhradně k ochraně práv a oprávněných zájmů pronajímatele, zejména k doložení stavu předmětu nájmu. Nakládání s fotodokumentací se řídí dokumentem „Zásady zpracování osobních údajů", který je přílohou nájemní smlouvy.</li>
<li>V případě, že bude předmět nájmu vrácen poškozený, chybí zapůjčená výbava nebo vykazuje jinou závadu vzniklou během doby nájmu, vyhotoví pronajímatel s nájemcem Protokol o zjištěném poškození motocyklu. Protokol obsahuje popis zjištěného poškození, rozsah škody a příslušnou fotodokumentaci. Protokol o zjištěném poškození vyžaduje podpis nájemce. Podpisem protokolu nájemce potvrzuje, že se seznámil s jeho obsahem, a zavazuje se uhradit škodu v plné výši, a to podle podmínek stanovených v nájemní smlouvě nebo dle doložených dokladů na opravu motocyklu. Odmítne-li nájemce Protokol podepsat, je pronajímatel oprávněn Protokol vyhotovit jednostranně. O odmítnutí podpisu se provede výslovná poznámka v Protokolu. Tato skutečnost nezakládá zánik povinnosti nájemce škodu uhradit. Pronajímatel zašle následně nájemci vyúčtování škody ve formě faktury v souladu s nájemní smlouvou a těmito VOP.</li>
<li>Nájemce nemusí předmět nájmu předávat umytý ani s plnou nádrží, ale nesmí svítit kontrolka rezervy.</li>
</ol>

<h2>7. Poruchy, nehody, závady a opravy</h2>
<ol type="a">
<li>Při jakékoli poruše, dopravní nehodě, poškození předmětu nájmu nebo neobvyklé situaci (např. podezření na závadu), je nájemce povinen neprodleně kontaktovat pronajímatele (telefonicky a následně i písemně formou e-mailu) a řídit se jeho pokyny. Bez souhlasu pronajímatele nesmí provádět žádné opravy ani servisní zásahy.</li>
<li>Nájemce se zavazuje neprodleně kontaktovat pronajímatele a oznámit mu veškeré škody vzniklé na předmětu nájmu, bez ohledu na jejich rozsah a příčinu.</li>
<li>V případě havárie předmětu nájmu, která znemožní další provoz, končí nájemní doba okamžitě. Nájemce není oprávněn s předmětem nájmu dále manipulovat, ani se jej pokoušet uvést do provozu bez výslovného souhlasu pronajímatele.</li>
<li>V případě dopravní nehody, odcizení předmětu nájmu nebo jiné závažné události je nájemce také povinen:
<ol type="i">
<li>neprodleně přivolat Policii ČR (nebo místní policii v zahraničí),</li>
<li>zajistit vyplnění a podepsání záznamu o nehodě,</li>
<li>spolupracovat při šetření události a poskytnout pravdivé informace.</li>
</ol></li>
<li>Nájemce je povinen přivolat Policii ČR vždy, vyžaduje-li to zákon o provozu na pozemních komunikacích (zejména v případě zranění, škody přesahující 100 000 Kč, škody na majetku třetích osob nebo nesouhlasu účastníků). U drobných poškození, která nemají charakter dopravní nehody podle zákona, policie zpravidla nezasahuje; v takových případech je nájemce povinen bezodkladně informovat pronajímatele a postupovat dle jeho pokynů.</li>
<li>Způsob řešení závady závisí na jejím rozsahu a místě, kde se předmět nájmu v danou chvíli nachází. Pronajímatel si vyhrazuje právo určit další postup s ohledem na okolnosti, dostupnost servisu, možnost převozu nebo opravy na místě.</li>
</ol>

<h2>8. Pojištění a odpovědnost</h2>
<ol type="a">
<li>Všechny motocykly motopůjčovny mají sjednané zákonné pojištění odpovědnosti z provozu vozidla, tzv. povinné ručení.</li>
<li>Na žádné z půjčovaných motocyklů není sjednáno havarijní pojištění.</li>
<li>V případě odcizení předmětu nájmu odpovídá nájemce až do výše jeho obvyklé tržní hodnoty, pokud porušil sjednané podmínky zabezpečení předmětu nájmu (např. ponechání klíčů v zapalování, nezajištění řídítek apod. uvedené v nájemní smlouvě.</li>
<li>Pokud nájemce prokáže, že byl předmět nájmu náležitě a řádně zabezpečen, a přesto došlo k jeho odcizení, odpovídá pouze do výše spoluúčasti ve výši 10 % z tržní hodnoty předmětu nájmu, maximálně však 30 000 Kč.</li>
<li>Nájemce odpovídá za veškeré škody, které vzniknou v důsledku porušení podmínek nájemní smlouvy, porušení pravidel silničního provozu, hrubé nedbalosti, úmyslného jednání nebo neoprávněného užívání předmětu nájmu. V takových případech nese nájemce odpovědnost za škodu v plné výši, a to bez možnosti pojistného krytí. Nájemce je povinen uhradit veškeré náklady spojené s opravou nebo náhradou předmětu nájmu až do výše jeho aktuální tržní hodnoty.</li>
<li>V případě poškození předmětu nájmu nebo jeho příslušenství vinou nájemce (např. pádem, nehodou, neopatrnou manipulací apod.), je nájemce povinen uhradit náklady na opravu. Výše škody bude stanovena na základě odborného servisu nebo odhadu pronajímatele.</li>
<li>V případě vzniku škody na předmětu nájmu nebo jeho příslušenství, kterou nájemce prokazatelně nezavinil a která byla způsobena třetí osobou nebo v důsledku nepředvídatelné události (např. dopravní nehoda způsobená jiným účastníkem, živelní pohroma, vandalismus), odpovídá nájemce maximálně do výše spoluúčasti 10 % z tržní hodnoty předmětu nájmu, maximálně však do výše 30 000 Kč, pokud zároveň:
<ol type="i">
<li>bezodkladně kontaktuje pronajímatele,</li>
<li>přivolá Policii ČR (nebo zahraniční) nebo jiný příslušný orgán veřejné moci (např. hasiče, obecní policii), pokud to situace vyžaduje,</li>
<li>poskytne veškerou součinnost při šetření události a zajištění případné náhrady škody od odpovědné osoby nebo pojišťovny,</li>
<li>prokáže, že v době vzniku škody dodržel všechny své povinnosti vyplývající ze smlouvy a pokynů pronajímatele.</li>
</ol></li>
<li>Ve všech případech, kdy je nájemce povinen dle těchto obchodních podmínek a nájemní smlouvy hradit škodu nebo spoluúčast, bude mu vystaven daňový doklad (faktura) se splatností 7 kalendářních dní ode dne jeho vystavení, není-li dohodnuto jinak. Faktura za škodu bude vystavena do 30 dnů od zjištění škody.</li>
<li>Nájemce odpovídá za veškeré dopravní přestupky, pokuty, poplatky a správní delikty, kterých se dopustí během doby trvání nájmu, a to bez ohledu na to, zda mu byly uloženy přímo na místě, nebo doručeny dodatečně správním orgánem. V případě, že bude pokuta, poplatek nebo jiný správní postih doručen pronajímateli dodatečně, zavazuje se nájemce uhradit veškeré s tím spojené náklady (včetně správních poplatků, případných nákladů na komunikaci s úřady a poplatku za zprostředkování ve výši 500 Kč). Pronajímatel si vyhrazuje právo poskytnout příslušným orgánům identifikační údaje nájemce v rozsahu nutném k převedení odpovědnosti za přestupek.</li>
<li>Nájemci bude za tyto náklady vystavena faktura se splatností 7 dnů od data vystavení. Neuhrazení částky ve lhůtě se považuje za porušení smluvních podmínek a může být předmětem vymáhání právní cestou.</li>
<li>Pronajímatel nenese odpovědnost za újmu vzniklou nájemci v důsledku nesprávného ovládání předmětu nájmu, nedodržení dopravních předpisů nebo nehod, které si nájemce způsobil vlastní vinou.</li>
<li>V případě prodlení nájemce s úhradou jakékoli částky vyplývající z nájemní smlouvy nebo VOP je pronajímatel oprávněn požadovat náhradu všech účelně vynaložených nákladů spojených s vymáháním pohledávky.</li>
<li>Mezi tyto náklady patří zejména:
<ol type="i">
<li>náklady právního zastoupení,</li>
<li>náklady na upomínky,</li>
<li>administrativní výdaje,</li>
<li>náklady související s předáním věci inkasní společnosti.</li>
</ol></li>
<li>Tato povinnost nájemce je splatná na základě vyúčtování (faktury) vystavené pronajímatelem.</li>
</ol>

<h2>9. Smluvní pokuty</h2>
<ol type="a">
<li>Nájemce je povinen zaplatit pronajímateli smluvní pokutu ve výši 20 000 Kč, pokud řídí předmět nájmu pod vlivem alkoholu, návykových látek nebo léčiv, které mohou ovlivnit schopnost řízení.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 10 000 Kč za porušení zákazu přenechání předmětu nájmu třetí osobě.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 15 000 Kč v případě použití předmětu nájmu k zakázaným činnostem (závody, soutěže, extrémní aktivity). Za extrémní aktivitu se považuje zejména jízda na uzavřených tratích, okruzích, v terénu, účast na závodech, soutěžích, stunt riding, wheelie, burnout apod.</li>
<li>V případě závažného poškození předmětu nájmu způsobeného hrubou nedbalostí nájemce se sjednává smluvní pokuta ve výši 20 000 Kč.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 15 000 Kč za porušení zákazu jízdy mimo území povolených států dle zelené karty.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 5 000 Kč v případě porušení povinnosti bezodkladně oznámit nehodu, poškození nebo závadu.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 10 000 Kč při neoprávněných zásazích do technického stavu motocyklu, jeho výbavy nebo příslušenství.</li>
<li>Nájemce je povinen zaplatit smluvní pokutu ve výši 10 000 Kč za porušení povinnosti zabezpečit předmět nájmu proti odcizení. Tato povinnost platí nezávisle na tom, zda dojde ke škodě; v případě odcizení předmětu nájmu nese nájemce odpovědnost za škodu v plné výši, tj. až do tržní hodnoty předmětu nájmu, a to bez možnosti uplatnění pojistného plnění. Smluvní pokuta zároveň zahrnuje náklady a administrativní činnosti spojené s vyřízením této události.</li>
<li>Uplatněním smluvních pokut není dotčeno právo pronajímatele požadovat náhradu škody v plném rozsahu, a to bez možnosti uplatnění pojistného plnění v případech, kdy nájemce poruší podmínky nájemní smlouvy nebo právní předpisy.</li>
<li>Nájemce má právo dokázat, že skutečná škoda byla nižší než sjednaná pokuta.</li>
</ol>

<h2>10. Odstoupení od smlouvy ze strany pronajímatele</h2>
<ol type="a">
<li>Pronajímatel je oprávněn odstoupit od nájemní smlouvy s okamžitou platností v těchto případech:
<ol type="i">
<li>nájemce poruší podmínky smlouvy nebo těchto VOP závažným způsobem,</li>
<li>nájemce používá předmět nájmu v rozporu s jeho určením, nedovoleně ho opravuje, přetěžuje, nebo s ním zachází nebezpečně,</li>
<li>nájemce odmítá komunikovat s pronajímatelem nebo opakovaně porušuje povinnost sdělovat důležité skutečnosti (např. nehoda, poškození, technické problémy),</li>
<li>existuje důvodné podezření, že předmět nájmu může být zneužit pro trestnou činnost nebo jinou činnost odporující právnímu řádu ČR nebo EU,</li>
<li>z provozních nebo bezpečnostních důvodů, zejména v případě technické závady znemožňující bezpečné užívání vozidla.</li>
</ol></li>
<li>V případě, že nájemce poruší některou z výše uvedených podmínek, má pronajímatel právo na:
<ol type="i">
<li>okamžité odstoupení od nájemní smlouvy,</li>
<li>požadovat neprodlené vrácení předmětu nájmu,</li>
<li>uplatnit nároky na náhradu škody vzniklé tímto porušením,</li>
<li>a využít dalších zákonných prostředků k ochraně svých práv.</li>
</ol></li>
<li>Odstoupením od smlouvy zaniká nájemní vztah ke dni oznámení o odstoupení. Předmět nájmu je nájemce povinen bezodkladně vrátit pronajímateli na místo určené ve smlouvě nebo dle pokynů pronajímatele.</li>
<li>V případě odstoupení od smlouvy z důvodů na straně nájemce nevzniká nárok na vrácení uhrazeného nájemného, a to ani poměrně, ledaže pronajímatel rozhodne jinak.</li>
</ol>

<h2>11. Odstoupení od smlouvy spotřebitelem</h2>
<ol type="a">
<li>Nájem motocyklu je službou spojenou s využitím volného času v konkrétním termínu podle volby zákazníka. V souladu se zákonem o ochraně spotřebitele tedy spotřebitel nemá právo odstoupit od smlouvy do 14 dnů, jak je jinak běžné u distančních smluv.</li>
<li>Potvrzením rezervace a odesláním rezervačního formuláře zákazník bere na vědomí, že služba je poskytována v konkrétním čase dle jeho volby a že právo na odstoupení dle § 1829 občanského zákoníku je podle § 1837 písm. j) vyloučeno.</li>
<li>Pokud zákazník zruší rezervaci před termínem zapůjčení, postupuje se podle storno podmínek uvedených v těchto VOP.</li>
</ol>

<h2>12. Zvláštní ustanovení pro výpůjčku dětských motocyklů a nezletilé řidiče</h2>
<ol type="a">
<li>Výpůjčka dětských motocyklů je určena výhradně pro osoby mladší 18 let (dále jen nezletilí), a to pouze pod dohledem a na zodpovědnost zákonného zástupce.</li>
<li>Nájemce v tomto případě je vždy osoba starší 18 let – zákonný zástupce dítěte (např. rodič), která nese plnou zodpovědnost za:
<ol type="i">
<li>bezpečnost a zdraví nezletilého,</li>
<li>bezpečný provoz stroje,</li>
<li>dohled nad používáním,</li>
<li>způsobené škody,</li>
<li>dodržení všech pokynů pronajímatele.</li>
</ol></li>
<li>Nezletilí mohou stroj používat pouze v uzavřeném, bezpečném prostoru, mimo pozemní komunikace, a za vhodných podmínek (např. za denního světla, bez deště apod.)</li>
<li>Je zakázáno používat dětské stroje:
<ol type="i">
<li>na veřejných silnicích, stezkách a chodnících,</li>
<li>bez ochranného vybavení (helma, rukavice, moto kalhoty a pevná obuv),</li>
<li>bez dozoru dospělé osoby.</li>
</ol></li>
<li>Při vrácení dětského stroje budou stejně jako u ostatních strojů posouzeny případné škody či jiné nedostatky. Náklady jsou nájemci doúčtovány dodatečně v podobě faktury se splatností 7 dnů od data vystavení.</li>
</ol>

<h2>13. Reklamace a řešení sporů</h2>
<ol type="a">
<li>Nájemce má právo uplatnit reklamaci na služby nebo stav předmětu nájmu bez zbytečného odkladu.</li>
<li>Reklamace musí být dodána písemně, a to nejpozději do 3 pracovních dnů od skončení nájemní doby, tj. fyzického předání předmětu nájmu pronajímateli.</li>
<li>Pronajímatel se zavazuje vyjádřit k reklamaci do 10 pracovních dnů od jejího doručení pronajímateli.</li>
<li>V případě sporu se smluvní strany zavazují nejprve pokusit o smírné řešení. Nedošlo-li ke smíru, je místně příslušným soudem pro řešení sporu soud podle sídla pronajímatele.</li>
<li>Spotřebitelé mají možnost využít mimosoudní řešení spotřebitelských sporů u příslušného orgánu. Více informací naleznete na webové stránce Evropské komise: https://ec.europa.eu/consumers/odr/.</li>
</ol>

<h2>14. Vyšší moc</h2>
<ol type="a">
<li>Žádná ze smluvních stran nenese odpovědnost za nesplnění svých povinností vyplývajících z této smlouvy v důsledku událostí vyšší moci, které nemohla rozumně předvídat, zabránit jim nebo je ovlivnit. Za vyšší moc se považují zejména přírodní katastrofy, požáry povodně, válečné konflikty, epidemie, rozhodnutí státních orgánů nebo jiné mimořádné události mající přímý dopad na schopnost plnit smluvní závazky. Tato skutečnost musí být druhé straně bez zbytečných odkladů oznámena.</li>
</ol>

<h2>15. Závěrečná ustanovení</h2>
<ol type="a">
<li>Nájemce potvrzuje, že se seznámil s těmito VOP, porozuměl jejich obsahu a bez výhrad s nimi souhlasí.</li>
<li>Veškeré dodatky a změny nebo odchylky VOP musí být uzavřeny písemně a potvrzeny oběma stranami, jinak jsou neplatné.</li>
<li>Tyto VOP jsou nedílnou součástí nájemní smlouvy a jsou pro obě smluvní strany závazné.</li>
<li>Ochrana osobních údajů je řešena samostatným dokumentem „Zásady zpracování osobních údajů", který je nájemci zpřístupněn a tvoří přílohu nájemní smlouvy.</li>
<li>Práva a povinnosti smluvních stran se řídí právním řádem České republiky.</li>
<li>Nájemní smlouva je uzavřena okamžikem, kdy pronajímatel elektronicky potvrdí rezervaci nájemci a nájemce ve stanovené lhůtě, tj. buď do 24 h od potvrzení rezervace, nebo při rezervaci na týž den okamžitě, uhradí nájemné a předloží všechny požadované platné doklady.</li>
</ol>

<p style="margin-top:30px;font-weight:700">Potvrzení souhlasu s obchodními podmínkami</p>
<p>Zákazník potvrzuje, že se seznámil s těmito Všeobecnými obchodními podmínkami, rozumí jim a bez výhrad s nimi souhlasí.</p>
<p>Nájemce potvrzuje souhlas s obchodními podmínkami zaškrtnutím příslušného políčka v rezervačním formuláři na webových stránkách pronajímatele. Tento elektronický úkon má povahu vlastnoručního podpisu a je považován za platný a závazný pro obě smluvní strany.</p>

<div class="footer">Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Mezná · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
  1
)
ON CONFLICT (type) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  name = EXCLUDED.name,
  version = document_templates.version + 1,
  updated_at = now();

-- 2. Smlouva o pronájmu motocyklu (rental_contract)
INSERT INTO public.document_templates (name, type, content_html, version)
VALUES (
  'Smlouva o pronájmu motocyklu',
  'rental_contract',
  '<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>Smlouva o pronájmu motocyklu – MotoGo24</title>
<style>
body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:13px;line-height:1.6}
.wrap{max-width:780px;margin:0 auto;padding:32px}
h1{text-align:center;font-size:20px;border-bottom:2px solid #1a8a18;padding-bottom:12px;margin-bottom:8px}
h2{font-size:14px;margin:20px 0 8px;color:#1a8a18}
.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:24px}
.parties{display:flex;gap:24px;margin:20px 0}
.party{flex:1;padding:14px;background:#f8faf9;border-radius:8px}
.party-label{margin:0 0 4px;font-size:10px;font-weight:700;text-transform:uppercase;color:#888}
.party p{margin:2px 0;font-size:12px}
table{width:100%;border-collapse:collapse;font-size:12px;margin:8px 0}
td{padding:6px 10px}
td:first-child{background:#f8faf9;font-weight:600;width:180px}
.sig{margin-top:48px;display:flex;justify-content:space-between}
.sig-box{text-align:center;width:45%}
.sig-line{border-top:1px solid #999;padding-top:8px;font-size:11px}
.footer{margin-top:40px;text-align:center;font-size:11px;color:#888;border-top:1px solid #ddd;padding-top:16px}
ul{padding-left:20px} li{margin-bottom:3px}
</style></head>
<body><div class="wrap">
<h1>SMLOUVA O PRONÁJMU MOTOCYKLU</h1>
<p class="subtitle">č. {{booking_number}} ze dne {{today}}</p>
<p style="font-size:12px">Tato smlouva o nájmu movité věci – motocyklu (dále jen „smlouva") se uzavírá mezi níže uvedenými stranami prostřednictvím elektronických prostředků komunikace na dálku, zejména prostřednictvím rezervačního formuláře na webových stránkách www.motogo24.cz.</p>

<div class="parties">
<div class="party">
<p class="party-label">Pronajímatel</p>
<p style="font-weight:700;margin:0">Bc. Petra Semorádová</p>
<p>Mezná 9, 393 01 Mezná</p>
<p>IČO: 21874263</p>
<p>Telefon: +420 774 256 271</p>
<p>E-mail: info@motogo24.cz</p>
<p>Bankovní spojení: 670100-2225851630/6210</p>
<p>Není plátce DPH.</p>
</div>
<div class="party">
<p class="party-label">Nájemce</p>
<p style="font-weight:700;margin:0">{{customer_name}}</p>
<p>{{customer_address}}</p>
<p>Číslo OP/PAS: {{customer_id_number}}</p>
<p>Číslo ŘP: {{customer_license}}</p>
<p>Telefon: {{customer_phone}}</p>
<p>E-mail: {{customer_email}}</p>
</div>
</div>

<p style="font-size:12px">Pronajatý motocykl smí řídit pouze nájemce uvedený ve smlouvě, jehož řidičské oprávnění a dovednosti jsou způsobilé k bezproblémové manipulaci s pronajatým strojem. V případě, že nájemce stroj zapůjčí svévolně třetí osobě, chápe se toto svévolné zapůjčení jako hrubé porušení nájemní smlouvy.</p>
<p style="font-size:12px">Jedinou výjimkou, kdy nájemce není zároveň řidič předmětu nájmu, jsou dětské motocykly. V případě pronájmu dětského motocyklu platí, že nájemcem je zákonný zástupce (rodič) nezletilého dítěte, které bude předmět nájmu užívat.</p>

<h2>Předmět nájmu</h2>
<table>
<tr><td>Značka a model</td><td>{{moto_model}}</td></tr>
<tr><td>SPZ</td><td>{{moto_spz}}</td></tr>
<tr><td>VIN</td><td>{{moto_vin}}</td></tr>
</table>
<p style="font-size:12px">Veškeré standardní příslušenství a nadstandardní vybavení zapůjčené nájemci je specifikováno v Předávacím protokolu, který tvoří nedílnou součást této nájemní smlouvy.</p>

<h2>Platnost nájemní smlouvy, termín výpůjčky, výše nájemného a kauce</h2>
<p style="font-size:12px">Nájemní smlouva je uzavřena okamžikem, kdy pronajímatel elektronicky potvrdí rezervaci nájemci a nájemce ve stanovené lhůtě uhradí nájemné a předloží pronajímateli všechny požadované platné doklady.</p>
<table>
<tr><td>Nájemní smlouva platí od</td><td>{{start_date}} {{start_time}}</td></tr>
<tr><td>Platnost smlouvy končí</td><td>{{end_date}} {{end_time}}</td></tr>
<tr><td>Termín výpůjčky</td><td>{{rental_period}}</td></tr>
<tr><td>Celkové nájemné</td><td><strong>{{total_price}} Kč</strong></td></tr>
<tr><td>Slovy</td><td>{{total_price_words}}</td></tr>
<tr><td>Kauce</td><td>0 Kč (pronajímatel nevyžaduje kauci)</td></tr>
</table>
<p style="font-size:12px">Cena zahrnuje veškeré náklady spojené s pronájmem včetně zapůjčeného příslušenství a doplňků navíc, jakož i případné dohodnuté služby navíc.</p>

<h2>Předání předmětu nájmu</h2>
<table>
<tr><td>Místo předání</td><td>{{pickup_location}}</td></tr>
</table>
<p style="font-size:12px">Předmět nájmu je nájemci předán ve stavu způsobilém k řádnému užívání. Skutečný technický a vizuální stav předmětu nájmu v okamžiku předání je zaznamenán v samostatném Předávacím protokolu.</p>
<p style="font-size:12px">Nájemce potvrzuje, že se před převzetím předmětu nájmu seznámil s uživatelským manuálem příslušného předmětu nájmu, který je k dispozici online prostřednictvím odkazů uvedených na webových stránkách poskytovatele.</p>

<h2>Místo a rozsah užívání předmětu nájmu</h2>
<p style="font-size:12px">Nájemce je oprávněn užívat předmět nájmu na území České republiky a dalších států, jež nejsou přeškrtnuty na zelené kartě.</p>
<p style="font-size:12px">Je výslovně zakázáno užívat předmět nájmu na území států, které jsou na zelené kartě přeškrtnuty.</p>

<h2>Vrácení předmětu nájmu</h2>
<table>
<tr><td>Místo vrácení</td><td>{{return_location}}</td></tr>
</table>
<p style="font-size:12px">Předmět nájmu musí být vrácen nejpozději do půlnoci (tj. 24:00 h) dne, který je ve smlouvě uveden jako poslední den nájmu. Vrácení po půlnoci je považováno za prodlení a je účtováno jako další den nájmu plus poplatek 500 Kč za každou započatou hodinu prodlení.</p>

<h2>Motivační sleva za vrácení ve výborném stavu</h2>
<p style="font-size:12px">V případě, že nájemce vrátí předmět nájmu ve viditelně čistém stavu, bez jakéhokoliv nového mechanického poškození, včetně kompletního vybavení a bude zřejmé, že k předmětu nájmu přistupoval šetrně, bude mu jako poděkování poskytnuta sleva ve výši 400 Kč na další pronájem formou slevového kódu.</p>

<h2>Pojištění, nehody a odpovědnost za škodu</h2>
<p style="font-size:12px">Předmět nájmu má sjednáno pouze zákonné pojištění odpovědnosti z provozu vozidla (tzv. povinné ručení) s územní platností dle zelené karty.</p>
<p style="font-size:12px">V případě dopravní nehody, poškození, zcizení nebo jiné mimořádné události je nájemce povinen: okamžitě přivolat policii ČR; neprodleně kontaktovat pronajímatele; zajistit fotodokumentaci a spolupracovat na sepsání záznamu o nehodě.</p>
<p style="font-size:12px">V případech, kdy není prokázána hrubá nedbalost či porušení pravidel, hradí nájemce spoluúčast ve výši 10 % z celkové škody, maximálně však 30 000 Kč.</p>

<h2>Povinnost zabezpečení předmětu nájmu</h2>
<p style="font-size:12px">Nájemce se zavazuje vždy řádně zabezpečit předmět nájmu proti odcizení: zamknout řízení, vyjmout klíč ze zapalování, zajistit parkování na vhodném místě.</p>

<h2>Závěrečná ustanovení</h2>
<p style="font-size:12px">Smluvní strany se dohodly, že veškeré skutečnosti neupravené touto smlouvou se řídí příslušnými ustanoveními zákona č. 89/2012 Sb., občanského zákoníku.</p>
<p style="font-size:12px">Odesláním rezervačního formuláře a zaškrtnutím příslušných souhlasů nájemce výslovně potvrzuje, že se seznámil se všemi dokumenty souvisejícími s nájmem. Elektronický souhlas má stejnou právní váhu jako fyzický podpis nájemce.</p>
<p style="font-size:12px">Nedílnou součástí této nájemní smlouvy jsou Obchodní podmínky pronajímatele, souhlas se zpracováním osobních údajů dle GDPR, Předávací protokol a Protokol o zjištěném poškození (pokud relevantní).</p>

<div class="sig">
<div class="sig-box"><div class="sig-line">Pronajímatel<br>Bc. Petra Semorádová</div></div>
<div class="sig-box"><div class="sig-line">Nájemce<br>{{customer_name}}</div></div>
</div>

<div class="footer">Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Mezná · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
  1
)
ON CONFLICT (type) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  name = EXCLUDED.name,
  version = document_templates.version + 1,
  updated_at = now();

-- 3. Předávací protokol (handover_protocol)
INSERT INTO public.document_templates (name, type, content_html, version)
VALUES (
  'Předávací protokol',
  'handover_protocol',
  '<!DOCTYPE html>
<html lang="cs">
<head><meta charset="utf-8"><title>Předávací protokol – MotoGo24</title>
<style>
body{font-family:"Segoe UI",sans-serif;color:#1a1a1a;margin:0;padding:0;font-size:13px;line-height:1.6}
.wrap{max-width:780px;margin:0 auto;padding:32px}
h1{text-align:center;font-size:20px;border-bottom:2px solid #2563eb;padding-bottom:12px;margin-bottom:8px}
h2{font-size:14px;margin:20px 0 8px;color:#2563eb}
.subtitle{text-align:center;font-size:12px;color:#666;margin-bottom:24px}
table{width:100%;border-collapse:collapse;font-size:12px;margin:8px 0;border:1px solid #ddd}
td,th{padding:8px 10px;border:1px solid #ddd;text-align:left}
th{background:#f0f7ff;font-weight:700;font-size:11px;text-transform:uppercase}
td:first-child{background:#f8faf9;font-weight:600;width:200px}
.checklist td{background:#fff;font-weight:normal}
.checklist td:first-child{width:auto;background:#fff}
.sig{margin-top:48px;display:flex;justify-content:space-between}
.sig-box{text-align:center;width:45%}
.sig-line{border-top:1px solid #999;padding-top:8px;font-size:11px}
.footer{margin-top:40px;text-align:center;font-size:11px;color:#888;border-top:1px solid #ddd;padding-top:16px}
</style></head>
<body><div class="wrap">
<h1>PŘEDÁVACÍ PROTOKOL</h1>
<p class="subtitle">k rezervaci č. {{booking_number}} ze dne {{today}}</p>

<h2>1. Identifikace smlouvy a stran</h2>
<table>
<tr><td>Číslo smlouvy</td><td>{{booking_number}}</td></tr>
<tr><td>Pronajímatel</td><td>MotoGo24, Bc. Petra Semorádová</td></tr>
<tr><td>Nájemce</td><td>{{customer_name}}</td></tr>
</table>

<h2>2. Identifikace vozidla</h2>
<table>
<tr><td>Značka a model</td><td>{{moto_model}}</td></tr>
<tr><td>VIN</td><td>{{moto_vin}}</td></tr>
</table>

<h2>3. Stav motocyklu při předání</h2>
<table>
<tr><td>Stav tachometru</td><td>{{mileage}} km</td></tr>
<tr><td>Stav paliva</td><td>{{fuel_state}}</td></tr>
<tr><td>Technický stav</td><td>{{technical_state}}</td></tr>
</table>

<h2>4. Příslušenství a výbava</h2>
<table class="checklist">
<tr><th>Položka</th><th>Počet ks</th><th>Stav při převzetí</th><th>Předáno</th></tr>
<tr><td>Helma</td><td></td><td></td><td></td></tr>
<tr><td>Kalhoty</td><td></td><td></td><td></td></tr>
<tr><td>Bunda</td><td></td><td></td><td></td></tr>
<tr><td>Rukavice</td><td></td><td></td><td></td></tr>
<tr><td>Boty</td><td></td><td></td><td></td></tr>
<tr><td>Kukla</td><td></td><td>nová (zůstává nájemci)</td><td></td></tr>
<tr><td>Kufr zadní</td><td></td><td></td><td></td></tr>
<tr><td>Kufr boční</td><td></td><td></td><td></td></tr>
</table>

<h2>5. Povinná výbava a dokumenty</h2>
<table class="checklist">
<tr><th>Položka</th><th>Počet ks</th><th>Předáno</th></tr>
<tr><td>Malý technický průkaz</td><td></td><td></td></tr>
<tr><td>Zelená karta</td><td></td><td></td></tr>
<tr><td>Kontakt na asistenční službu</td><td></td><td></td></tr>
<tr><td>Záznam o dopravní nehodě s propiskou</td><td></td><td></td></tr>
<tr><td>Klíče</td><td></td><td></td></tr>
<tr><td>Lékárnička</td><td></td><td></td></tr>
<tr><td>Reflexní vesta</td><td></td><td></td></tr>
</table>

<h2>6. Převzetí motocyklu</h2>
<p style="font-size:12px">Nájemce potvrzuje, že převzal motocykl ve výše uvedeném stavu a s uvedeným příslušenstvím.</p>
<p style="font-size:12px">Příslušná fotodokumentace je přiložena k protokolu a je jeho nedílnou součástí. Nájemce bere na vědomí, že fotodokumentace pořízená v čase předání motocyklu je rozhodující pro posouzení stavu motorky.</p>
<p style="font-size:12px">Převzetím motocyklu nájemce souhlasí s obsahem tohoto Předávacího protokolu, který bude nájemci zaslán elektronicky na e-mail uvedený v nájemní smlouvě bezprostředně po převzetí motocyklu.</p>

<table>
<tr><td>Datum a čas převzetí</td><td>{{today}} {{today_time}}</td></tr>
<tr><td>Vystavil/a</td><td>Bc. Petra Semorádová</td></tr>
</table>

<div class="sig">
<div class="sig-box"><div class="sig-line">Předávající<br>Bc. Petra Semorádová</div></div>
<div class="sig-box"><div class="sig-line">Přebírající<br>{{customer_name}}</div></div>
</div>

<div class="footer">Bc. Petra Semorádová · IČO: 21874263 · Mezná 9, 393 01 Mezná · info@motogo24.cz · +420 774 256 271</div>
</div></body></html>',
  1
)
ON CONFLICT (type) DO UPDATE SET
  content_html = EXCLUDED.content_html,
  name = EXCLUDED.name,
  version = document_templates.version + 1,
  updated_at = now();

-- Ensure unique constraint exists on type for ON CONFLICT to work
-- (If it doesn't exist, the ON CONFLICT will fail — in that case run without ON CONFLICT)
-- Alternative: Use DO NOTHING + separate UPDATE if needed
