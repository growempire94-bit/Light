// Renders web/scene.js frame by frame in headless Chromium and encodes with ffmpeg.
//   node render.js                     -> build/seg*.mp4 + build/video.mp4 (no audio)
//   node render.js --stills=1.5,7,20   -> build/still_*.png for checking layout
const { chromium } = require('playwright');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const TL = JSON.parse(fs.readFileSync(path.join(root, 'timeline.json'), 'utf8'));
const args = process.argv.slice(2);
const stillsArg = args.find(a => a.startsWith('--stills='));
const outDir = (args.find(a => a.startsWith('--out=')) || '').slice(6) || path.join(root, 'build');
const WORKERS = 4;

async function makePage(browser) {
  const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
  page.on('pageerror', e => { console.error('PAGE ERROR', e.message); process.exit(1); });
  await page.addInitScript(tl => { window.TL = tl; }, TL);
  await page.goto('file://' + path.join(root, 'web', 'index.html'));
  await page.evaluate(async () => {
    const fonts = ['900 40px Inter', '800 40px Inter', '700 40px Inter', '500 40px "JetBrains Mono"',
      '800 40px "JetBrains Mono"', '40px "Noto Color Emoji"'];
    await Promise.all(fonts.map(f => document.fonts.load(f, 'АБВabc😀')));
  });
  return page;
}

const grab = (page, t, type, q) => page.evaluate(([t, type, q]) => {
  window.draw(t);
  return document.getElementById('c').toDataURL(type, q);
}, [t, type, q]);

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  if (stillsArg) {
    const page = await makePage(browser);
    for (const s of stillsArg.slice(9).split(',')) {
      const t = parseFloat(s);
      const data = await grab(page, t, 'image/png');
      fs.writeFileSync(path.join(outDir, `still_${t.toFixed(2)}.png`), Buffer.from(data.split(',')[1], 'base64'));
    }
    await browser.close();
    return;
  }
  const fps = TL.fps;
  const total = Math.ceil(TL.duration * fps);
  const per = Math.ceil(total / WORKERS);
  const t0 = Date.now();
  await Promise.all([...Array(WORKERS).keys()].map(async w => {
    const page = await makePage(browser);
    const a = w * per, b = Math.min(total, a + per);
    const seg = path.join(outDir, `seg${w}.mp4`);
    const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
      '-c:v', 'libx264', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-r', String(fps), seg],
      { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let f = a; f < b; f++) {
      const data = await grab(page, f / fps, 'image/jpeg', 0.95);
      const buf = Buffer.from(data.slice(data.indexOf(',') + 1), 'base64');
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (w === 0 && (f - a) % 90 === 0) console.log(`frames ${f - a}/${b - a}  ${((Date.now() - t0) / 1000).toFixed(0)}s`);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }));
  await browser.close();
  fs.writeFileSync(path.join(outDir, 'segs.txt'), [...Array(WORKERS).keys()].map(w => `file 'seg${w}.mp4'`).join('\n') + '\n');
  const r = spawnSync('ffmpeg', ['-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', path.join(outDir, 'segs.txt'),
    '-c', 'copy', path.join(outDir, 'video.mp4')], { stdio: 'inherit' });
  if (r.status !== 0) process.exit(1);
  console.log(`done in ${((Date.now() - t0) / 1000).toFixed(0)}s, ${total} frames`);
})();
