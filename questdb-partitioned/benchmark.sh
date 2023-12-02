#!/bin/bash

# Install

wget https://github.com/questdb/questdb/releases/download/7.3.5/questdb-7.3.5-rt-linux-amd64.tar.gz
tar xf questdb*.tar.gz --one-top-level=questdb --strip-components 1
questdb/bin/questdb.sh start

while ! nc -z localhost 9000; do
  sleep 0.1
done

sed -i 's/query.timeout.sec=60/query.timeout.sec=500/' ~/.questdb/conf/server.conf
sed -i "s|#cairo.sql.copy.root=null|cairo.sql.copy.root=$PWD|" ~/.questdb/conf/server.conf
questdb/bin/questdb.sh stop
questdb/bin/questdb.sh start

# Import the data

wget --no-verbose --continue 'https://datasets.clickhouse.com/hits_compatible/hits.csv.gz'
gzip -d hits.csv.gz

curl -G --data-urlencode "query=$(cat create.sql)" 'http://localhost:9000/exec'
curl -G --data-urlencode "query=copy hits from 'hits.csv' with timestamp 'EventTime' format 'yyyy-MM-dd HH:mm:ss';" 'http://localhost:9000/exec'

echo 'waiting for import to finish...'
until [ "$(curl -s -G --data-urlencode "query=select * from sys.text_import_log where phase is null and status='finished';" 'http://localhost:9000/exec' | grep -c '"count":1')" -ge 1 ]; do
    echo '.'
    sleep 5
done

curl -s -G --data-urlencode "query=select datediff('s', start, finish) took_secs from (select min(ts) start, max(ts) finish from sys.text_import_log where phase is null);" 'http://localhost:9000/exec'

# Run queries

./run.sh 2>&1 | tee log.txt

du -bcs ~/.questdb/db/hits*

cat log.txt | grep -P '"timings"|"error"|null' | sed -r -e 's/^.*"error".*$/null/; s/^.*"execute":([0-9]*),.*$/\1/' |
  awk '{ print ($1) / 1000000000 }' | sed -r -e 's/^0$/null/' |
  awk '{ if (i % 3 == 0) { printf "[" }; printf $1; if (i % 3 != 2) { printf "," } else { print "]," }; ++i; }'
