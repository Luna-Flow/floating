# `decimal` Performance

## Baseline Gate

`just bench decimal` は current tree と `testdata/decimal/performance_baseline.json` の immutable manifest を比較します。paired AB/BA/AB process を実行し、cell ごとに九つ以上の accepted sample を要求し、不安定 MAD を拒否し、paired median regression が 5% を超えると失敗します。

## Operand Model

measurement は limb count と dense、sparse、square、unbalanced shape を分離します。kernel は canonical little-endian base-1e9 limb を保存し、NTT は小さい working digit に変換します。単一 global digit threshold では padding と shape crossover を表せません。

## Native 乗算 Calibration

native は multiply の schoolbook→Karatsuba が 96 limb、square が 48、Karatsuba→Toom-3 が 1,152 です。transform-band NTT multiply は 1,728/2,816/4,608/7,680 limb、square は 640/1,040/1,824/3,648/7,296 から始まります。他 target は独立した conservative value を保ちます。

## 除算 Calibration

native Burnikel–Ziegler threshold は block band ごとに 2,816、5,120、10,240 limb です。Newton reciprocal division は differential test 用に実装されていますが、Burnikel–Ziegler より遅い測定結果のため native では自動選択しません。

## 統計手法

threshold experiment は ABBA/BAAB order、process 間の size rotation、不安定 process の拒否、weighted non-increasing isotonic regression、complete process column bootstrap を使います。production boundary には 95% upper confidence threshold、`p <= 0.05` の one-sided sign test、3% 以上の median improvement が必要です。

## 再現と解釈

```sh
just bench decimal --target native
just bench decimal-threshold --model --transition mul-toom3-ntt-32k \
  --model-low 4096 --model-high 5120 --model-step 128 \
  --processes 5 --samples 9 --bootstrap-samples 5000
```

threshold は target-specific evidence であり API promise ではありません。高速 path は coefficient differential test と IEEE/GDA conformance を先に通過する必要があります。
