# International Business: My Future — TikTok

Профорієнтаційний ролик «Міжнародний менеджер: очікування vs реальність» (тема №5)
для освітньої програми «Менеджмент міжнародного бізнесу» Одеської політехніки.

- `out/International_Business_My_Future_TikTok.mp4` — готове відео 1080×1920, 30 fps, 59 с, з озвучкою.
- `out/International_Business_My_Future_bez_ozvuchky.mp4` — те саме без голосу (музика + ефекти), щоб начитати своїм голосом.

Озвучка: нейромережа [ukrainian-tts](https://github.com/robinhad/ukrainian-tts) v6, голос Mykyta, наголоси розставлені вручну
(`lines_stressed.tsv`), темп ×1.25. Музика й звукові ефекти згенеровані кодом.

## Перезібрати

```
pip install scipy numpy
# Python 3.10 env: torch==1.13.1 espnet==202301 "typeguard<3" "scipy<1.12" "numpy<1.24" kaldiio soundfile six "setuptools<70"
# модель: model.pth, config.yaml, spk_xvector.ark, feats_stats.npz з релізу v6.0.0 ukrainian-tts
python3.10 tts_neural.py <model_dir> mykyta 1.25   # озвучка (старий варіант: tts.py з RHVoice)
python3 build_timeline.py # таймінги слів, сцен, ефектів
python3 audio.py          # музика + ефекти + зведення
node render.js            # кадри (Playwright/Chromium) -> build/video.mp4
```
Потім змікшувати відео й `audio/mix_voice.wav` через ffmpeg (loudnorm -14 LUFS).
