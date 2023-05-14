#target: dino-pytorch
FROM ubuntu:20.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y git build-essential python3-pip
#RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
RUN pip3 install torch torchvision torchaudio
RUN git clone https://github.com/IDEA-Research/DINO.git
RUN pip3 install -r DINO/requirements.txt
