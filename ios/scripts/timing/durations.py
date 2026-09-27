import json,sys
d=json.load(sys.stdin)
def walk(n,depth=0):
    if n.get('nodeType') in ('Test Suite','Test Case'):
        print('  '*depth, n.get('nodeType'), n.get('name'), n.get('result'), n.get('duration'))
    for c in n.get('children',[]):
        walk(c,depth+1)
for t in d['testNodes']: walk(t)
