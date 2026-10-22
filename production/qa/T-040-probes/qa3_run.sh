#!/bin/bash
# QA T-040 3. tur koşucu (yalniz kendi baslattigi surecler)
cd "/Users/eralperol/Documents/Projects/imaro-the-mayor-handover-imaro-m01-349562fb"; G="/Users/eralperol/Documents/Projects/imaro-the-mayor/.tools/Godot.app/Contents/MacOS/Godot"; P=production/qa/T-040-probes
$G --headless --path . --script $PWD/$P/qa2_b001_probe.gd > $P/qa3_b001.log 2>&1; echo "b001 exit $?" >> $P/qa3_done.txt
$G --headless --path . --script $PWD/$P/qa2_sametick_scene.gd -- --preset=district:D1 > $P/qa3_sametick.log 2>&1; echo "sametick exit $?" >> $P/qa3_done.txt
$G --headless --fixed-fps 60 --path . --script $PWD/$P/qa3_play_probe.gd -- --demo --preset=district:D1 --qa-frames=1500 > $P/qa3_play_smoke.log 2>&1; echo "play exit $?" >> $P/qa3_done.txt
$G --headless --path . --script $PWD/$P/qa3_load_hash_probe.gd -- --demo --preset=district:D1 --no-smoke-save-load --qa-days=120 > $P/qa3_load_hash.log 2>&1; echo "loadhash exit $?" >> $P/qa3_done.txt
echo ALLDONE >> $P/qa3_done.txt
