# International Business: My Future — TikTok

Профорієнтаційний ролик «Міжнародний менеджер: очікування vs реальність» (тема №5)
для освітньої програми «Менеджмент міжнародного бізнесу» Одеської політехніки.

- `out/International_Business_My_Future_TikTok.mp4` — готове відео 1080×1920, 30 fps, 59 с, з озвучкою.
- `out/International_Business_My_Future_bez_ozvuchky.mp4` — те саме без голосу (музика + ефекти), щоб начитати своїм голосом.

Озвучка: синтез RHVoice, голос Volodymyr (CC BY-ND 4.0). Музика й звукові ефекти згенеровані кодом.

## Перезібрати

```
apt-get install rhvoice rhvoice-ukrainian && pip install scipy numpy
python3 tts.py            # озвучка з lines.tsv
python3 build_timeline.py # таймінги слів, сцен, ефектів
python3 audio.py          # музика + ефекти + зведення
node render.js            # кадри (Playwright/Chromium) -> build/video.mp4
```
Потім змікшувати відео й `audio/mix_voice.wav` через ffmpeg (loudnorm -14 LUFS).
