#!/bin/bash
pushd $DINO/models/dino/ops/
bash make.sh
popd
if [ $# -gt 0 ];then
    "$@"
else
    sleep infinity
fi
