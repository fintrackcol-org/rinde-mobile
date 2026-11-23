// Genera assets/l10n/{en,pt}.json: las traducciones de Rinde Web que usa la app móvil más las propias
// de la app (tool/l10n_mobile/{en,pt}.json). La clave es el texto en español, igual que en la web.
// De la web solo se copian las que aparecen en lib/. Las de l10n_mobile van siempre y se aplican
// después: ahí viven los textos que la web no tiene y las correcciones de traducciones de la web.
//
//   node tool/export_l10n.mjs <ruta a fintrack/frontend/src/locales>
//
// Lista los textos de t('…') sin traducción en ninguna de las dos fuentes y, si hay alguno, termina
// con código 1 (los archivos se escriben igual: esos textos se verían en español).
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const localesDir = process.argv[2];
if (!localesDir) throw new Error('Falta la ruta a frontend/src/locales de Rinde Web');
const BS = String.fromCharCode(92);
const NL = String.fromCharCode(10);
// t( o tr( justo antes de la comilla.
const TR_CALL = new RegExp('(^|[^A-Za-z0-9_])tr?' + BS + '(' + BS + 's*$');

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, out);
    else if (name.endsWith('.dart') && !name.endsWith('.g.dart')) out.push(path);
  }
  return out;
}

// Literales de una sola comilla de Dart (con sus escapes), y cuáles van dentro de t('…') o tr('…').
// Entra en las interpolaciones ${…}: un t('…') dentro de otro texto también es una clave.
function literals(source) {
  const all = [];
  const inT = [];

  // Lee el literal que abre en i; devuelve el índice de su comilla de cierre.
  function str(i) {
    const raw = source[i - 1] === 'r';
    let j = i + 1;
    let text = '';
    while (j < source.length && source[j] !== "'" && source[j] !== NL) {
      if (!raw && source[j] === BS) {
        text += source[j + 1];
        j += 2;
      } else if (!raw && source[j] === '$' && source[j + 1] === '{') {
        const close = expr(j + 2);
        text += source.slice(j, close + 1);
        j = close + 1;
      } else {
        text += source[j];
        j++;
      }
    }
    if (source[j] !== "'") return j;
    all.push(text);
    if (TR_CALL.test(source.slice(Math.max(0, i - 40), i))) {
      inT.push({ text, line: source.slice(0, i).split(NL).length });
    }
    return j;
  }

  // Salta una interpolación (con sus literales anidados); devuelve el índice de la llave de cierre.
  function expr(j) {
    let depth = 1;
    while (j < source.length) {
      if (source[j] === "'") {
        j = str(j) + 1;
        continue;
      }
      if (source[j] === '{') depth++;
      else if (source[j] === '}' && --depth === 0) return j;
      j++;
    }
    return j;
  }

  for (let i = 0; i < source.length; i++) {
    if (source[i] !== "'") continue;
    // Saltar comentarios de línea.
    const lineStart = source.lastIndexOf(NL, i) + 1;
    if (source.slice(lineStart, i).includes('//')) continue;
    i = str(i);
  }
  return { all, inT };
}

const root = fileURLToPath(new URL('..', import.meta.url));
const used = new Set();
// Clave de t('…') → primer lugar donde se usa, para decir qué archivo la pide.
const keys = new Map();
for (const file of walk(join(root, 'lib'))) {
  const { all, inT } = literals(readFileSync(file, 'utf8'));
  all.forEach((s) => used.add(s));
  const where = relative(root, file).split(sep).join('/');
  for (const { text, line } of inT) if (!keys.has(text)) keys.set(text, `${where}:${line}`);
}

// Clave → idiomas en los que falta.
const missing = new Map();
const unused = new Set();
for (const language of ['en', 'pt']) {
  const dir = join(localesDir, language);
  const web = {};
  for (const name of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
    Object.assign(web, JSON.parse(readFileSync(join(dir, name), 'utf8')));
  }
  const mobile = JSON.parse(readFileSync(join(root, 'tool', 'l10n_mobile', `${language}.json`), 'utf8'));
  const merged = { ...web, ...mobile };
  const out = {};
  for (const text of [...new Set([...used, ...Object.keys(mobile)])].sort()) {
    if (merged[text] !== undefined) out[text] = merged[text];
  }
  writeFileSync(join(root, 'assets', 'l10n', `${language}.json`), JSON.stringify(out, null, 1) + '\n');
  for (const key of keys.keys()) {
    if (!merged[key]) missing.set(key, [...(missing.get(key) ?? []), language]);
  }
  Object.keys(mobile).filter((k) => !used.has(k)).forEach((k) => unused.add(k));
  console.log(
    `${language}: ${Object.keys(out).length} traducciones (${Object.keys(mobile).length} propias de la app)`,
  );
}

if (unused.size > 0) {
  console.log(`\nAviso: ${unused.size} claves de tool/l10n_mobile no aparecen en lib/ (revisa si sobran):`);
  [...unused].sort().forEach((k) => console.log(`  - «${k}»`));
}
if (missing.size === 0) {
  console.log("\nTodos los textos de t('…') tienen traducción en inglés y en portugués.");
} else {
  console.error(`\nFALTAN ${missing.size} textos de t('…') sin traducción; se verían en español.`);
  console.error('Agrégalos en tool/l10n_mobile/en.json y pt.json y vuelve a generar:');
  for (const key of [...missing.keys()].sort()) {
    console.error(`  [${missing.get(key).join(' ')}] «${key}»  (${keys.get(key)})`);
  }
  process.exitCode = 1;
}
