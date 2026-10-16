#!/usr/bin/env python3
"""Builds a single-file Mukafaah Manager demo (no server needed).

    python3 tools/manager-demo/build.py [out.html]

Inlines backend/admin (index, styles, app.js, logo) plus mock-api.js, which fakes the API in the browser.
"""
import base64, pathlib, sys
root = pathlib.Path(__file__).resolve().parents[2]
adm = root / 'backend' / 'admin'
here = pathlib.Path(__file__).parent
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else root / 'web-dist' / 'manager-demo.html')
logo = 'data:image/png;base64,' + base64.b64encode((adm / 'logo.png').read_bytes()).decode()
css = (adm / 'styles.css').read_text().replace("url('/admin/logo.png')", "var(--mk-logo)")
js = (adm / 'app.js').read_text().replace('/admin/logo.png', logo)
mock = (here / 'mock-api.js').read_text()
safe = lambda s: s.replace('</script', '<\\/script')
ribbon = """
.mk-demo{position:fixed;z-index:9999;left:50%;transform:translateX(-50%);bottom:calc(10px + env(safe-area-inset-bottom,0px));
 background:#2C123F;color:#fff;font:500 12px/1.2 'Readex Pro',system-ui,sans-serif;padding:7px 14px;border-radius:999px;
 box-shadow:0 6px 20px rgba(44,18,63,.35);display:flex;gap:8px;align-items:center;pointer-events:none;white-space:nowrap}
.mk-demo b{color:#E9B800;font-weight:600}
"""
html = f"""<title>Mukafaah Manager Demo</title>
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#2C123F">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Readex+Pro:wght@400;500;600;700&display=swap">
<style>:root{{--mk-logo:url('{logo}')}}
{css}
{ribbon}</style>
<div id="app"></div>
<div class="mk-demo"><b>Demo</b> Sample data. Sign in with any number. Changes reset on reload.</div>
<script>window.MK_DEMO_LOGO = '{logo}';</script>
<script>{safe(mock)}</script>
<script>{safe(js)}</script>
"""
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(html)
print(out, f'{len(html)//1024} KB')
