# Checks the locale files in Runeway/Locales against enUS.lua: no unknown keys, the same format
# placeholders (%s, %d, %.2f, %%) as English, and lists keys that still fall back to English.
# Each file is also loaded on Lua 5.1 with its client locale.
#   python tests/check_locales.py
import os
import re
import sys
import glob
from lupa import lua51

ROOT = os.path.join(os.path.dirname(__file__), '..')
DIR = os.path.join(ROOT, 'Runeway', 'Locales')
PH = re.compile(r'%[-0-9.]*[sdf%]')


def load(locale, files):
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f'function GetLocale() return "{locale}" end; NS = {{}}')
    for f in files:
        L.execute('local f = assert(loadstring(..., "@' + os.path.basename(f) + '")); f("Runeway", NS)',
                  open(f, encoding='utf8').read())
    return {k: v for k, v in L.eval('NS.L').items()}


en_file = os.path.join(DIR, 'enUS.lua')
en = load('enUS', [en_file])
errors = 0
for f in sorted(glob.glob(os.path.join(DIR, '*.lua'))):
    loc = os.path.basename(f)[:-4]
    if loc == 'enUS':
        continue
    keys = set(re.findall(r'^L\.([A-Z0-9_]+)\s*=', open(f, encoding='utf8').read(), re.M))
    t = load(loc, [en_file, f])
    unknown = keys - set(en)
    bad = [k for k in keys & set(en) if sorted(PH.findall(t[k])) != sorted(PH.findall(en[k]))]
    missing = sorted(set(en) - keys)
    errors += len(unknown) + len(bad)
    print(f'{loc}: {len(keys)}/{len(en)} texts' + (f', unknown {sorted(unknown)}' if unknown else '')
          + (f', placeholders differ {sorted(bad)}' if bad else '') + (f', English fallback {missing}' if missing else ''))
sys.exit(1 if errors else 0)
