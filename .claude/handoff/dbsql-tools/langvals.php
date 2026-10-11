<?php
$root='/home/user/Vel-n/motogo-web-php';
$paths=[
 ['jak_pujcit_vraceni_pujcovna',['faq','items',1,'a']],
 ['jak_pujcit_vraceni_pujcovna',['faq','items',1,'q']],
 ['jak_pujcit_vraceni_jinde',['faq','items',1,'a']],
 ['jak_pujcit_vraceni_jinde',['faq','items',1,'q']],
 ['jak_pujcit_postup',['process','steps',11,'text']],
 ['jak_pujcit_dokumenty',['handover','items',2]],
 ['jak_pujcit_dokumenty',['payments','rows',2,1]],
 ['jak_pujcit_dokumenty',['payments','rows',2,0]],
];
$out=[];
foreach(['cs','en','de','es','fr','nl','pl','uk'] as $l){
  $arr = include "$root/lang/pages_$l.php";
  $pages = $arr['pages'] ?? $arr;
  foreach($paths as [$pg,$p]){
    $v = $pages[$pg] ?? null;
    foreach($p as $k){ $v = is_array($v) && array_key_exists($k,$v) ? $v[$k] : null; }
    $out[$l][$pg.'.'.implode('.',$p)] = $v;
  }
}
echo json_encode($out, JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT);
