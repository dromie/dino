#!/bin/bash
cp -r $DINO $HOME/
pushd $HOME/DINO/models/dino/ops/
bash make.sh && touch /tmp/model_build_ready
popd
if [ $# -gt 0 ];then
    "$@"
else
    sleep infinity
fi
