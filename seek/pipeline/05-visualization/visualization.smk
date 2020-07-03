"""
===============================================
05. Visualization workflow on web browser
================================================

This pipeline depends on the following functions:

    * blender
    * Flask

from Blender, Flask
"""

import os
import sys
from pathlib import Path

from mne_bids import make_bids_basename, make_bids_folders

sys.path.append("../../../")

from seek.pipeline.fileutils import BidsRoot, BIDS_ROOT, _get_session_name, _get_seek_config

configfile: _get_seek_config()
BLENDER_PATH = config["blender_path"]
BLENDER_PATH = "blender"
# BLENDER_PATH = os.environ.get("blender")
# print(BLENDER_PATH)

# get the freesurfer patient directory
bids_root = BidsRoot(BIDS_ROOT(config['bids_root']))
subject_wildcard = "{subject}"

# initialize directories that we access in this snakemake
FS_DIR = bids_root.freesurfer_dir
FSPATIENT_SUBJECT_FOLDER = bids_root.get_freesurfer_patient_dir(subject_wildcard)
FS_MRI_FOLDER = Path(FSPATIENT_SUBJECT_FOLDER) / "mri"
FS_CT_FOLDER = Path(FSPATIENT_SUBJECT_FOLDER) / "CT"
FS_ELECS_FOLDER = Path(FSPATIENT_SUBJECT_FOLDER) / "elecs"
FS_ACPC_FOLDER = Path(FSPATIENT_SUBJECT_FOLDER) / "acpc"
FS_SURF_FOLDER = Path(FSPATIENT_SUBJECT_FOLDER) / "surf"
FS_LABEL_FOLDER = os.path.join(FSPATIENT_SUBJECT_FOLDER, "label")
FS_ROI_FOLDER = os.path.join(FSPATIENT_SUBJECT_FOLDER, "rois")
FS_OBJ_FOLDER = os.path.join(FSPATIENT_SUBJECT_FOLDER, "obj")

# specific file paths
LH_PIAL_ASC = os.path.join(FS_SURF_FOLDER, "ascii", "lh.pial.asc")
RH_PIAL_ASC = os.path.join(FS_SURF_FOLDER, "ascii", "rh.pial.asc")
LH_ANNOT_FILE = os.path.join(FS_LABEL_FOLDER, "lh.aparc.annot")
RH_ANNOT_FILE = os.path.join(FS_LABEL_FOLDER, "rh.aparc.annot")
LH_PIAL_SRF = os.path.join(FS_SURF_FOLDER, "lh.pial.srf")
RH_PIAL_SRF = os.path.join(FS_SURF_FOLDER, "rh.pial.srf")
LH_ANNOT_DPV = os.path.join(FS_LABEL_FOLDER, "lh.aparc.annot.dpv")
RH_ANNOT_DPV = os.path.join(FS_LABEL_FOLDER, "rh.aparc.annot.dpv")
LH_PIAL_ROI = os.path.join(FS_ROI_FOLDER, "lh.pial_roi")
RH_PIAL_ROI = os.path.join(FS_ROI_FOLDER, "rh.pial_roi")

# blender output file paths
surface_scene_fpath = os.path.join(FSPATIENT_SUBJECT_FOLDER, "blender_objects", "reconstruction.glb")
surface_fbx_fpath = os.path.join(FSPATIENT_SUBJECT_FOLDER, "blender_objects", "reconstruction.fbx")

# coordinate system and electrodes as tsv files
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

subworkflow reconstruction_workflow:
    workdir:
           "../02-reconstruction/",
    snakefile:
             "../02-reconstruction/reconstruction.smk"
    configfile:
              _get_seek_config()

subworkflow contact_localization_workflow:
    workdir:
           "../04-contact_localization/"
    snakefile:
             "../04-contact_localization/contact_localization.smk"
    configfile:
              _get_seek_config()

rule all:
    input:
         surface_scene_file=expand(surface_scene_fpath, subject=config["patients"]),
         # surface_scene_file = os.path.join("./webserver/templates/static/", "reconstruction.glb"),
         # surface_fbx_file = os.path.join("./webserver/templates/static/", "reconstruction.fbx"),
    shell:
         "echo 'Done!;'"

"""Convert Ascii pial files to surface files."""
rule convert_asc_to_srf:
    input:
         LH_PIAL_ASC=LH_PIAL_ASC,
         RH_PIAL_ASC=RH_PIAL_ASC,
    output:
          LH_PIAL_SRF=LH_PIAL_SRF,
          RH_PIAL_SRF=RH_PIAL_SRF,
    shell:
         "cp {input.LH_PIAL_ASC} {output.LH_PIAL_SRF};"
         "cp {input.RH_PIAL_ASC} {output.RH_PIAL_SRF};"

