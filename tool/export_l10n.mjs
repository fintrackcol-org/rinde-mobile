// Genera assets/l10n/{en,pt}.json con las traducciones de Rinde Web que usa la app móvil.
// La clave es el texto en español (igual que la web). Solo se copian las que aparecen en lib/.
//
//   node tool/export_l10n.mjs <ruta a fintrack/frontend/src/locales>
//
// Al final lista los textos de t('…') que la web no tiene traducidos (quedan en español).
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

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
    if (TR_CALL.test(source.slice(Math.max(0, i - 40), i))) inT.push(text);
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

const used = new Set();
const keys = new Set();
for (const file of walk(new URL('../lib', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))) {
  const { all, inT } = literals(readFileSync(file, 'utf8'));
  all.forEach((s) => used.add(s));
  inT.forEach((s) => keys.add(s));
}

const missing = {};
for (const language of ['en', 'pt']) {
  const dir = join(localesDir, language);
  const web = {};
  for (const name of readdirSync(dir).filter((n) => n.endsWith('.json')).sort()) {
    Object.assign(web, JSON.parse(readFileSync(join(dir, name), 'utf8')));
  }
  const out = {};
  for (const text of [...used].sort()) if (web[text] !== undefined) out[text] = web[text];
  writeFileSync(new URL(`../assets/l10n/${language}.json`, import.meta.url), JSON.stringify(out, null, 1) + '\n');
  missing[language] = [...keys].filter((k) => web[k] === undefined).sort();
  console.log(`${language}: ${Object.keys(out).length} traducciones`);
}
const both = missing.en.filter((k) => missing.pt.includes(k));
console.log(`\nTextos de t('…') sin traducción en la web (${both.length}); se verán en español:`);
both.forEach((k) => console.log('  - ' + k));
