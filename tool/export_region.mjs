// Genera lib/core/region/region_data.g.dart desde lib/region.js de Rinde Web (solo lectura).
// Dart no tiene Intl.DisplayNames ni los formatos de ICU, así que nombres y formatos se calculan aquí
// con el mismo motor que usa la web y se guardan ya resueltos.
//
//   node tool/export_region.mjs <ruta a fintrack/frontend/src/lib/region.js>
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const src = process.argv[2];
if (!src) throw new Error('Falta la ruta a region.js de Rinde Web');
const region = await import(pathToFileURL(src).href);
const { COUNTRIES, LANGUAGES, DEFAULT_REGION, countryName, currencyName, moneySample, localeFor } = region;
const LANGS = LANGUAGES.map((l) => l.code);

// Literal de texto Dart: escapa la barra, la comilla y el signo de dólar (interpolación).
const BS = String.fromCharCode(92);
const q = (s) =>
  "'" + String(s).split(BS).join(BS + BS).split("'").join(BS + "'").split('$').join(BS + '$') + "'";

function format(country, currency) {
  const locale = localeFor({ country, currency });
  const nf = (d) =>
    new Intl.NumberFormat(locale, { style: 'currency', currency, minimumFractionDigits: d, maximumFractionDigits: d });
  const parts = nf(2).formatToParts(1234567.5);
  const first = parts.findIndex((p) => p.type === 'integer');
  const last = parts.findLastIndex((p) => p.type === 'integer' || p.type === 'fraction');
  const prefix = parts.slice(0, first).map((p) => p.value).join('');
  const suffix = parts.slice(last + 1).map((p) => p.value).join('');
  const plain = new Intl.NumberFormat(locale).formatToParts(12345.6);
  const groupsFourDigits = new Intl.NumberFormat(locale, { style: 'currency', currency, maximumFractionDigits: 0 })
    .formatToParts(1250)
    .some((p) => p.type === 'group');
  return {
    locale,
    prefix,
    suffix,
    group: parts.find((p) => p.type === 'group')?.value ?? '.',
    decimal: parts.find((p) => p.type === 'decimal')?.value ?? ',',
    inputGroup: plain.find((p) => p.type === 'group')?.value ?? '.',
    inputDecimal: plain.find((p) => p.type === 'decimal')?.value ?? ',',
    minGrouping: groupsFourDigits ? 1 : 2,
    // Tamaño de los grupos después del primero (2 en India: 12,34,567).
    secondaryGroup: (() => {
      const ints = parts.filter((p) => p.type === 'integer').map((p) => p.value);
      return ints.length > 2 ? ints[ints.length - 2].length : 3;
    })(),
  };
}

const rows = COUNTRIES.map(({ code, currency, language, timeZone }) => {
  const f = format(code, currency);
  const names = Object.fromEntries(LANGS.map((l) => [l, countryName(code, l)]));
  const currencyNames = Object.fromEntries(LANGS.map((l) => [l, currencyName(currency, l)]));
  const sample = moneySample(code, currency === 'COP' ? 1250000 : 1250.5);
  return { code, currency, language, timeZone, names, currencyNames, sample, ...f };
});

// Ejemplos para comprobar en Dart que el formato sale igual que en la web (formatMoney de regionFormats).
const examples = rows.map((r) => {
  const nf = (d) =>
    new Intl.NumberFormat(r.locale, {
      style: 'currency',
      currency: r.currency,
      minimumFractionDigits: d,
      maximumFractionDigits: d,
    });
  const money = (a) => (Number.isInteger(a) ? nf(0) : nf(2)).format(a);
  return { code: r.code, cases: [40000, 1250, 1234567.5, 9999999999.99, 0.5, 38].map((a) => [a, money(a)]) };
});

const map = (o) => `{${Object.entries(o).map(([k, v]) => `${q(k)}: ${q(v)}`).join(', ')}}`;
let out = `// GENERADO por tool/export_region.mjs desde lib/region.js de Rinde Web. No editar a mano.
part of 'region.dart';

const kLanguages = <Language>[
${LANGUAGES.map((l) => `  Language(${q(l.code)}, ${q(l.name)}),`).join('\n')}
];

const kDefaultRegion = Region(country: ${q(DEFAULT_REGION.country)}, currency: ${q(DEFAULT_REGION.currency)}, language: ${q(DEFAULT_REGION.language)});

const kCountries = <Country>[
`;
for (const r of rows) {
  out += `  Country(
    code: ${q(r.code)},
    currency: ${q(r.currency)},
    language: ${q(r.language)},
    timeZone: ${q(r.timeZone)},
    names: ${map(r.names)},
    currencyNames: ${map(r.currencyNames)},
    sample: ${q(r.sample)},
    format: MoneyFormat(
      prefix: ${q(r.prefix)},
      suffix: ${q(r.suffix)},
      group: ${q(r.group)},
      decimal: ${q(r.decimal)},
      inputGroup: ${q(r.inputGroup)},
      inputDecimal: ${q(r.inputDecimal)},
      minGrouping: ${r.minGrouping},${r.secondaryGroup === 3 ? '' : `
      secondaryGroup: ${r.secondaryGroup},`}
    ),
  ),
`;
}
out += '];\n';
writeFileSync(new URL('../lib/core/region/region_data.g.dart', import.meta.url), out);
writeFileSync(new URL('../test/core/region_examples.json', import.meta.url), JSON.stringify(examples, null, 1));
console.log(`${rows.length} países, ${new Set(rows.map((r) => r.currency)).size} monedas, idiomas: ${LANGS.join(', ')}`);
