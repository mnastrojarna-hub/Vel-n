<?php
echo renderHead('Potvrzení | MotoGo24', 'Potvrzení platby za rezervaci nebo objednávku.');
echo renderHeader();
?>
<main id="content"><div class="container">
<?php echo renderBreadcrumb([['label'=>'Domů','href'=>'/'], 'Potvrzení']); ?>
<div class="ccontent"><div id="confirm-content">
<div class="loading-overlay"><span class="spinner"></span> Ověřujeme platbu...</div>
</div></div>
</div></main>
<?php
echo renderFooter();
echo renderPageEnd(true);
?>
<script src="/js/pages-potvrzeni.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function(){ MG._initPotvrzeni(); });
</script>
