"""
=============================================
04. Contact Localization Using SEEK Algorithm
=============================================

This pipeline depends on the following functions:

    * python SEEK algorithm

"""

import os
import sys
from pathlib import Path

from mne_bids import make_bids_basename, make_bids_folders

sys.path.append("../../../")
from seek.pipeline.fileutils import BidsRoot, BIDS_ROOT, _get_session_name, _get_seek_config

configfile: _get_seek_config()

# get the freesurfer patient directory
bids_root = BidsRoot(BIDS_ROOT(config['bids_root']),
                     center_id=config['center_id']
                     )
subject_wildcard = "{subject}"

METADATA_FOLDER = "../../../data_examples/sourcedata/"

# initialize directories that we access in this snakemake
FS_DIR = bids_root.freesurfer_dir
FSPATIENT_SUBJECT_DIR = bids_root.get_freesurfer_patient_dir(subject_wildcard)
FSOUT_MRI_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "mri"
FSOUT_CT_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "CT"
FSOUT_ELECS_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "elecs"
FSOUT_ACPC_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "acpc"
FSOUT_SURF_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / "surf"
FSOUT_GYRI_FOLDER = Path(FSPATIENT_SUBJECT_DIR) / 'label' / 'gyri'

FIGDIR = os.path.join(FSOUT_ELECS_FOLDER, "figs")


def _get_bids_basename(subject, acquisition):
    """Wildcard function to get bids_basename."""
    bids_fname = make_bids_basename(subject,
                                    acquisition=acquisition,
                                    suffix=f"electrodes.tsv")
    return bids_fname


def get_channels_tsv_fpath(bids_root, subject_id):
    data_path = make_bids_folders(subject=subject_id, bids_root=bids_root, make_dir=False,
                                  overwrite=False, verbose=False)
    channels_tsv_fpath = make_bids_basename(subject=subject_id, suffix="channels.tsv", prefix=data_path)
    return channels_tsv_fpath


data_path = make_bids_folders(subject=subject_wildcard, session=_get_session_name(config),
                              bids_root=str(bids_root.bids_root), make_dir=False,
                              overwrite=False, verbose=False)
manual_coordsystem_fname = make_bids_basename(
    subject=subject_wildcard, session=_get_session_name(config), processing='manual',
    acquisition='seeg',
    suffix='coordsystem.json', prefix=data_path)
manual_electrodes_fname = make_bids_basename(
    subject=subject_wildcard, session=_get_session_name(config), processing='manual',
    acquisition='seeg',
    suffix='electrodes.tsv', prefix=data_path)

coordsystem_fname = make_bids_basename(
    subject=subject_wildcard, session=_get_session_name(config), processing='seek',
    acquisition='seeg',
    suffix='coordsystem.json', prefix=data_path)
electrodes_fname = make_bids_basename(
    subject=subject_wildcard, session=_get_session_name(config), processing='seek',
    acquisition='seeg',
    suffix='electrodes.tsv', prefix=data_path)

# channels_fname = get_channels_tsv_fpath(str(bids_root.bids_root), subject_id=subject_wildcard)

voxel_electrodes_fname = electrodes_fname.replace("electrodes", "voxelelectrodes")

# for electrode files in CT image space
ct_coordsystem_fname = coordsystem_fname.replace("coordsystem", "ctcoordsystem")
ct_electrodes_fname = electrodes_fname.replace("electrodes", "ctelectrodes")
ct_voxel_electrodes_fname = ct_electrodes_fname.replace("electrodes", "voxelelectrodes")
ct_voxel_electrodes_fname = ct_voxel_electrodes_fname.replace(".tsv", ".mat")

subworkflow reconstruction_workflow:
    workdir:
           "../02-reconstruction/"
    snakefile:
             "../02-reconstruction/reconstruction.smk"
    configfile:
              _get_seek_config()

subworkflow coregistration_workflow:
    workdir:
           "../03-coregistration/"
    snakefile:
             "../03-coregistration/coregistration.smk"
    configfile:
              _get_seek_config()

