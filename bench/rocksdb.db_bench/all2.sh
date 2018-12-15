# OPT="-DNDEBUG -O2" make db_bench # DEBUG_LEVEL=0 make db_bench

dbdir=$1
keys=$2
secs=$3
nthreads=$4
rowlen=$5
wmb_per_sec=$6
write_buf_mb=$7
max_bg_thr=$8
l1_mb=$9
min_level_compress=${10}
comp_type=${11}
cache_mb=${12}
bg_io_mb=${13}
secs_debt=${14}
dbversion=${15}
dbbench=${16}

# Comments on the command line options
# arg 1 - database directory. This must exist. The test won't create it.
# arg 2 - number of keys (keys == rows) to Put into RocksDB
# arg 3 - number of seconds for which each test is run. See below for the tests that are run.
# arg 4 - number of user threads that will be created
# arg 5 - number of bytes for the values that are Put into RocksDB
# arg 6 - rate limit in MB/sec for tests that rate limit the writers
# arg 7 - sets the size of the write buffer (memtable). I usually use 32mb or 64mb for the write buffer
# arg 8 - sets the number of background compaction threads. Start with number-real-cores / 4. Compaction
#         needs CPU but if there are too many then some will get starved and you all need CPU for the
#         application and request handling.
# arg 9 - target size for level 1 of the LSM tree. I usually use 256mb, 512mb or 1024mb. Note that I
#         configured compaction to start when there are 4 files in level 0
#         (--level0_file_num_compaction_trigger=4) and I want sizeof(L0) ~= sizeof(L1) when compaction occurs.
#         The size of L0 files is determined by the size of the write buffer (see arg7). So if you adjust
#         arg 7 then adjust this arg.
# arg 10 - first level in the LSM tree to compress. I usually start compression on level 3 and leave levels 0,
#         1 and 2 uncompressed. I don't compress small levels because the CPU cost is high, but the space
#         savings are small. Compressing L0, L1 and L2 would reduce the total write-rate & write-amplification
#         from compaction, but I don't think it is worth it. Compaction stalls usually happen from L0->L1
#         compaction or from L1->L2 compaction and compression makes that slower, so it increases stalls.
# arg 11 - compression type. This is your choice but when choosing between zstd and zlib I prefer zstd.
#         See http://smalldatum.blogspot.com/2016/09/zlib-vs-zstd-for-myrocks-running.html
# arg 12 - size of the RocksDB block cache. My advice is at
#         http://smalldatum.blogspot.com/2016/09/tuning-rocksdb-block-cache.html
# arg 13 - an estimate of the IO rate that storage & RocksDB supports
# arg 14 - used for compaction throttling. The number of seconds of "IO debt" I allow RocksDB to have before
#          throttling writes. Used with arg 13.
# arg 15 - release number that determines which RocksDB options are used to support this script across many
#          versions. I don't update this for every release so only a few versions are valid. And "leveldb"
#          is a valid version.
# arg 16 - path to db_bench

xkeys=$(( $keys * 1000 ))

if [[ $dbversion = "4.1" ]] ; then
  wps=$(( ( 1024 * 1024 * $wmb_per_sec) / ( $rowlen + 12 ) ))
  ddds="--disable_data_sync=0"
  cpri=""
elif [[ $dbversion = "4.5" ]] ; then
  wps=$(( 1024 * 1024 * $wmb_per_sec ))
  ddds="--disable_data_sync=0"
  cpri=""
  echo "using 4.5"
elif [[ $dbversion = "5.4" || $dbversion = "5.8" ]] ; then
  wps=$(( 1024 * 1024 * $wmb_per_sec ))
  ddds=""
  # enable kMinOverlappingRatio
  cpri="--compaction_pri=3"
  echo "using $dbversion"
elif [[ $dbversion = "leveldb" ]]; then
  wps="" 
  ddds=""
  cpri=""
  echo "using $dbversion"
else
  echo Version $dbversion not supported
  exit -1
fi

killall vmstat
killall iostat

sfx=N${keys}.S${secs}.T${nthreads}

if [[ $dbversion != "leveldb" ]]; then

# --stats_per_interval=1 \
# --stats_interval_seconds=10 \

f1="\
--num=$keys \
--value_size=$rowlen \
--key_size=8 \
--max_write_buffer_number=4 \
--write_buffer_size=$(( 1024 * 1024 * $write_buf_mb )) \
--target_file_size_base=$(( 1024 * 1024 * $write_buf_mb )) \
--max_background_compactions=$max_bg_thr \
--max_background_flushes=2 \
--cache_index_and_filter_blocks=1 \
--pin_l0_filter_and_index_blocks_in_cache=1 \
--block_size=8192 \
--cache_size=$(( 1024 * 1024 * $cache_mb )) \
--level_compaction_dynamic_level_bytes=1 \
--max_bytes_for_level_base=$(( 1024 * 1024 * $l1_mb )) \
--compression_type=${comp_type} \
--min_level_to_compress=$min_level_compress \
--bytes_per_sync=$(( 1024 * 1024 * 8 )) \
--wal_bytes_per_sync=$(( 1024 * 1024 * 8 )) \
--statistics=0 \
--histogram=0 \
--bloom_bits=10 \
--open_files=-1 \
--sync=0 \
--disable_wal=0 \
$dds \
$cpri \
--max_total_wal_size=$(( 1024 * 1024 * 1024 )) \
--verify_checksum=1"

