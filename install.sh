#!/bin/bash -e
self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

KUBEFLOW_VERSION=v1.7.0

start_minikube() {
  minikube start --kubernetes-version=1.25.3 --network=bridge
  if [ ! -d manifests ];then 
    git clone https://github.com/kubeflow/manifests.git $KUBEFLOW_VERSION
    cd manifests
  else
    cd manifests
    git reset --hard $KUBEFLOW_VERSION

  fi
  #dinominikube
  sed -i -e 's/email:.*/email: nandor.galambosi@gmail.com/' -e 's/hash:.*$/hash: $2y$12$iA8Y5KrPrWNSclGxICEb8uThXX4XR33xNiVk0xmo4.Nv4evaL3niC/' common/dex/base/config-map.yaml
  while ! kustomize build example | awk '!/well-defined/' | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
  kubectl wait pod --for=condition=Ready -A --all
}

curl_download() {
  BN=$(basename $1)
  if [ ! -f "${self_dir}/data/$BN" ];then
    curl -o "${self_dir}/data/$BN" -C - "$1"
  fi
}

gsutil_download() {
  ${self_dir}/data/gcli/bin/gsutil -m rsync gs://images.cocodataset.org/$1 ${self_dir}/data/$1
}

download() {
  curl_download "$@"
}

get_data() {
  mkdir -p ${self_dir}/data/gcli
  #curl -o ${self_dir}/data/gcli/gcloudcli.tar.gz -C - 'https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-430.0.0-linux-x86_64.tar.gz'
  #tar xzf ${self_dir}/data/gcli/gcloudcli.tar.gz -C ${self_dir}/data/gcli
  cd ${self_dir}/data

  download 'http://images.cocodataset.org/zips/train2017.zip'
  download 'http://images.cocodataset.org/zips/val2017.zip'
  download 'http://images.cocodataset.org/zips/test2017.zip'
  download 'http://images.cocodataset.org/annotations/annotations_trainval2017.zip'
  download 'http://images.cocodataset.org/annotations/stuff_annotations_trainval2017.zip'
  download 'http://images.cocodataset.org/annotations/panoptic_annotations_trainval2017.zip'
  download 'http://images.cocodataset.org/annotations/image_info_test2017.zip'
}


"$@"