# First rule
rule all:
    input:
         figure_file=expand(os.path.join(FIGDIR, "summary_pca_elecs.png"),
                            subject=config['patients']),
         elecs3d_figure_fpath=expand(os.path.join(FIGDIR, "electrodes_in_voxel_space.png"),
                                     subject=config['patients']),
         bids_electrodes_file=expand(os.path.join(electrodes_fname),
                                     subject=config['patients']),
         bids_electrodes_json_file=expand(os.path.join(electrodes_fname.replace('.tsv', '.json')),
                                          subject=config['patients']),
         manual_bids_electrodes_file=expand(os.path.join(manual_electrodes_fname),
                                            subject=config['patients']),
         manual_bids_electrodes_json_file=expand(os.path.join(manual_electrodes_fname.replace('.tsv', '.json')),
                                                 subject=config['patients']),
    params:
          bids_root=bids_root.bids_root,
    shell:
         "echo 'done';"
         "bids-validator {params.bids_root};"

"""
Convert an annotation file into multiple label files or into a segmentation 'volume'. 
It can also create a border overlay.

# This version of mri_annotation2label uses the coarse labels from the Desikan-Killiany Atlas, unless
    # atlas_surf is 'destrieux', in which case the more detailed labels are used
"""
rule convert_gyri_annotations_to_labels:
    input:
         recon_success_file=reconstruction_workflow(os.path.join(FSPATIENT_SUBJECT_DIR, "{subject}_recon_success.txt")),
    params:
          subject_id=subject_wildcard,
          hemisphere='lh',
          surf_atlas_suffix_destrieux='--a2009s',
          surf_atlas_suffix_dk='',
          FS_GYRI_DIR=FSOUT_GYRI_FOLDER,
    shell:
         "mri_annotation2label " \
         "--subject {params.subject_id} " \
         "--hemi {params.hemisphere} " \
         "--surface pial {params.surf_atlas_suffix_destrieux} " \
         "--outdir {FS_GYRI_DIR};"
         "mri_annotation2label " \
         "--subject {params.subject_id} " \
         "--hemi {params.hemisphere} " \
         "--surface pial {params.surf_atlas_suffix_dk} " \
         "--outdir {FS_GYRI_DIR};"

"""
Rule for conversion .mat -> .txt

Converts output of fieldtrip toolbox .mat files named accordingly into txt files. 
Note: This file should contain at least two contacts per electrode.
"""
rule convert_CT_eleccoords_to_txt:
    # input:
    #     clustered_center_points_mat = os.path.join(FSOUT_ELECS_FOLDER,
    #                                                # '{subject}_elec_f.mat'
    #                                                '{subject}CH_elec_initialize.mat'),
    params:
          elecs_dir=FSOUT_ELECS_FOLDER,
    output:
          clustered_center_points=os.path.join(FSOUT_ELECS_FOLDER, '{subject}_elecxyz_inct.txt'),
    shell:
         "python ./convert_to_txt.py {params.elecs_dir} {output.clustered_center_points};"

rule copy_channnelstsv_to_freesurfer:
    input:
         channels_tsv_fpath=lambda wildcards: get_channels_tsv_fpath(str(bids_root.bids_root),
                                                                     subject_id=wildcards.subject),
    output:
          channels_tsv_fpath=os.path.join(FSOUT_ELECS_FOLDER,
                                          os.path.basename(get_channels_tsv_fpath(str(bids_root.bids_root),
                                                                                  subject_id=subject_wildcard))),
    shell:
         "cp {input.channels_tsv_fpath} {output.channels_tsv_fpath};"

