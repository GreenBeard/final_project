#!/bin/tcsh -f
#-------------------------------------------
# qflow exec script for project /home/alex/workspace/ece385_labs/final_project
#-------------------------------------------

/usr/local/share/qflow/scripts/synthesize.sh /home/alex/workspace/ece385_labs/final_project final_project /home/alex/workspace/ece385_labs/final_project/source/final_project.sv || exit 1
# /usr/local/share/qflow/scripts/placement.sh -d /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/vesta.sh  /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/router.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/vesta.sh  -d /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/migrate.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/drc.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/lvs.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/gdsii.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/cleanup.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
# /usr/local/share/qflow/scripts/display.sh /home/alex/workspace/ece385_labs/final_project final_project || exit 1
