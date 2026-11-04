#!/bin/bash
cd "/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb"; G="/Users/eralperol/Documents/Projects/imaro-the-mayor/.tools/Godot.app/Contents/MacOS/Godot"; P=production/qa/T-040-probes
$G --headless --path . --script $PWD/$P/qa2_loop_probe.gd > $P/qa3_loop.log 2>&1; echo "loop exit $?" >> $P/qa3_done2.txt
$G --headless --path . --script $PWD/$P/qa_can03_probe.gd > $P/qa3_can03.log 2>&1; echo "can03 exit $?" >> $P/qa3_done2.txt
$G --headless --fixed-fps 60 --path . --script $PWD/$P/qa2_play_probe.gd -- --demo --preset=district:D1 --qa-frames=30 > $P/qa3_orig_qa2_play.log 2>&1; echo "orig_qa2_play exit $?" >> $P/qa3_done2.txt
echo ALLDONE >> $P/qa3_done2.txt