f2="\
--use_existing_db=0 \
--threads=1"

else

f1="\
--num=$keys \
--value_size=$rowlen \
--write_buffer_size=$(( 1024 * 1024 * $write_buf_mb )) \
--block_size=8192 \
--cache_size=$(( 1024 * 1024 * $cache_mb )) \
--max_file_size=$(( 1024 * 1024 * $write_buf_mb )) \
--histogram=0 \
--bloom_bits=10 \
--open_files=10000"

f2="\
--use_existing_db=0 \
--threads=1"

fi

if [[ $dbversion = "leveldb" ]]; then
seed=""
else
seed="--seed=$( date +%s )"
fi

echo Run fillrandom $keys keys $( date )
vmstat 10 >& o.vm.fillseq.$sfx &
vpid=$!
iostat -kx 10 >& o.io.fillseq.$sfx &
ipid=$!
${dbbench} --db=$dbdir --benchmarks=fillrandom $f1 $f2 $seed >& o.fillrandom.$sfx
echo ${dbbench} --db=$dbdir --benchmarks=fillrandom $f1 $f2 $seed >> o.fillrandom.$sfx
du -hs $dbdir >> o.fillrandom.$sfx
kill $vpid
kill $ipid

if [[ $dbversion != "leveldb" ]]; then
f2="\
--seek_nexts=100 \
--duration=$secs \
--writes=$xkeys \
--use_existing_db=1 \
--level0_file_num_compaction_trigger=4 \
--level0_slowdown_writes_trigger=12 \
--level0_stop_writes_trigger=20 \
--hard_pending_compaction_bytes_limit=$(( 1024 * 1024 * $bg_io_mb * $secs_debt ))  \
--rate_limiter_bytes_per_sec=$(( 1024 * 1024 * $bg_io_mb )) \
--threads=$nthreads"

else
f2="\
--use_existing_db=1 \
--threads=$nthreads"

fi

if [[ $dbversion = "4.1" ]] ; then
  echo Skip for 4.1 
elif [[ $dbversion = "4.5" || $dbversion = "5.4" || $dbversion = "5.8" ]] ; then
  f2="$f2 --soft_pending_compaction_bytes_limit=$(( 1024 * 512 * $bg_io_mb * $secs_debt )) \
      --allow_concurrent_memtable_write \
      --enable_write_thread_adaptive_yield"
elif [[ $dbversion = "leveldb" ]]; then
  echo Skip for leveldb
else
  echo Version $dbversion not supported
  exit -1
fi

if [[ $dbversion = "foobar" ]]; then
echo Run overwrite $keys keys at $( date )
seed="--seed=$( date +%s )"
vmstat 10 >& o.vm.overwrite.all.$sfx &
vpid=$!
iostat -kx 10 >& o.io.overwrite.all.$sfx &
ipid=$!
${dbbench} --db=$dbdir --benchmarks=overwrite $f1 $f2 $seed >& o.overwrite.secs.$sfx
echo ${dbbench} --db=$dbdir --benchmarks=overwrite $f1 $f2 $seed >> o.overwrite.secs.$sfx
du -hs $dbdir >> o.overwrite.all.$sfx
kill $vpid
kill $ipid
fi

if [[ $dbversion = "4.1" ]] ; then
  f2="$f2 --writes_per_second=$wps"
elif [[ $dbversion = "4.5" || $dbversion = "5.4" || $dbversion = "5.8" ]] ; then
  f2="$f2 --benchmark_write_rate_limit=$wps"
elif [[ $dbversion = "leveldb" ]]; then
  echo Skip for leveldb
else
  echo Version $dbversion not supported
  exit -1
fi

for t in readrandom seekrandom ; do
echo Run $t $secs seconds at $( date )
vmstat 10 >& o.vm.$t.secs.$sfx &
vpid=$!
iostat -kx 10 >& o.io.$t.secs.$sfx &
ipid=$!

xa=""
if [[ $dbversion = "leveldb" ]]; then
  seed=""
  if [[ $t = "readrandom" ]]; then
    xa="--reads=$(( 10 * $keys )) "
  fi
else
seed="--seed=$( date +%s )"
fi

${dbbench} --db=$dbdir --benchmarks=$t $f1 $f2 $seed $xa >& o.$t.secs.$sfx &
dpid=$!
sleep 60; bash perf2.sh $t $( pidof db_bench )
wait $dpid

echo ${dbbench} --db=$dbdir --benchmarks=$t $f1 $f2 $seed $xa >> o.$t.secs.$sfx
du -hs $dbdir >> o.$t.secs.$sfx
kill $vpid
kill $ipid
done

grep "^fillrandom" o.fillrandom.$sfx > o.res.$sfx
grep "^overwrite" o.overwrite.secs.$sfx >> o.res.$sfx
for t in readwhilewriting seekrandomwhilewriting readrandom seekrandom ; do grep "^$t" o.$t.secs.$sfx; done >> o.res.$sfx
