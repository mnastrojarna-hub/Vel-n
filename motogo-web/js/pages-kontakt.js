// ===== MotoGo24 Web — Kontakt =====

var MG = window.MG || {};
window.MG = MG;

MG.route('/kontakt', function(app){
  var bc = MG.renderBreadcrumb([{label:'Domů',href:'/'},'Kontakt']);

  var quickContact = '<section><div class="contact-quick-boxes">' +
    '<div class="contact-quick-box dfc"><div class="img-icon dfcc"><img src="gfx/telefon.svg" alt="Telefon" class="icon-small" loading="lazy"></div><div>' +
    '<p><small>ZAVOLEJTE NÁM</small><br><strong><a href="' + MG.PHONE_LINK + '">' + MG.PHONE + '</a></strong></p></div></div>' +
    '<div class="contact-quick-box dfc"><div class="img-icon dfcc"><img src="gfx/email.svg" alt="E-mail" class="icon-small" loading="lazy"></div><div>' +
    '<p><small>NAPIŠTE NÁM</small><br><strong>' + MG.EMAIL_USER + '@' + MG.EMAIL_DOMAIN + '</strong></p></div></div>' +
    '<div class="contact-quick-box dfc"><div><p><small>DATOVÁ SCHRÁNKA</small><br><strong>iuw3vnb</strong></p></div></div>' +
    '</div></section>';

  var infoSection = '<div class="gr2 contact-info"><section>' +
    '<h2>Provozovna</h2>' +
    '<p><strong>Adresa:</strong><br>' + MG.ADDRESS + '</p><p>&nbsp;</p>' +
    '<p><strong>Provozní doba:</strong><br>PO – NE: 00:00 – 24:00 (nonstop)<br>Včetně víkendů a svátků</p><p>&nbsp;</p>' +
    '<h2>Fakturační údaje</h2>' +
    '<p><strong>Bc. Petra Semorádová</strong><br>Mezná 9, 393 01 Pelhřimov</p><p>&nbsp;</p>' +
    '<p>IČO: 21874263<br>Nejsem plátce DPH</p><p>&nbsp;</p>' +
    '<p>Společnost byla zapsána dne 31. 7. 2024 u Městského úřadu v Pelhřimově.</p>' +
    '</section><div>' +
    '<section><h2>Sledujte nás</h2>' +
    '<p class="dfc"><span class="social-icon"><img alt="Facebook" src="gfx/facebook.svg"></span>&nbsp;<a href="' + MG.FB_URL + '">facebook</a></p><p>&nbsp;</p>' +
    '<p class="dfc"><span class="social-icon"><img alt="Instagram" src="gfx/instagram.svg"></span>&nbsp;<a href="' + MG.IG_URL + '">instagram</a></p></section>' +
    '<section class="cta-green-box"><h2>Chcete si domluvit rezervaci?</h2>' +
    '<p>Rezervujte si motorku online během pár minut a vyražte za dobrodružstvím.</p><p>&nbsp;</p>' +
    '<p><a class="btn btndark" href="#/rezervace">REZERVOVAT ONLINE</a></p></section>' +
    '</div></div>';

  var mapSection = '<section>' +
    '<h2>Kde nás najdete</h2>' +
    '<p><iframe aria-label="Mapa kde nás najdete" class="map" loading="lazy" src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d60685.769400224744!2d15.153296724864992!3d49.356399196882506!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x470ce75bf69a97b3%3A0xe75f9d3fadf02b5b!2zTWV6bsOhIDksIDM5MyAwMSBNZXpuw6E!5e0!3m2!1scs!2scz!4v1762106938627!5m2!1scs!2scz"></iframe></p></section>';

  var seoText = '<h2>Kontakty – půjčovna motorek Vysočina (Pelhřimov)</h2>' +
    '<p>Motogo24 je&nbsp;<strong>moderní půjčovna motorek na Vysočině</strong>. Sídlíme v&nbsp;<strong>Pelhřimově</strong>, jsme otevřeni&nbsp;<strong>nonstop</strong>&nbsp;a půjčujeme&nbsp;<strong>bez kauce</strong>, s kompletní&nbsp;<strong>výbavou v ceně</strong>.</p>';

  app.innerHTML = '<main id="content"><div class="container contact">' + bc +
    '<div class="ccontent contacts">' +
    '<h1>Kontakty půjčovna motorek Motogo24</h1>' +
    '<p>Máte dotaz k <strong>půjčení motorky</strong>, chcete si objednat <strong>dárkový poukaz</strong>, poradit s výběrem nebo si rovnou <strong>domluvit rezervaci</strong>? Jsme tu pro vás každý den, <strong>nonstop</strong>.</p><p>&nbsp;</p>' +
    quickContact + infoSection + mapSection + seoText +
    '</div></div></main>';
});
