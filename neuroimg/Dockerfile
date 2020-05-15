FROM python:latest
LABEL authors="Christopher Coogan <c.coogan2201@gmail.com>, Adam Li <ali39@jhu.edu>"

ENV DEBIAN_FRONTEND noninteractive
SHELL ["/bin/bash", "-c"]

############# SYSTEM LEVEL INSTALLS #############
# install basic ubuntu utilities
RUN apt-get update && apt-get install -y \
    apt-utils \
    build-essential \
    wget \
    python \
    libglu1-mesa \
    git \
    g++ \
    gcc \
    libxmu-dev \
    libxi6 \       
    libgconf-2-4 \
    libfontconfig1 \
    libxrender1 \
    octave \ 
    gawk \
    unzip \
    curl \
    libxss1 \
    libjpeg62 \
    tcsh \
    bc \
    dialog

# Freesurfer
RUN wget -O- https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/7.1.0/freesurfer-linux-centos7_x86_64-7.1.0.tar.gz | \
    tar zx --no-same-owner -C /usr/local/ \
    --exclude='freesurfer/trctrain' \
    --exclude='freesurfer/subjects/fsaverage_sym' \
    --exclude='freesurfer/subjects/fsaverage3' \
    --exclude='freesurfer/subjects/fsaverage4' \
    --exclude='freesurfer/subjects/fsaverage5' \
    --exclude='freesurfer/subjects/fsaverage6' \
    --exclude='freesurfer/subjects/cvs_avg35' \
    --exclude='freesurfer/subjects/cvs_avg35_inMNI152' \
    --exclude='freesurfer/subjects/bert' \
    --exclude='freesurfer/subjects/V1_average' \
    --exclude='freesurfer/average/mult-comp-cor' 

ENV FREESURFER_HOME=/usr/local/freesurfer \
    bids_root=/data \
    derivatives_output_dir=/data/derivatives \
    SUBJECTS_DIR=/data/derivatives/freesurfer
COPY ./neuroimg/freesurferlicense.txt /usr/local/freesurfer/.license

RUN echo "source /usr/local/freesurfer/SetUpFreeSurfer.sh" >> ~/.bashrc \
 && \
# Neuroimgpipe dependencies
    pip3 install snakemake mne-bids numpy scipy mne dicom2nifti && \
# Node & bids-validator
    curl -sL https://deb.nodesource.com/setup_13.x | bash - && \
    apt-get install -y nodejs && \
    npm i -g bids-validator

############# KEEP BELOW SYSTEM LEVEL INSTALLS #############
# setup working directories
WORKDIR /neuroimg
COPY ./neuroimg/pipeline/01-prep /neuroimg/pipeline/01-prep
COPY ./neuroimg/pipeline/02-reconstruction /neuroimg/pipeline/02-reconstruction
COPY ./neuroimg/pipeline/03-coregistration /neuroimg/pipeline/03-coregistration

# copy over files and functions
COPY ./neuroimg/pipeline/fileutils.py /neuroimg/pipeline/fileutils.py
COPY ./neuroimg/format /neuroimg/format
COPY ./neuroimg/pipeline/config/localconfig.yaml /neuroimg/pipeline/config/localconfig.yaml
