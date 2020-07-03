"""
===============================================
06. Postsurgery T1 MRI registration and workflow
================================================

This pipeline depends on the following functions:

    * mrconvert
    * flirt

from FreeSurfer6+, FSL.
"""

import os
import sys
from pathlib import Path

from mne_bids import make_bids_basename

sys.path.append("../../../")
from seek.pipeline.fileutils import (BidsRoot, BIDS_ROOT, _get_seek_config,
                                     _get_anat_bids_dir, _get_bids_basename)

configfile: _get_seek_config()

# get the freesurfer patient directory
bids_root = BidsRoot(BIDS_ROOT(config['bids_root']),
                     center_id=config['center_id'])
subject_wildcard = "{subject}"

SESSION = 'postsurgery'

# initialize directories that we access in this snakemake
RAW_CT_FOLDER = bids_root.get_rawct_dir(subject_wildcard)
RAW_POSTMRI_FOLDER = bids_root.get_postmri_dir(subject_wildcard)
FS_DIR = bids_root.freesurfer_dir
FSPATIENT_SUBJECT_DIR = bids_root.get_freesurfer_patient_dir(subject_wildcard)
FSOUT_MRI_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "mri"
FSOUT_POSTMRI_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "postsurgerymri"

BIDS_POSTSURG_ANAT_DIR = _get_anat_bids_dir(bids_root.bids_root, subject_wildcard, session=SESSION)
BIDS_PRESURG_ANAT_DIR = _get_anat_bids_dir(bids_root.bids_root, subject_wildcard, session='presurgery')
postmri_bids_fname = _get_bids_basename(subject_wildcard, session=SESSION,
                                        space='RAS', imgtype='T1w', ext='nii.gz')
postmri_native_bids_fname = _get_bids_basename(subject_wildcard, session=SESSION,
                                               imgtype='T1w', ext='nii')
premri_bids_fname = _get_bids_basename(subject_wildcard, session='presurgery',
                                       space='RAS', imgtype='T1w', ext='nii')

from_id = 'presurgeryT1w'
to_id = 'postsurgeryT1w'
kind = 'xfm'
pre_to_post_transform_fname = make_bids_basename(subject=subject_wildcard) + \
                              f"_from-{from_id}_to-{to_id}_mode-image_{kind}.mat"

SESSION = 'postsurgery'

subworkflow prep_workflow:
    workdir:
           "../01-prep/"
    snakefile:
             "../01-prep/prep.smk"
    configfile:
              _get_seek_config()

# First rule
rule all:
    input:
         # MRI_NIFTI_IMG = expand(os.path.join(_get_anat_bids_dir(bids_root.bids_root, subject_wildcard),
         #                                     _get_bids_basename(subject_wildcard, imgtype='T1w')),
         #                                     subject=config['patients']),
         # mapping matrix for post T1 to pre T1
         MAPPING_FILE=expand(os.path.join(FSOUT_POSTMRI_FOLDER, pre_to_post_transform_fname),
                             subject=config['patients']),
    params:
          bids_root=bids_root.bids_root,
    shell:
         "echo 'done';"
         "bids-validator {params.bids_root};"

"""
Rule for prepping fs_recon by converting dicoms -> NIFTI images.

They are reoriented into 'LAS' orientation. For more information, see
BIDS specification.
"""
rule convert_dicom_to_bids:
    params:
          MRI_FOLDER=RAW_POSTMRI_FOLDER,
          bids_root=bids_root.bids_root,
    output:
          MRI_bids_fname=os.path.join(BIDS_POSTSURG_ANAT_DIR, postmri_native_bids_fname),
    shell:
         "mrconvert {params.MRI_FOLDER} {output.MRI_bids_fname};"

"""
Rule for coregistering postsurgical T1 to presurgical T1 RAS.

This is because RAS is the preferred direction in Seg3D when we segment the image, it should be this one.
Then the corersponding coregistration from the RAS to FreeSurfer space gives the correct orientation.

postsurgical_T1w -> presurgical_T1w_RAS. Note FSL Flirt outputs files in 'nii.gz' format.
"""
rule coregistert1_post_to_pre_RAS:
    input:
         MRI_bids_fname=os.path.join(BIDS_POSTSURG_ANAT_DIR, postmri_native_bids_fname),
         PREMRI_NIFTI_IMG=prep_workflow(os.path.join(BIDS_PRESURG_ANAT_DIR, premri_bids_fname)),
    params:
         FSOUT_POSTMRI_FOLDER = str(FSOUT_POSTMRI_FOLDER),
    output:
          PREMRI_NIFTI_IMG=os.path.join(FSOUT_POSTMRI_FOLDER, premri_bids_fname),
          POSTMRI_NIFTI_IMG=os.path.join(FSOUT_POSTMRI_FOLDER, postmri_bids_fname),
          POSTMRI_bids_fname=os.path.join(BIDS_POSTSURG_ANAT_DIR, postmri_bids_fname),
          # mapping matrix for post to pre in T1
          MAPPING_FILE_ORIG=os.path.join(FSOUT_POSTMRI_FOLDER, pre_to_post_transform_fname),
    shell:
         "mkdir --parents {params.FSOUT_POSTMRI_FOLDER};"
         "cp {input.PREMRI_NIFTI_IMG} {output.PREMRI_NIFTI_IMG};"
         "flirt -in {input.MRI_bids_fname} \
                             -ref {input.PREMRI_NIFTI_IMG} \
                             -omat {output.MAPPING_FILE_ORIG} \
                             -out {output.POSTMRI_NIFTI_IMG};"
         "cp {output.POSTMRI_NIFTI_IMG} {output.POSTMRI_bids_fname};"

         # rule map_postRAS_to_preFS:
