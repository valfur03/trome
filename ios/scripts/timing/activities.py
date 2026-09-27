import json,subprocess,sys
path=sys.argv[1]
tests=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','tests','--path',path]))
ids=[]
def walk(n):
    if n.get('nodeType')=='Test Case': ids.append(n['nodeIdentifier'])
    for c in n.get('children',[]): walk(c)
for t in tests['testNodes']: walk(t)
maxdepth=int(sys.argv[2]) if len(sys.argv)>2 else 1
for tid in ids:
    d=json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','activities','--test-id',tid,'--path',path]))
    print('=====',tid)
    for r in d['testRuns']:
        out=[]
        def w(a,depth):
            for x in a:
                out.append((depth,x.get('startTime'),x['title'],len(x.get('attachments',[]))))
                w(x.get('childActivities',[]),depth+1)
        w(r['activities'],0)
        top=[o for o in out if o[1] is not None and o[0]<=maxdepth]
        t0=top[0][1]
        for i,(dp,t,title,att) in enumerate(top):
            nxt=top[i+1][1] if i+1<len(top) else None
            dur=(nxt-t) if nxt else 0
            print(f"{t-t0:6.1f} {dur:5.1f} {'  '*dp}{title[:110]}{' [att %d]'%att if att else ''}")
