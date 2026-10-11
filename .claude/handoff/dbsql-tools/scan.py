import json,re,sys,os
D=sys.argv[1]
pat=re.compile(r"(tankov|natankov|dotankov|nádrž|nadrz|palivo|paliv[aeuo]|benzín|benzin|\bmyt[íi]|umyt|umýt|\bmýt|\bmyj|myt[áa]|čist[áéou]|vyčist|svítící rezerv|rezerv[auy]\b(?!ace)|\bfuel|refuel|\bpetrol|\bwash|\bclean|full tank|\btank\b|tanken|kraftstoff|gewaschen|waschen|sauber|reservelampe|reserveleuchte|combustible|gasolina|depósito|lavad|lavar|limpi|carburant|essence|le plein|réservoir|lavé|laver|propre|brandstof|benzine|gewassen|wassen|schoon|paliw|zatankow|tankowa|\bbak\b|umyt|czyst|myci|mycie|rezerw[ay]\b|пальн|бак|заправ|мит[иийоа]|вимит|чист|резерв(?!ув))",re.I)
def walk(o,path):
    if isinstance(o,dict):
        for k,v in o.items(): yield from walk(v,path+[str(k)])
    elif isinstance(o,list):
        for i,v in enumerate(o): yield from walk(v,path+[str(i)])
    elif isinstance(o,str):
        yield path,o
for fn in sorted(os.listdir(D)):
    if not fn.endswith('.json'): continue
    data=json.load(open(os.path.join(D,fn)))
    if not isinstance(data,list): continue
    for row in data:
        rid=row.get('key') or row.get('slug') or row.get('id') or row.get('name')
        for path,s in walk(row,[]):
            if path and path[0] in ('id','updated_at','created_at'): continue
            txt=re.sub(r'<[^>]+>',' ',s)
            for m in pat.finditer(txt):
                a=max(0,m.start()-110); b=min(len(txt),m.end()+110)
                print(f"{fn}|{rid}|{'.'.join(path)}|{m.group(0)}| …{txt[a:b]}…".replace('\n',' '))
