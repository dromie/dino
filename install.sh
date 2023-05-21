#!/bin/bash -e
self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd )"

K8S_VERSION=1.25.3
KUBEFLOW_VERSION=v1.7.0
STORAGE_DIR="/data"
NFS_DIR=$STORAGE_DIR/nfs_export
REGISTRY_DIR=$STORAGE_DIR/registry
CACHE_DIR=$STORAGE_DIR/cache
if [ -f $REGISTRY_DIR/url ];then 
  source $REGISTRY_DIR/url
fi
if [ -f $CACHE_DIR/url ];then 
  source $CACHE_DIR/url
fi

export PATH=${self_dir}/bin:$PATH

restart_infra() {
  mkdir -p $NFS_DIR $REGISTRY_DIR $CACHE_DIR
  docker stop nfs || true
  docker stop registry || true
  docker stop cache || true
  docker rm nfs || true
  docker rm registry || true
  docker run -d --net=host --privileged --name nfs -v $NFS_DIR:/exports --rm gcr.io/google-samples/nfs-server:1.1
  docker run -d --rm --name registry -p 5000:5000 -v $REGISTRY_DIR:/var/lib/registry:Z registry:2 /var/lib/registry/config.yml
  docker run -d --rm --name cache -p 5001:5000 -v $CACHE_DIR:/var/lib/registry:Z registry:2 /var/lib/registry/config.yml
  while ! curl --cacert $REGISTRY_DIR/server.crt https://$REGISTRY; do sleep 5;done
  while ! curl --cacert $CACHE_DIR/server.crt https://$CACHE; do sleep 5;done
}

create_registry_config() {
  DOMAIN=${DOMAIN:-$1}
  mkdir -p $REGISTRY_DIR
  mkdir -p $CACHE_DIR
  openssl genrsa -out $REGISTRY_DIR/server.key 4096
  openssl req -key $REGISTRY_DIR/server.key -new -out $REGISTRY_DIR/server.csr -subj "/C=HU/ST=Budapest/L=Budapest/emailAddress=admin@kubeflow.com/CN=${DOMAIN:?Please specify domain}"
  openssl x509 -signkey $REGISTRY_DIR/server.key -in $REGISTRY_DIR/server.csr -req -days 365 -out $REGISTRY_DIR/server.crt
  cp $REGISTRY_DIR/server.* $CACHE_DIR/
  cat <<EOF >$REGISTRY_DIR/config.yml
version: 0.1
log:
  level: info
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :5000
  tls:
    certificate: /var/lib/registry/server.crt
    key: /var/lib/registry/server.key
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
  cat <<EOF >$CACHE_DIR/config.yml
version: 0.1
log:
  level: info
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
  delete:
    enabled: true
http:
  addr: :5000
  tls:
    certificate: /var/lib/registry/server.crt
    key: /var/lib/registry/server.key
  headers:
    X-Content-Type-Options: [nosniff]
proxy:
  remoteurl: https://registry-1.docker.io
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
  echo "export REGISTRY=$DOMAIN:5000" >$REGISTRY_DIR/url
  echo "export CACHE=$DOMAIN:5001" >$CACHE_DIR/url
  source $REGISTRY_DIR/url
  source $CACHE_DIR/url
}

start_minikube() {
  minikube start --cpus=max --kubernetes-version=${K8S_VERSION} --network=bridge --apiserver-ips=0.0.0.0 --insecure-registry=0.0.0.0/0 --registry-mirror=https://$DOMAIN:5001
  kubectl apply -f ${self_dir}/files/sysadmin.yaml
  kubectl create ns gpu-operator --dry-run=client -o yaml|kubectl apply -f -
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
  helm upgrade --install --wait -n gpu-operator --create-namespace gpu-operator nvidia/gpu-operator
  if [ ! -d manifests ];then 
    git clone https://github.com/kubeflow/manifests.git -b $KUBEFLOW_VERSION
    cd manifests
  else
    cd manifests
    git reset --hard $KUBEFLOW_VERSION
  fi
  #dinominikube
  sed -i -e 's/email:.*/email: dino@kubeflow.com/' -e 's/hash:.*$/hash: $2y$12$iA8Y5KrPrWNSclGxICEb8uThXX4XR33xNiVk0xmo4.Nv4evaL3niC/' common/dex/base/config-map.yaml
  sed -i 's/CD_REGISTRATION_FLOW=.*/CD_REGISTRATION_FLOW=true/' apps/centraldashboard/upstream/base/params.env
  while ! kustomize build example | awk '!/well-defined/' | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
  while ! kubectl wait pod --for=condition=Ready -A --all;do 
	  sleep 30
	  kubectl get pods  -A  -o json|jq -r '.items[]|select(.status.phase=="Succeeded").metadata|"-n "+.namespace+" "+.name' | xargs -L1 kubectl delete pod || true
  done
  kubectl apply -f ${self_dir}/files/user.yaml

  export DOMAIN=$(openssl x509 -in $REGISTRY_DIR/server.crt -subject -noout | sed 's/^.*CN = \([^ ]*\).*$/\1/')
  envsubst <${self_dir}/files/ingress-cert.yaml | kubectl apply -f -
  kubectl -n istio-system  patch svc istio-ingressgateway -p '{"spec": { "type": "LoadBalancer"}}'
  kubectl -n kubeflow patch gateways.networking.istio.io kubeflow-gateway --type=json -p '[{"op":"add","path":"/spec/servers/-","value":{ "port": { "name": "https", "number": 443, "protocol": "HTTPS"}, "tls": { "mode": "SIMPLE", "credentialName": "kubeflow-ingress-tls" }, "hosts": ["*"]}}]'
}

