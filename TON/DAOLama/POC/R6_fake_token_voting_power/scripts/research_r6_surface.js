const fs = require('fs');
const path = require('path');

const ROOT = process.cwd();
const SEARCH_TERMS = [
  'vote',
  'voting',
  'govern',
  'snapshot',
  'quorum',
  'delegat',
  'proposal',
  'jetton',
  'token'
];

function listJsFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === 'POC') continue;
      out.push(...listJsFiles(full));
      continue;
    }
    if (/\.(js|json|html|md)$/i.test(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

function main() {
  const files = listJsFiles(ROOT);
  const hits = [];

  for (const file of files) {
    const rel = path.relative(ROOT, file);
    const content = fs.readFileSync(file, 'utf8');
    const lower = content.toLowerCase();
    const matched = SEARCH_TERMS.filter((term) => lower.includes(term));
    if (matched.length) {
      hits.push({
        file: rel,
        matched_terms: matched
      });
    }
  }

  console.log(JSON.stringify({
    searched_terms: SEARCH_TERMS,
    hit_count: hits.length,
    hits: hits.slice(0, 50)
  }, null, 2));
}

main();