"""Semi-automated algorithm to find electrode contacts on CT image.

Requires at 2 end-point contacts on each electrode.
"""
rule find_electrodes_on_CT:
    input:
         CT_NIFTI_IMG=reconstruction_workflow(os.path.join(FSOUT_CT_FOLDER, "CT.nii")),
         brainmask_inct_file=coregistration_workflow(os.path.join(FSOUT_CT_FOLDER, "brainmask_inct.nii.gz")),
         # list of channel points (at least 2 per electrode)
         electrode_initialization_file=os.path.join(FSOUT_ELECS_FOLDER, '{subject}_elecxyz_inct.txt'),
    params:
          FSPATIENT_DIR=FSPATIENT_SUBJECT_DIR.as_posix(),
    output:
          clustered_center_points=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(ct_electrodes_fname)),
          clustered_center_voxels=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(ct_voxel_electrodes_fname)),
          binarized_ct_volume=os.path.join(FSOUT_CT_FOLDER, "{subject}_binarized_ct.nii.gz"),
          elecs3d_figure_fpath=os.path.join(FIGDIR, "electrodes_in_voxel_space.png"),
          ct_coordsystem_fname=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(ct_coordsystem_fname)),
    shell:
         "echo 'RUNNING CLUSTERING ALGORITHM';"
         "python ./localize.py " \
         "{input.CT_NIFTI_IMG} " \
         "{input.brainmask_inct_file} " \
         "{input.electrode_initialization_file} " \
         "{output.clustered_center_points} " \
         "{output.clustered_center_voxels} " \
         "{output.binarized_ct_volume} " \
         "{params.FSPATIENT_DIR} " \
         "{output.elecs3d_figure_fpath};" \
 \
"""
Rule for image space conversion CT -> T1

applying flirt rigid registration affine transformation to the xyz coordinates of the localized
contacts in CT space. This will convert them into the space of the T1 image.
"""
rule convert_xyzcoords_to_native_T1:
    input:
         CT_NIFTI_IMG=os.path.join(FSOUT_CT_FOLDER, "CT.nii"),
         MRI_NIFTI_IMG=os.path.join(FSOUT_MRI_FOLDER, "T1.nii"),
         # DEPENDENCY ON RECONSTRUCTION WORKFLOW
         # mapping matrix for post to pre in T1
         MAPPING_FILE=coregistration_workflow(os.path.join(FSOUT_CT_FOLDER, "fsl_ct-to-t1_omat.txt")),
         ct_xyzcoords_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(ct_electrodes_fname)),
    output:
          mri_xyzcoords_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(electrodes_fname)),
          mri_coordsystem_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(coordsystem_fname)),
    shell:
         "python ./convert_coordspace.py " \
         "{input.CT_NIFTI_IMG} " \
         "{input.MRI_NIFTI_IMG} " \
         "{input.MAPPING_FILE} " \
         "{input.ct_xyzcoords_fpath} " \
         "{output.mri_xyzcoords_fpath};"

rule convert_manuallabels_to_native_T1:
    input:
         CT_NIFTI_IMG=os.path.join(FSOUT_CT_FOLDER, "CT.nii"),
         MRI_NIFTI_IMG=os.path.join(FSOUT_MRI_FOLDER, "T1.nii"),
         # DEPENDENCY ON RECONSTRUCTION WORKFLOW
         # mapping matrix for post to pre in T1
         MAPPING_FILE=coregistration_workflow(os.path.join(FSOUT_CT_FOLDER, "fsl_ct-to-t1_omat.txt")),
         manual_ct_coords_fpath=os.path.join(FSOUT_ELECS_FOLDER, '{subject}_elecxyz_inct.txt'),
    output:
          mri_electrode_coords_file=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(manual_electrodes_fname)),
          mri_coordsystem_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(manual_coordsystem_fname)),
    shell:
         "python ./convert_coordspace.py " \
         "{input.CT_NIFTI_IMG} " \
         "{input.MRI_NIFTI_IMG} " \
         "{input.MAPPING_FILE} " \
         "{input.manual_ct_coords_fpath} " \
         "{output.mri_electrode_coords_file};"

