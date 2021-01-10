#!/bin/bash

head -n 200 "../data/$2/train.$1" > "temp/dev.$1"
head -n 200 "../data/$2/train.es" > "temp/dev.es"
tail -n +201 "../data/$2/train.$1" | head -n 200 > "temp/test.$1"
tail -n +201 "../data/$2/train.es" | head -n 200 > "temp/test.es"
tail -n +401 "../data/$2/train.$1" > "temp/train.$1"
tail -n +401 "../data/$2/train.es" > "temp/train.es"

./run_baseline_system.sh $1 temp "save/$1" 30 > "log_$1.txt" #2> /dev/null > /dev/null
#echo $2
#python3 ../evaluate.py --system_output "save/$1/translations/$1_es.bpe.hyp" --gold_reference "save/$1/translations/$1_es.bpe.ref"

