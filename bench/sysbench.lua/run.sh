ntabs=$1
nr=$2
secs=$3
dbAndCreds=$4
setup=$5
cleanup=$6
testType=$7
range=$8
client=$9
tableoptions=${10}
sysbdir=${11}
ddir=${12}
dname=${13}
usepk=${14}

#echo $@
shift 14

samp=1
nsamp=10000000

realdop=$( cat /proc/cpuinfo | grep "^processor" | wc -l )
#echo $realdop CPUs

testArgs=(--rand-type=uniform)

if [[ $testType == "read-only" || $testType == "read-only.pre" ]]; then
  lua="oltp_read_only.lua"
elif [[ $testType == "read-only-count" ]]; then
  lua="oltp_read_only_count.lua"
  testArgs=(--rand-type=uniform --skip-trx)
elif [[ $testType == "read-write" ]]; then
  lua="oltp_read_write.lua"
elif [[ $testType == "write-only" ]]; then
  lua="oltp_write_only.lua"
elif [[ $testType == "delete" ]]; then
  lua="oltp_delete.lua"
elif [[ $testType == "update-inlist" ]]; then
  lua="oltp_inlist_update.lua"
elif [[ $testType == "update-one" ]]; then
  lua="oltp_update_non_index.lua"
  nr=1
elif [[ $testType == "update-nonindex" ]]; then
  lua="oltp_update_non_index.lua"
elif [[ $testType == "update-zipf" ]]; then
  testArgs=(--rand-type=zipfian)
  lua="oltp_update_non_index.lua"
elif [[ $testType == "update-index" ]]; then
  lua="oltp_update_index.lua"
elif [[ $testType == "update-rate" ]]; then
  lua="oltp_update_rate.lua"
  testArgs=(--rand-type=uniform --update-rate=1000)
elif [[ $testType == "point-query" || $testType == "point-query.pre" || $testType == "point-query.warm" ]]; then
  lua="oltp_point_select.lua"
  testArgs=(--rand-type=uniform --skip-trx)
elif [[ $testType == "random-points" || $testType == "random-points.pre" ]]; then
  testArgs=(--rand-type=uniform --random-points=$range --skip-trx)
  lua="oltp_inlist_select.lua"
elif [[ $testType == "hot-points" ]]; then
  testArgs=(--rand-type=uniform --random-points=$range --hot-points --skip-trx)
  lua="oltp_inlist_select.lua"
elif [[ $testType == "points-covered-pk" || $testType == "points-covered-pk.pre" ]]; then
  lua="oltp_points_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx)
elif [[ $testType == "points-covered-si" || $testType == "points-covered-si.pre" ]]; then
  lua="oltp_points_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --on-id=false)
elif [[ $testType == "points-notcovered-pk" || $testType == "points-notcovered-pk.pre" ]]; then
  lua="oltp_points_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --covered=false)
elif [[ $testType == "points-notcovered-si" || $testType == "points-notcovered-si.pre" ]]; then
  lua="oltp_points_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --on-id=false --covered=false)
elif [[ $testType == "range-covered-pk" || $testType == "range-covered-pk.pre" ]]; then
  lua="oltp_range_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx)
elif [[ $testType == "range-covered-si" || $testType == "range-covered-si.pre" ]]; then
  lua="oltp_range_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --on-id=false)
elif [[ $testType == "range-notcovered-pk" || $testType == "range-notcovered-pk.pre" ]]; then
  lua="oltp_range_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --covered=false)
elif [[ $testType == "range-notcovered-si" || $testType == "range-notcovered-si.pre" ]]; then
  lua="oltp_range_covered.lua"
  testArgs=(--rand-type=uniform --skip-trx --on-id=false --covered=false)
elif [[ $testType == "insert" ]]; then
  lua="oltp_insert.lua"
else
echo Did not recognize testType $testType
exit 1
fi

