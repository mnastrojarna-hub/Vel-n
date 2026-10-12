import json,sys
L,A=sys.argv[1],sys.argv[2]
def leaves(o,p=()):
    if isinstance(o,dict):
        for k,v in o.items(): yield from leaves(v,p+(k,))
    elif isinstance(o,list):
        for i,v in enumerate(o): yield from leaves(v,p+(i,))
    else: yield p,o
out=[]
def diff(name,before,after,keyf,fields):
    b={keyf(r):r for r in before}; a={keyf(r):r for r in after}
    assert set(b)==set(a), name
    n=0
    for k in sorted(a):
        lb=dict(('/'.join(map(str,(f,)+p)),v) for f in fields for p,v in leaves(b[k].get(f)))
        la=dict(('/'.join(map(str,(f,)+p)),v) for f in fields for p,v in leaves(a[k].get(f)))
        for path in sorted(set(lb)|set(la)):
            if lb.get(path)!=la.get(path):
                n+=1; out.append((name,k,path,lb.get(path),la.get(path)))
    print(name,'changed leaves:',n)
diff('cms',json.load(open(L+'/cms_variables.json')),json.load(open(A+'/cms_after.json')),lambda r:r['key'],['value','translations'])
diff('faq',json.load(open(L+'/faq_items.json')),json.load(open(A+'/faq_after.json')),lambda r:r['id'],['question','answer','translations'])
diff('aps',json.load(open(L+'/app_settings.json')),json.load(open(A+'/aps_after.json')),lambda r:r['key'],['value'])
json.dump(out,open(A+'/leafdiff.json','w'),ensure_ascii=False,indent=0)
for o in out: print(o[0],o[1],o[2])