curl_download() {
  BN=$(basename $1)
  if [ ! -f "$BN" ];then
    curl -Lo "$BN" -C - "$1"
  fi
}

gsutil_download() {
  ${self_dir}/data/gcli/bin/gsutil -m rsync gs://images.cocodataset.org/$1 $1
}

fetch() {
  curl_download "$1"
  unzip -n $(basename $1)
}

get_data() {
  mkdir -p $NFS_DIR/data
  mkdir -p $NFS_DIR/checkpoints
  cd $NFS_DIR/data
  fetch 'http://images.cocodataset.org/zips/train2017.zip'
  fetch 'http://images.cocodataset.org/zips/val2017.zip'
  fetch 'http://images.cocodataset.org/zips/test2017.zip'
  fetch 'http://images.cocodataset.org/annotations/annotations_trainval2017.zip'
  fetch 'http://images.cocodataset.org/annotations/stuff_annotations_trainval2017.zip'
  fetch 'http://images.cocodataset.org/annotations/panoptic_annotations_trainval2017.zip'
  fetch 'http://images.cocodataset.org/annotations/image_info_test2017.zip'
}

build_dino() {
  DOCKER_BUILDKIT=1 docker build -t ${REGISTRY:?Please Initialize registry}/dino-pytorch -f ${self_dir}/dino/Dockerfile.dino ${self_dir}/dino/
  DOCKER_BUILDKIT=1 docker build -t ${REGISTRY:?Please Initialize registry}/dino-jupyter -f ${self_dir}/dino/Dockerfile.jupyter ${self_dir}/dino/
  docker push -q ${REGISTRY:?Please Initialize registry}/dino-pytorch 
  docker push -q ${REGISTRY:?Please Initialize registry}/dino-jupyter 
}

cleanup_dino() {
  kubectl delete -f ${self_dir}/dino/dino.yaml || true
  kubectl delete -f ${self_dir}/dino/pvc.yaml || true
}

create_pvc() {
  kubectl apply -f ${self_dir}/dino/pvc.yaml 
}

restart_dino() {
  cleanup_dino
  create_pvc
  envsubst <${self_dir}/dino/dino.yaml|kubectl apply -n default -f -
}

fetch_tools() {
  echo "Downloading missing tools...."
  BINDIR=${self_dir}/bin
  mkdir -p $BINDIR
  
  if [ ! -x $BINDIR/helm ];then echo "Download helm...";curl https://get.helm.sh/helm-v3.12.0-linux-amd64.tar.gz|tar xvzC ${self_dir}/bin --strip-components=1 linux-amd64/helm;fi
  if [ ! -x $BINDIR/kubectl ];then echo "Download kubectl...";curl -Lo $BINDIR/kubectl https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubectl && chmod +x $BINDIR/kubectl;fi
  if [ ! -x $BINDIR/kustomize ];then echo "Download kustomize...";curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.0.3/kustomize_v5.0.3_linux_amd64.tar.gz | tar xvzC ${self_dir}/bin;fi
  if [ ! -x $BINDIR/minikube ];then echo "Download minikube...";curl -Lo $BINDIR/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64  && chmod +x $BINDIR/minikube;fi
  
}

fullstart() {
  fetch_tools
  create_registry_config "${REGISTRYDOMAIN:-$1}"
  restart_infra
  start_minikube
  build_dino
  create_pvc
  minikube tunnel
}

"$@"
