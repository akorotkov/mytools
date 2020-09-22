dop=$1
m=$2

allq="q.L1.ips100 q.L2.ips100 q.L3.ips200 q.L4.ips200 q.L5.ips400 q.L6.ips400 q.L7.ips600 q.L8.ips600 q.L9.ips800 q.L10.ips800 q.L11.ips1000 q.L12.ips1000"

for d1 in ${m}m.* ; do for d2 in l.i0 l.i1 $allq ; do bash rth.sh ${d1} ${d2} $dop "Insert rt" > ${d1}/${d2}/o.rt.c.insert ; done; done

for d1 in ${m}m.* ; do for d2 in l.i0 l.i1 $allq ; do bash rth.sh ${d1} ${d2} $dop "Insert rt" | tr ',' '\t' > ${d1}/${d2}/o.rt.t.insert ; done; done

for d1 in ${m}m.* ; do for d2 in l.i0 l.i1 $allq ; do bash rth.sh ${d1} ${d2} $dop "Query rt" > ${d1}/${d2}/o.rt.c.query ; done; done

for d1 in ${m}m.* ; do for d2 in l.i0 l.i1 $allq ; do bash rth.sh ${d1} ${d2} $dop "Query rt" | tr ',' '\t' > ${d1}/${d2}/o.rt.t.query ; done; done
