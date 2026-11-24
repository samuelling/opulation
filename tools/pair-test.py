# python3 tools/pair-test.py — two phones in one headless Chrome pair through a local relay: her face is fed to his
# camera, his song to her ears. Needs: pip install playwright; python3 -m http.server 8765; node tools/relay-dev.mjs
import sys, time, os, base64
from playwright.sync_api import sync_playwright
URL = 'http://localhost:8765/?test&relay=ws://localhost:8787' + ('&nodirect' if os.environ.get('NODIRECT') else '')
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/usr/bin/google-chrome', args=['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
        '--use-file-for-fake-audio-capture=/tmp/silence.wav', '--autoplay-policy=no-user-gesture-required'])
    pages = {}
    for role in ('female', 'male'):
        c = b.new_context(permissions=['microphone', 'camera'], viewport={'width': 420, 'height': 900})
        pg = c.new_page(); pg.on('console', lambda m, r=role: print(f'  [{r}] {m.text}') if m.type in ('error', 'warning') else None)
        pg.on('pageerror', lambda e, r=role: print(f'  [{r}] PAGE ERROR {e}'))
        pg.goto(URL); pg.wait_for_function('window.__opul')
        pg.click('#roleFemale' if role == 'female' else '#roleMale'); pages[role] = pg
    pages['female'].click('#go'); time.sleep(1.0); pages['male'].click('#go')
    t0 = time.time(); last = None; result = 'timeout'
    while time.time() - t0 < 60:
        url = pages['female'].evaluate('__opul.card()')
        if url: pages['male'].evaluate('(u) => __opul.see(u)', url)
        for chunk in pages['male'].evaluate('__opul.takePlayed()'): pages['female'].evaluate('(x) => __opul.hear(x)', chunk)
        st = {r: pages[r].evaluate('__opul.state()') for r in pages}
        line = ' | '.join(f"{r}: {st[r]['stage']} · {st[r]['air']}" for r in st)
        if line != last: print(f'{time.time() - t0:5.1f}s  {line}'); last = line
        if st['male']['nest'] and st['female']['nest']: result = f"nest open: {st['male']['nest']}"; break
        if 'kick' in st['male']['caption'].lower(): result = 'kicked: ' + st['male']['caption']; break
        time.sleep(0.12)
    print(f'{time.time() - t0:5.1f}s  RESULT: {result}')
    if 'nest' in result:
        pages['male'].fill('#noteIn', 'a fig, ripe'); pages['male'].click('#noteSend')
        pages['female'].fill('#noteIn', 'and a wasp'); pages['female'].click('#noteSend'); time.sleep(1.5)
        print('  she got:', pages['female'].evaluate("[...document.querySelectorAll('#items li.in .bub')].map(e => e.textContent)"))
        print('  he got: ', pages['male'].evaluate("[...document.querySelectorAll('#items li.in .bub')].map(e => e.textContent)"))
        pages['male'].evaluate("""() => { const f = new File([new Uint8Array(300000).map((_, i) => i & 255)], 'big.bin', { type: 'application/octet-stream' }); __opul.sendItem(f, 'file'); }""")
        time.sleep(3)
        print('  file:', pages['female'].evaluate("[...document.querySelectorAll('#items li.in .fs')].map(e => e.textContent)"))
        pages['male'].click('#again'); time.sleep(1.2)
        print('  after he leaves, her status:', pages['female'].evaluate("document.getElementById('nestStatus').textContent"))
        for r in pages: pages[r].screenshot(path=f'/tmp/pair-{r}.png', full_page=True)
    b.close()