"""Convert Subcortical surface files to Blender object files."""
rule convert_subcort_to_obj:
    input:
         subcort_success_flag_file=reconstruction_workflow(
             os.path.join(FSPATIENT_SUBJECT_FOLDER, "{subject}_subcort_success.txt")),
    params:
          subject=subject_wildcard,
          fsdir=FS_DIR,
          FS_OBJ_FOLDER=str(FS_OBJ_FOLDER),
    output:
          obj_success_flag_file=os.path.join(FSPATIENT_SUBJECT_FOLDER, "{subject}_subcortobjects_success.txt"),
    shell:
         "export SUBJECTS_DIR={params.fsdir};"
         "mkdir -p {params.FS_OBJ_FOLDER};"
         "./scripts/objMaker.sh {params.subject};"
         "touch {output.obj_success_flag_file};"

"""Convert annotation files to DPV files for Blender."""
rule convert_annot_to_dpv:
    input:
         LH_ANNOT_FILE=LH_ANNOT_FILE,
         RH_ANNOT_FILE=RH_ANNOT_FILE,
    output:
          LH_ANNOT_DPV=LH_ANNOT_DPV,
          RH_ANNOT_DPV=RH_ANNOT_DPV,
    shell:
         "./scripts/annot2dpv {input.LH_ANNOT_FILE} {output.LH_ANNOT_DPV};"
         "./scripts/annot2dpv {input.RH_ANNOT_FILE} {output.RH_ANNOT_DPV};"

"""Split surfaces into files per right/left hemisphere."""
rule split_surfaces:
    input:
         LH_ANNOT_DPV=LH_ANNOT_DPV,
         RH_ANNOT_DPV=RH_ANNOT_DPV,
         LH_PIAL_SRF=LH_PIAL_SRF,
         RH_PIAL_SRF=RH_PIAL_SRF,
    params:
          LH_PIAL_ROI=LH_PIAL_ROI,
          RH_PIAL_ROI=RH_PIAL_ROI,
    output:
          roi_flag_file=os.path.join(FSPATIENT_SUBJECT_FOLDER, "surfaces_roi_flag_success.txt")
    shell:
         # "cd ./scripts/;"
         "./scripts/splitsrf {input.LH_PIAL_SRF} {input.LH_ANNOT_DPV} {params.LH_PIAL_ROI};"
         "./scripts/splitsrf {input.RH_PIAL_SRF} {input.RH_ANNOT_DPV} {params.RH_PIAL_ROI};"
         "touch {output.roi_flag_file};"

rule create_surface_objects:
    input:
         roi_flag_file=os.path.join(FSPATIENT_SUBJECT_FOLDER, "surfaces_roi_flag_success.txt"),
         electrode_fpath=contact_localization_workflow(electrodes_fname),
         obj_success_flag_file=os.path.join(FSPATIENT_SUBJECT_FOLDER, "{subject}_subcortobjects_success.txt"),
    params:
          LH_PIAL_ROI=LH_PIAL_ROI,
          RH_PIAL_ROI=RH_PIAL_ROI,
          fsdir=FS_DIR,
          subject=subject_wildcard,
          materialcolors_file=os.path.join(os.getcwd(), "./scripts/materialColors.json"),
          BLENDER_PATH=BLENDER_PATH,
    output:
          surface_scene_file=surface_scene_fpath,
          surface_fbx_file=surface_fbx_fpath,
          # copied_surface_scene_file = os.path.join("./webserver/templates/static/", "reconstruction.glb"),
          # copied_surface_fbx_file = os.path.join("./webserver/templates/static/", "reconstruction.fbx"),
    shell:
         "echo 'Creating surface objects for rendering!';"
         "export SUBJECTS_DIR={params.fsdir};"
         "./scripts/surfaceToObject.sh {params.subject};"
         "{params.BLENDER_PATH} --background --python ./scripts/sceneCreator.py -- " \
         "{params.fsdir} " \
         "{params.subject} " \
         "{input.electrode_fpath} " \
         "True False " \
         "{output.surface_fbx_file} " \
         "{output.surface_scene_file} " \
         "{params.materialcolors_file};"
         # "cp {output.surface_scene_file} {output.copied_surface_scene_file};"
         # "cp {output.surface_fbx_file} {output.copied_surface_fbx_file};"