IFS=","; read -ra dbA <<< "$dbAndCreds"
if [[ ${dbA[0]} == "mysql" ]]; then
  if [[ ${#dbA[@]} -ne 6 ]]; then
    echo "For MySQL expect 6 args (mysql,user,password,host,db,engine) got ${#dbA[@]} args from $dbAndCreds"
    exit -1
  fi

  sbDbCreds=(--mysql-user=${dbA[1]} --mysql-password=${dbA[2]} --mysql-host=${dbA[3]} --mysql-db=${dbA[4]})
  export MYSQL_PWD=${dbA[2]}
  clientArgs=(-u${dbA[1]} -h${dbA[3]} ${dbA[4]})
  engine=${dbA[5]}
  engineArg="--mysql-storage-engine=$engine"
  sqlF=e
  driver="mysql"
  $client "${clientArgs[@]}" -e 'reset master' 2> /dev/null

elif [[ ${dbA[0]} == "postgres" ]]; then
  if [[ ${#dbA[@]} -ne 5 ]]; then
    echo "For Postgres expect 5 args (postgres,user,password,host,db) got ${#dbA[@]} args from $dbAndCreds"
    exit -1
  fi
  sbDbCreds=(--pgsql-user=${dbA[1]} --pgsql-password=${dbA[2]} --pgsql-host=${dbA[3]} --pgsql-db=${dbA[4]})
  export PGPASSWORD=${dbA[2]}
  clientArgs=(-U${dbA[1]} -h${dbA[3]} ${dbA[4]})
  engine="pgsql"
  engineArg=""
  sqlF=c
  driver="pgsql"

else
  echo Could not parse dbAndCreds :: $dbAndCreds :: and first arg is ${dbA[0]}
  exit -1
fi

prepareArgs=""
if [[ $usepk -eq 0 ]]; then
  prepareArgs="--secondary "
fi

sfx="${testType}.range${range}.pk${usepk}"

# --- Setup ---

if [[ $setup == 1 ]]; then

echo Setup for $ntabs tables > sb.prepare.o.$sfx
echo Setup for $ntabs tables

for x in $( seq 1 $ntabs ); do
  echo Drop table sbtest${x} >> sb.prepare.o.$sfx
  $client "${clientArgs[@]}" -${sqlF} "drop table if exists sbtest${x}" >> sb.prepare.o.$sfx 2>&1
  echo Done drop >> sb.prepare.o.$sfx
done

killall vmstat >& /dev/null
killall iostat >& /dev/null
vmstat $samp $nsamp >& sb.prepare.vm.$sfx &
vmpid=$!
iostat -y -kx $samp $nsamp >& sb.prepare.io.$sfx &
iopid=$!
start_secs=$( date +'%s' )

exA=(--db-driver=$driver $setupArgs $engineArg --range-size=$range --table-size=$nr --tables=$ntabs --events=0 --time=$secs $sysbdir/share/sysbench/$lua $prepareArgs prepare)
echo $sysbdir/bin/sysbench "${exA[@]}" "${sbDbCreds[@]}" >> sb.prepare.o.$sfx
$sysbdir/bin/sysbench "${exA[@]}" "${sbDbCreds[@]}" >> sb.prepare.o.$sfx 2>&1
status=$?
if [[ $status != 0 ]]; then
  echo sysbench prepare failed, see sb.prepare.o.$sfx
  exit -1
fi

stop_secs=$( date +'%s' )
tot_secs=$(( $stop_secs - $start_secs ))
mrps=$( echo "scale=3; ( $ntabs * $nr ) / $tot_secs / 1000000.0" | bc )
rps=$( echo "scale=0; ( $ntabs * $nr ) / $tot_secs" | bc )
echo "Load seconds is $tot_secs for $ntabs tables, $mrps Mips, $rps ips" >> sb.prepare.o.$sfx

kill $vmpid
kill $iopid
bash an.sh sb.prepare.io.$sfx sb.prepare.vm.$sfx $dname $rps $realdop > sb.prepare.met.$sfx

if [[ $driver == "mysql" ]]; then
  $client "${clientArgs[@]}" -e 'reset master' 2> /dev/null
  for x in $( seq 1 $ntabs ); do
    echo Analyze table sbtest${x} >> sb.prepare.o.$sfx
    $client "${clientArgs[@]}" -${sqlF} "analyze table sbtest${x}" >> sb.prepare.o.$sfx 2>&1
    pids[${n}]=$!
  done

  for x in $( seq 1 $ntabs ); do
    wait ${pids[${n}]}
  done

elif [[ $driver == "pgsql" ]]; then
  for x in $( seq 1 $ntabs ); do
    echo Vacuum analyze table sbtest${x} >> sb.prepare.o.$sfx
    $client "${clientArgs[@]}" -${sqlF} "vacuum (analyze, verbose) sbtest${x}" >> sb.prepare.o.$sfx 2>&1
    pids[${n}]=$!
  done

  for x in $( seq 1 $ntabs ); do
    wait ${pids[${n}]}
  done
fi

fi

# --- run sysbench tests ---

rm -f sb.r.trx.$sfx sb.r.qps.$sfx sb.r.rtavg.$sfx sb.r.rtmax.$sfx sb.r.rt95.$sfx

for nt in "$@"; do
echo Run for $nt threads at $( date )

sfxn="$sfx.dop${nt}"
killall vmstat >& /dev/null
killall iostat >& /dev/null
vmstat $samp $nsamp >& sb.vm.$sfxn &
vmpid=$!
iostat -y -kx $samp $nsamp >& sb.io.$sfxn &
iopid=$!

exA=(--db-driver=$driver --range-size=$range --table-size=$nr --tables=$ntabs --threads=$nt --events=0 --warmup-time=5 --time=$secs $sysbdir/share/sysbench/$lua run)
echo $sysbdir/bin/sysbench "${exA[@]}" "${sbDbCreds[@]}" "${testArgs[@]}"  > sb.o.$sfxn
echo "$realdop CPUs" >> sb.o.$sfxn
$sysbdir/bin/sysbench "${exA[@]}" "${sbDbCreds[@]}" "${testArgs[@]}" >> sb.o.$sfxn 2>&1

kill $vmpid
kill $iopid
qps=$( grep queries: sb.o.$sfxn | awk '{ print $3 }' | tr -d '(' )
bash an.sh sb.io.$sfxn sb.vm.$sfxn $dname $qps $realdop > sb.met.$sfxn

if [[ $driver == "mysql" ]]; then
  $client "${clientArgs[@]}" -e "show engine $engine status\G" >& sb.es.$sfx
  $client "${clientArgs[@]}" -e "show indexes from sbtest1\G" >& sb.is.$sfx
  $client "${clientArgs[@]}" -e "show global variables" >& sb.gv.$sfx
  $client "${clientArgs[@]}" -e "show global status\G" >& sb.gs.$sfx
  $client "${clientArgs[@]}" -e "show table status\G" >& sb.ts.$sfx
  $client "${clientArgs[@]}" -e 'reset master' 2> /dev/null

elif [[ $driver == "pgsql" ]]; then
  $client "${clientArgs[@]}" -c 'show all' > sb.pg.conf.$sfx
  $client "${clientArgs[@]}" -x -c 'select * from pg_stat_bgwriter' > sb.pgs.bg.$sfx
  $client "${clientArgs[@]}" -x -c 'select * from pg_stat_database' > sb.pgs.db.$sfx
  $client "${clientArgs[@]}" -x -c "select * from pg_stat_all_tables where schemaname='public'" > sb.pgs.tabs.$sfx
  $client "${clientArgs[@]}" -x -c "select * from pg_stat_all_indexes where schemaname='public'" > sb.pgs.idxs.$sfx
  $client "${clientArgs[@]}" -x -c "select * from pg_statio_all_tables where schemaname='public'" > sb.pgi.tabs.$sfx
  $client "${clientArgs[@]}" -x -c "select * from pg_statio_all_indexes where schemaname='public'" > sb.pgi.idxs.$sfx
  $client "${clientArgs[@]}" -x -c 'select * from pg_statio_all_sequences' > sb.pgi.seq.$sfx
fi

echo "sum of data and index length columns in GB" >> sb.ts.$sfx
cat sb.ts.$sfx  | grep "Data_length"  | awk '{ s += $2 } END { printf "%.3f\n", s / (1024*1024*1024) }' >> sb.ts.$sfx
cat sb.ts.$sfx  | grep "Index_length" | awk '{ s += $2 } END { printf "%.3f\n", s / (1024*1024*1024) }' >> sb.ts.$sfx

done

du -hs $ddir > sb.sz.$sfx
echo "with apparent size " >> sb.sz.$sfx
du -hs --apparent-size $ddir >> sb.sz.$sfx
echo "all" >> sb.sz.$sfx
du -hs ${ddir}/* >> sb.sz.$sfx

if [[ $cleanup == 1 ]]; then

echo Cleanup
echo Cleanup > sb.cleanup.$sfx
for x in $( seq 1 $ntabs ); do
  echo Drop table sbtest${x} >> sb.cleanup.$sfx
  $client "${clientArgs[@]}" -${sqlF} "drop table if exists sbtest${x}" >> sb.prepare.$sfx 2>&1
done

fi

for nt in "$@"; do
  grep transactions: sb.o.$sfx.dop${nt} | awk '{ print $3 }' | tr -d '(' | awk '{ printf "%.0f\t", $1 }' 
done > sb.r.trx.$sfx
echo "$engine $testType range=$range" >> sb.r.trx.$sfx

for nt in "$@"; do
  grep queries: sb.o.$sfx.dop${nt} | awk '{ print $3 }' | tr -d '(' | awk '{ printf "%.0f\t", $1 }' 
done > sb.r.qps.$sfx
echo "$engine $testType range=$range" >> sb.r.qps.$sfx

for nt in "$@"; do
  grep avg: sb.o.$sfx.dop${nt} | awk '{ print $2 }' | awk '{ printf "%s\t", $1 }' 
done > sb.r.rtavg.$sfx
echo "$engine $testType range=$range" >> sb.r.rtavg.$sfx

for nt in "$@"; do
  grep max: sb.o.$sfx.dop${nt} | awk '{ print $2 }' | awk '{ printf "%s\t", $1 }' 
done > sb.r.rtmax.$sfx
echo "$engine $testType range=$range" >> sb.r.rtmax.$sfx

for nt in "$@"; do
  grep percentile: sb.o.$sfx.dop${nt} | awk '{ print $3 }' | awk '{ printf "%s\t", $1 }' 
done > sb.r.rt95.$sfx
echo "$engine $testType range=$range" >> sb.r.rt95.$sfx

