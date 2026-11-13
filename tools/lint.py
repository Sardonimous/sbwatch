import re,glob,sys,xml.dom.minidom
bad=False
for f in glob.glob('components/*.xml')+[]:
    xml.dom.minidom.parse(f)
src=""
for f in sorted(glob.glob('components/*.brs')+glob.glob('source/*.brs')):
    t=open(f).read(); src+=t
    lines=[l.split("'")[0].strip() for l in t.splitlines()]
    c=lambda p:sum(1 for l in lines if re.match(p,l))
    pr=[(c(r'^(sub|function)\b'),c(r'^end (sub|function)\b')),(c(r'^if\b.*\bthen$'),c(r'^end if\b')),(c(r'^for\b'),c(r'^end for\b|^next\b')),(c(r'^while\b'),c(r'^end while\b'))]
    if any(a!=b for a,b in pr): print("UNBALANCED",f,pr); bad=True
    # reserved words used as identifiers (outside strings/comments, not after a dot)
    for n,l in enumerate(t.splitlines(),1):
        code=re.sub(r'"[^"]*"','""',l).split("'")[0]
        for m_ in re.finditer(r'(?<![\.\w])(pos|tab|box|dim|eval|let|line_num|rem|objfun|getglobalaa)\b',code,re.I):
            print("RESERVED WORD",f,n,m_.group(1),"|",l.strip()); bad=True
defs={d.lower() for d in re.findall(r'^(?:sub|function)\s+(\w+)',src,re.M|re.I)}
calls=set(re.findall(r'(?<![\.\w])([a-zA-Z_]\w*)\(',src))
bi={'createobject','len','left','right','mid','int','val','str','lcase','asc','chr','instr','parsejson','formatjson','type','wait','sleep','readasciifile','writeasciifile','if','for','while','function','sub','and','or','not','each','track'}
u=sorted(c for c in calls if c.lower() not in defs and c.lower() not in bi)
if u: print("UNDEFINED",u); bad=True
print("LINT FAILED" if bad else "lint ok")
sys.exit(1 if bad else 0)
