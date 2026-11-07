#!/bin/bash
# T-077: tüm koşuları sırayla çalıştırır (ölçüm temiz kalsın diye paralel DEĞİL). Her koşu kendi kilidini alır/bırakır.
# Atlanan (yük > 8) koşu çıkış 3 verir; burada kaydedilir ve devam edilir.
cd "$(dirname "$0")/../.."
b=experiments/m3_baseline/run_baseline.sh
for seed in 1467 7 31337; do
  for mode in player none; do
    $b "$mode-s$seed" -- --mode=$mode --sim-seed=$seed --years=5 || echo "ATLANDI/HATA: $mode-s$seed rc=$?"
  done
done
for mode in player none; do
  $b "$mode-s1467-nodiff" -- --mode=$mode --sim-seed=1467 --years=5 --no-diff || echo "ATLANDI/HATA: $mode-nodiff rc=$?"
done
$b "player-s1467-profile" -- --mode=player --sim-seed=1467 --years=5 --no-diff --profile || echo "ATLANDI/HATA: profile rc=$?"
echo ALL_DONE
