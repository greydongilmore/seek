"""
===============================================
01. Prep Reconstruction Workflow and BIDS Layout
===============================================

In this pipeline, we prep the reconstruction workflow
by putting MRI and CT data into the BIDS layout and
re-orient images to RAS with ACPC alignment.

We assume that there is only one set of dicoms for CT and MRI
data.

This pipeline depends on the following functions:

    * mrconvert
    * acpcdetect

from FreeSurfer6+, acpcdetect2.0. To create a DAG pipeline, run:

    snakemake --dag | dot -Tpdf > dag_pipeline_reconstruction.pdf

"""

# Authors: Adam Li <adam2392@gmail.com>
# License: GNU

import os
import sys
from pathlib import Path

# hack to run from this file folder
sys.path.append("../../../")
from seek.pipeline.fileutils import (BidsRoot, BIDS_ROOT, _get_seek_config,
                                     _get_anat_bids_dir, _get_ct_bids_dir, _get_bids_basename)

configfile: _get_seek_config()

# get the freesurfer patient directory
bids_root = BidsRoot(BIDS_ROOT(config['bids_root']),
                     center_id=config['center_id']
                     )
subject_wildcard = "{subject}"

# initialize directories that we access in this snakemake
FS_DIR = bids_root.freesurfer_dir
RAW_CT_FOLDER = bids_root.get_rawct_dir(subject_wildcard)
RAW_MRI_FOLDER = bids_root.get_premri_dir(subject_wildcard)
FSOUT_MRI_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "mri"
FSOUT_CT_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "CT"
FSOUT_ACPC_FOLDER = Path(bids_root.get_freesurfer_patient_dir(subject_wildcard)) / "acpc"

BIDS_PRESURG_ANAT_DIR = _get_anat_bids_dir(bids_root.bids_root, subject_wildcard, session='presurgery')
BIDS_PRESURG_CT_DIR = _get_ct_bids_dir(bids_root.bids_root, subject_wildcard, session='presurgery')
premri_native_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                              imgtype='T1w', ext='nii')
premri_robustfov_native_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                                        processing='robustfov',
                                                        imgtype='T1w', ext='nii')
premri_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                       space='RAS', imgtype='T1w', ext='nii')
ct_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                   imgtype='CT', ext='nii')

# First rule
rule all:
    input:
         MRI_bids_fname_fscopy=expand(os.path.join(FSOUT_ACPC_FOLDER, premri_robustfov_native_bids_fname),
                                      subject=config['patients']),
         MRI_NIFTI_IMG=expand(os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname),
                              subject=config['patients']),
    params:
          bids_root=bids_root.bids_root,
    shell:
         "echo 'done';"
         "bids-validator {params.bids_root};"

"""
Rule for prepping fs_recon by converting dicoms -> NIFTI images.

For more information, see BIDS specification.
"""
rule convert_dicom_to_nifti:
    params:
          CT_FOLDER=RAW_CT_FOLDER,
          MRI_FOLDER=RAW_MRI_FOLDER,
          bids_root=bids_root.bids_root,
    output:
          CT_bids_fname=os.path.join(BIDS_PRESURG_CT_DIR, ct_bids_fname),
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_native_bids_fname),
    shell:
         "mrconvert {params.CT_FOLDER} {output.CT_bids_fname};"
         "mrconvert {params.MRI_FOLDER} {output.MRI_bids_fname};"


"""
Add comment.
"""
rule compute_robust_fov:
    input:
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_native_bids_fname),
    output:
          MRI_bids_fname_gz=os.path.join(FSOUT_ACPC_FOLDER, premri_robustfov_native_bids_fname) + '.gz',
          MRI_bids_fname=os.path.join(FSOUT_ACPC_FOLDER, premri_robustfov_native_bids_fname),
    container:
         "docker://neuroseek/seek",
    shell:
         "echo 'robustfov -i {input.MRI_bids_fname} -r {output.MRI_bids_fname_gz}';"
         'robustfov -i {input.MRI_bids_fname} -r {output.MRI_bids_fname_gz};'  # -m roi2full.mat
         'mrconvert {output.MRI_bids_fname_gz} {output.MRI_bids_fname} --datatype uint16;'


"""
Rule for automatic ACPC alignment using acpcdetect software. 

Please check the output images to quality assure that the ACPC was properly
aligned.  
"""
rule automatic_acpc_alignment:
    input:
         MRI_bids_fname=os.path.join(FSOUT_ACPC_FOLDER, premri_robustfov_native_bids_fname),
    params:
          anat_dir=str(BIDS_PRESURG_ANAT_DIR),
          acpc_fs_dir=str(FSOUT_ACPC_FOLDER),
    output:
          MRI_bids_fname_fscopy=os.path.join(FSOUT_ACPC_FOLDER, premri_native_bids_fname),
          MRI_bids_fname=os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname),
    shell:
         # create BIDS session directory and copy file there
         "echo 'acpcdetect -i {input.MRI_bids_fname} -center-AC -output-orient RAS;'"
         "echo {output.MRI_bids_fname};"
         "mkdir -p {params.acpc_fs_dir};"
         "cp {input.MRI_bids_fname} {output.MRI_bids_fname_fscopy};"
         # run acpc auto detection
         "acpcdetect -i {output.MRI_bids_fname_fscopy} -center-AC -output-orient RAS;"
         "cp {output.MRI_bids_fname_fscopy} {output.MRI_bids_fname};"

"""
Use mne.coregistration
"""
# rule estimate_fiducials:
#     input:
#
#     output:
#
#     params:
#
#     shell:

"""
Use pydeface.
"""
# rule deface:
