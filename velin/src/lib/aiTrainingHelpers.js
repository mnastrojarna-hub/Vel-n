// Shared helpers for training scenario generation
export const TS = () => Date.now().toString(36).slice(-4)
export const NAME = () => ['Jan','Petra','Tomáš','Eva','Martin','Lucie','Pavel','Alena'][Math.random()*8|0]
export const SURNAME = () => ['Novák','Černá','Horák','Dvořák','Svoboda','Malá','Veselý','Krejčí'][Math.random()*8|0]
export const BRANCH = () => Math.random() > 0.5 ? 'Mezná' : 'Brno'
export const MOTO = () => ['Honda CB500F','Yamaha MT-07','Kawasaki Z650','BMW G310R','KTM Duke 390'][Math.random()*5|0]
export const DAYS = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return d.toLocaleDateString('cs-CZ') }
export const EXTRAS = () => ['helma','rukavice','bunda','kufr','GPS'][Math.random()*5|0]
