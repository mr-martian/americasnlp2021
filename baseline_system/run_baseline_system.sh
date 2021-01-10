#!/bin/bash

set -e

TGT_FILE=$1
SRC_FILE=es

DATA_DIR=$2
SAVE_DIR=$3

EPOCHS=$4

FAIRSEQ_PREPROCESS=fairseq-preprocess
FAIRSEQ_TRAIN=fairseq-train
FAIRSEQ_GENERATE=fairseq-generate

EVALUATE="python3 ../evaluate.py"

MODELS=${SAVE_DIR}/models/${TGT_FILE}_${SRC_FILE}
CHECKPOINTS=${SAVE_DIR}/checkpoints/${TGT_FILE}_${SRC_FILE}
LOGS=${SAVE_DIR}/logs/${TGT_FILE}_${SRC_FILE}
TRANSLATIONS=${SAVE_DIR}/translations/${TGT_FILE}_${SRC_FILE}
DATA_OUT=${SAVE_DIR}/data_out/${TGT_FILE}_${SRC_FILE}

mkdir -p ${MODELS} ${CHECKPOINTS} ${LOGS} ${DATA_OUT} ${TRANSLATIONS}

echo "################ Training SentencePiece tokenizer ################"

python3 sp_tools.py \
  --train \
  --src ${SRC_FILE} \
  --tgt ${TGT_FILE} \
  --data_dir ${DATA_DIR}/ \
  --model_dir ${MODELS}/ \
  --vocab_size 3557
  
echo "################ Done training ################"
#Vocab size may need to be changed depending on training files (3560 for pilot data train)

tail -n +4 ${MODELS}/sentencepiece.bpe.vocab | cut -f1 | sed 's/$/ 100/g' > $MODELS/fairseq.dict

echo "################ Tokenizing data ################"

python3 sp_tools.py \
  --encode \
  --src ${SRC_FILE} \
  --tgt ${TGT_FILE} \
  --data_dir ${DATA_DIR}/ \
  --data_out ${DATA_OUT}/ \
  --model_dir ${MODELS}/ \
  --vocab_size 5000

echo "################ Done tokenizing ################"

echo "################ Encoding Data ################"

${FAIRSEQ_PREPROCESS}  --source-lang $SRC_FILE --target-lang $TGT_FILE \
    --trainpref $DATA_OUT/train.bpe \
    --validpref $DATA_OUT/dev.bpe \
    --destdir $DATA_OUT \
    --srcdict $MODELS/fairseq.dict \
    --tgtdict $MODELS/fairseq.dict \
    --thresholdtgt 0 \
    --thresholdsrc 0 \
    --workers 4 \
#    --testpref $DATA_OUT/test.bpe \

echo "################ Done encoding ################"

echo "################ Starting training ################"

${FAIRSEQ_TRAIN} \
    $DATA_OUT \
    --source-lang $SRC_FILE --target-lang $TGT_FILE \
    --arch transformer --share-all-embeddings \
    --encoder-layers 5 --decoder-layers 5 \
    --encoder-embed-dim 512 --decoder-embed-dim 512 \
    --encoder-ffn-embed-dim 2048 --decoder-ffn-embed-dim 2048 \
    --encoder-attention-heads 2 --decoder-attention-heads 2 \
    --encoder-normalize-before --decoder-normalize-before \
    --dropout 0.4 --attention-dropout 0.2 --relu-dropout 0.2 \
    --weight-decay 0.0001 \
    --label-smoothing 0.2 --criterion label_smoothed_cross_entropy \
    --optimizer adam --adam-betas '(0.9, 0.98)' --clip-norm 0 \
    --lr-scheduler inverse_sqrt --warmup-updates 4000 --warmup-init-lr 1e-7 \
    --lr 1e-3 --stop-min-lr 1e-9 \
    --max-tokens 1000 \
    --update-freq 4 \
    --max-epoch $EPOCHS --save-interval 1 \
    --tensorboard-logdir $LOGS \
    --save-dir $CHECKPOINTS \
    --skip-invalid-size-inputs-valid-test \
    --no-epoch-checkpoints \
    --no-last-checkpoints \
    --keep-best-checkpoints 1

echo "################ Done training, starting evaluation ################"

${FAIRSEQ_GENERATE} \
      $DATA_OUT  \
    --source-lang $SRC_FILE --target-lang $TGT_FILE \
    --path $CHECKPOINTS/checkpoint_best.pt \
    --beam 5 --lenpen 1.2 \
    --gen-subset valid \
    --remove-bpe=sentencepiece \
    --no-progress-bar  > $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.out


cat $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.out | grep -P "^H" |sort -V |cut -f 3- | sed 's/\[ro_RO\]//g'  > $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.bpe.hyp
cat $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.out | grep -P "^T" |sort -V |cut -f 2- | sed 's/\[ro_RO\]//g'  > $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.bpe.ref

echo "################ Done decoding ################"

${EVALUATE} \
  --system_output $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.bpe.hyp \
  --gold_reference  $TRANSLATIONS/${TGT_FILE}_${SRC_FILE}.bpe.ref
