# Kubeflow environment for [DINO](https://github.com/IDEA-Research/DINO).

Tested on:
- Ubuntu 20.04
- Docker 20.10.7
- nVidia Tesla T4

Requirements:
- docker.io, nvidia-container-toolkit, nvidia-docker2  installed
    - docker/daemon.json should contain nvidia runtime 
- jq
- envsubst
- /data directory with ~300GB free space writeable

apt-get install jq gettext-base docker.io nvidia-container-toolkit nvidia-docker2

## Usage:
### Download COCO 
```sh
install.sh get_data
```
### Install
```sh
install.sh fullstart $FQDN
```
- SSL certificates will be generated for this FQDN

Expected result:
- local docker registry
- local docker mirror
- local nfs server
- minikube
- gpu-operator
- kubeflow
- prebuild pytorch container with DINO
- prebuild pytorch jupyter container with DINO

### Inference and Visualization
- (Optional) Download checkpoint(s) from [Google Drive](https://drive.google.com/drive/folders/1qD5m1NmK0kjE5hh-G17XUX751WsEG-h_) and put it to ``` /data/nfs_export/checkpoints ```

- Create Notebook
    - ``` kubectl create -f dino/dino_jupyter.yaml ```
    - Attaches coco-data
    - Attaches dino-checkpoints
    - Compiles model
- login to https://$FQDN with 
    - user: dino@kubeflow.com
    - password: dinominikube
- Check out the prepared notebook (DINO/jupyter_dino.ipynb)
    - You might need to update the checkpoint file and configuration in section 2 