rule apply_anatomicalatlas_to_electrodes:
    input:
         fs_lut_fpath=os.path.join(METADATA_FOLDER, "FreeSurferColorLUT.txt"),
         clustered_center_points_file=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(electrodes_fname)),
         T1_NIFTI_IMG=os.path.join(FSOUT_MRI_FOLDER, "T1.nii"),
         mri_coordsystem_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(coordsystem_fname)),
    params:
          FSPATIENT_DIR=str(FSPATIENT_SUBJECT_DIR),
    output:
          bids_electrodes_tsv_file=os.path.join(electrodes_fname),
          bids_electrodes_json_file=os.path.join(electrodes_fname.replace('.tsv', '.json')),
          mri_coordsystem_fpath=os.path.join(coordsystem_fname),
    shell:
         "echo 'Applying anatomical atlas to electrode points...';"
         "python ./apply_anat_to_electrodes.py " \
         "{input.clustered_center_points_file} " \
         "{output.bids_electrodes_tsv_file} " \
         "{params.FSPATIENT_DIR} " \
         "{input.fs_lut_fpath} " \
         "{input.T1_NIFTI_IMG};"
         "cp {input.mri_coordsystem_fpath} {output.mri_coordsystem_fpath};"

rule apply_anatomicalatlas_to_manual_electrodes:
    input:
         fs_lut_fpath=os.path.join(METADATA_FOLDER, "FreeSurferColorLUT.txt"),
         mri_bids_electrodes_tsv_file=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(manual_electrodes_fname)),
         T1_NIFTI_IMG=os.path.join(FSOUT_MRI_FOLDER, "T1.nii"),
         mri_coordsystem_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(manual_coordsystem_fname)),
    params:
          FSPATIENT_DIR=str(FSPATIENT_SUBJECT_DIR),
    output:
          bids_electrodes_tsv_file=os.path.join(manual_electrodes_fname),
          bids_electrodes_json_file=os.path.join(manual_electrodes_fname.replace('.tsv', '.json')),
          mri_coordsystem_fpath=os.path.join(manual_coordsystem_fname),
    shell:
         "echo 'Applying anatomical atlas to electrode points...';"
         "python ./apply_anat_to_electrodes.py " \
         "{input.mri_bids_electrodes_tsv_file} " \
         "{output.bids_electrodes_tsv_file} " \
         "{params.FSPATIENT_DIR} " \
         "{input.fs_lut_fpath} " \
         "{input.T1_NIFTI_IMG};"
         "cp {input.mri_coordsystem_fpath} {output.mri_coordsystem_fpath};"

# rule apply_whitematteratlas_to_electrodes:
#     input:
#         WM_IMG_FPATH =  ,
#     params:
#         FSPATIENT_DIR = FSPATIENT_SUBJECT_DIR,
#     output:
#         bids_electrodes_file = os.path.join(electrodes_fname),
#     shell:
#         "echo 'Applying anatomical atlas to electrode points...';"
#         "python ./apply_anat_to_electrodes.py " \
#         "{input.clustered_center_points_file} " \
#         "{input.clustered_center_voxels_file} " \
#         "{output.bids_electrodes_file} " \
#         "{params.FSPATIENT_DIR} " \
#         "{input.WM_IMG_FPATH};"

"""
Rule to plot:
- parcellated nodes in space with the surface shown transparently
- surface shown transparent with different regions colored
- parcellated nodes in space with the contacts.xyz (centers) plotted
"""
rule visualize_results:
    input:
         ct_xyzcoords_fpath=os.path.join(FSOUT_ELECS_FOLDER, os.path.basename(ct_electrodes_fname)),
         # list of channel points (at least 2 per electrode)
         manual_electrode_file=os.path.join(FSOUT_ELECS_FOLDER, '{subject}_elecxyz_inct.txt'),
         # DEPENDENCY ON RECONSTRUCTION WORKFLOW
         ctfile=reconstruction_workflow(os.path.join(FSOUT_CT_FOLDER, "CT.nii")),
    params:
          fsdir=FSPATIENT_SUBJECT_DIR,
    output:
          pcafigure_file=os.path.join(FIGDIR, "summary_pca_elecs.png"),
          l2figure_file=os.path.join(FIGDIR, "summary_euclidean_distance_errors.png"),
    shell:
         "echo 'RUNNING VISUALIZATION CHECKS';"
         "python ./visualize_results.py {input.ct_xyzcoords_fpath} " \
         "{input.manual_electrode_file} " \
         "{input.ctfile} " \
         "{params.fsdir} " \
         "{output.pcafigure_file} {output.l2figure_file};"
