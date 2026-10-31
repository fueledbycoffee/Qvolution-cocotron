# Independent high-precision Table 5 evaluation for fixed-vector provenance.
# Does not import, parse or call production transfer code.
from decimal import Decimal as D, getcontext
getcontext().prec=60
a=D('0.17883277'); b=1-4*a; c=D('.5')-a*(4*a).ln()
for x in map(D,['0','0.25','0.499999','0.5','0.500001','0.75','1']):
    e=x*x/3 if x <= D('.5') else (((x-c)/a).exp()+b)/12
    print('inverse',x,e)
for e in map(D,['0','0.0833333333333333333333333333333333333333333333333333333333333','1']):
    x=(3*e).sqrt() if e <= 1/D(12) else a*(12*e-b).ln()+c
    print('forward',e,x)
for peak in map(D,['400','1000','2000']):
    gamma=D('1.2')+D('.42')*(peak/1000).log10()
    for rgb in [(D(1)/12,)*3,(D(1),D(0),D(0))]:
        y=D('.2627')*rgb[0]+D('.6780')*rgb[1]+D('.0593')*rgb[2]
        print('ootf',peak,rgb,tuple(peak*y**(gamma-1)*v for v in rgb))
