import fs from "node:fs/promises";
import path from "node:path";

const ROOT = process.cwd();
const OUT = path.join(ROOT, "aleo_context");
const API = "https://api.explorer.provable.com/v2";
const API_V1 = "https://api.explorer.provable.com/v1";
const NETWORKS = ["mainnet", "testnet"];

async function getJson(url) {
  const response = await fetch(url, { headers: { "user-agent": "aleo-context-collector/1.0" } });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}: ${await response.text()}`);
  return response.json();
}

async function getText(url) {
  const value = await getJson(url);
  return typeof value === "string" ? value : JSON.stringify(value, null, 2);
}

async function writeText(filePath, content) {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, content, "utf8");
}

function safeName(programId) {
  return programId.replaceAll("/", "_");
}

function unique(values) {
  return [...new Set(values.filter(Boolean))].sort();
}

function matchAll(source, regex) {
  return [...source.matchAll(regex)];
}

function parseBlockItems(source, keyword) {
  const heading = new RegExp(`^${keyword}\\s+([A-Za-z0-9_]+):\\s*$`, "gm");
  const matches = matchAll(source, heading);
  const items = {};
  for (let i = 0; i < matches.length; i += 1) {
    const name = matches[i][1];
    const start = matches[i].index + matches[i][0].length;
    let end = i + 1 < matches.length ? matches[i + 1].index : source.length;
    const tail = source.slice(start);
    const nextTop = tail.search(/^(mapping|struct|record|function|finalize|closure|constructor)\s+[A-Za-z0-9_]+:|^import\s+/m);
    if (nextTop >= 0) end = Math.min(end, start + nextTop);
    items[name] = source.slice(start, end).replace(/^\n+|\n+$/g, "");
  }
  return items;
}

function parseIo(body = "") {
  const inputs = matchAll(body, /^\s*input\s+([A-Za-z0-9_]+)\s+as\s+([^;]+);/gm).map((m) => ({
    register: m[1],
    type: m[2].trim(),
  }));
  const outputs = matchAll(body, /^\s*output\s+([A-Za-z0-9_]+)\s+as\s+([^;]+);/gm).map((m) => ({
    register: m[1],
    type: m[2].trim(),
  }));
  return { inputs, outputs };
}

function parseMapping(body = "") {
  return {
    key: body.match(/key\s+as\s+([^;]+);/)?.[1]?.trim() ?? null,
    value: body.match(/value\s+as\s+([^;]+);/)?.[1]?.trim() ?? null,
  };
}

function parseFields(body = "") {
  return matchAll(body, /^\s*([A-Za-z0-9_]+)\s+as\s+([^;]+);/gm).map((m) => ({
    name: m[1],
    type: m[2].trim(),
  }));
}

function refsIn(text, programId) {
  return unique(matchAll(text ?? "", /\b([a-z][a-z0-9_]*\.aleo)(?=\/|::)/g).map((m) => m[1]).filter((x) => x !== programId));
}

function stateWrites(text = "") {
  const setWrites = matchAll(text, /\bset\s+[^;\n]+?\s+into\s+([A-Za-z0-9_]+)\[/g).map((m) => m[1]);
  const removes = matchAll(text, /\bremove\s+([A-Za-z0-9_]+)\[/g).map((m) => m[1]);
  return unique([...setWrites, ...removes]);
}

function conditionMarkers(text = "") {
  return unique(matchAll(text, /\b(assert\.[a-z]+|branch\.[a-z]+|ternary|gte|lte|lt|gt|is\.eq|nor|and|or)\b/g).map((m) => m[1]));
}

function parseProgram(programId, source, calls) {
  const functions = parseBlockItems(source, "function");
  const finalizers = parseBlockItems(source, "finalize");
  const mappings = parseBlockItems(source, "mapping");
  const structs = parseBlockItems(source, "struct");
  const records = parseBlockItems(source, "record");
  const imports = unique(matchAll(source, /^import\s+([a-z][a-z0-9_]*\.aleo);/gm).map((m) => m[1]));
  const parsedFunctions = {};

  for (const [name, body] of Object.entries(functions)) {
    const finalize = finalizers[name] ?? "";
    const { inputs, outputs } = parseIo(body);
    parsedFunctions[name] = {
      inputs,
      outputs,
      has_finalize: Boolean(finalizers[name]),
      async: body.includes("async "),
      returns_future: body.includes(".future"),
      cross_contract_refs: refsIn(body, programId),
      state_reads: unique(matchAll(body, /\b(?:get|get\.or_use|contains)\s+([A-Za-z0-9_]+)\[/g).map((m) => m[1])),
      state_writes: stateWrites(body),
      conditional_markers: conditionMarkers(body),
      finalize_inputs: parseIo(finalize).inputs,
      finalize_state_reads: unique(matchAll(finalize, /\b(?:get|get\.or_use|contains)\s+([A-Za-z0-9_]+)\[/g).map((m) => m[1])),
      finalize_state_writes: stateWrites(finalize),
      finalize_uses_block_height: finalize.includes("block.height"),
      finalize_conditional_markers: conditionMarkers(finalize),
      snark_verify: body.includes("snark.verify") || finalize.includes("snark.verify"),
    };
  }

  const asyncOrConditional = Object.entries(parsedFunctions)
    .filter(([, data]) => data.async || data.has_finalize || data.finalize_uses_block_height || data.conditional_markers.length || data.finalize_conditional_markers.length)
    .map(([name]) => name);

  return {
    program_id: programId,
    calls_24h_or_metric_window: calls,
    imports,
    mappings: Object.fromEntries(Object.entries(mappings).map(([name, body]) => [name, parseMapping(body)])),
    structs: Object.fromEntries(Object.entries(structs).map(([name, body]) => [name, parseFields(body)])),
    records: Object.fromEntries(Object.entries(records).map(([name, body]) => [name, parseFields(body)])),
    functions: parsedFunctions,
    finalizers: Object.keys(finalizers).sort(),
    cross_contract_refs: refsIn(source, programId),
    async_or_conditional_paths: asyncOrConditional,
    state_commitment_surfaces: {
      records: Object.keys(records).sort(),
      mappings: Object.keys(mappings).sort(),
      future_outputs: Object.entries(parsedFunctions).flatMap(([fn, data]) =>
        data.outputs.filter((output) => output.type.endsWith(".future")).map((output) => ({ function: fn, output: output.type })),
      ),
    },
    event_model_note:
      "Aleo does not expose EVM-style events in program source; observable commitments are records, transitions, futures/finalize effects, and mapping updates.",
  };
}

function classifyPath(programId) {
  const p = programId.toLowerCase();
  if (/(bridge|warp|hyp_|mailbox|gmp|connection|vlink)/.test(p)) return "bridge/cross-chain";
  if (/(stake|staking|delegator|validator|pondo|whalepool)/.test(p)) return "staking/liquid staking";
  if (/(token|stablecoin|usdc|usad|wrapped|credits)/.test(p)) return "token/credit flow";
  if (/(oracle|checksum|rate_limit)/.test(p)) return "oracle/governance guard";
  if (/(nft|ticket|arcade|mint)/.test(p)) return "NFT/game asset";
  if (/(pool|swap|lend|flash|arcn|dara)/.test(p)) return "DeFi pool/lending";
  return "application/other";
}

async function collectNetwork(network) {
  const rawDir = path.join(OUT, "raw", network);
  const sourceDir = path.join(rawDir, "program_sources");
  const parsedDir = path.join(OUT, "parsed", network);
  const metrics = await getJson(`${API}/${network}/metrics/programs`);
  await writeText(path.join(rawDir, "program_metrics.json"), JSON.stringify(metrics, null, 2));
  await writeText(path.join(rawDir, "latest_height.txt"), `${(await getText(`${API_V1}/${network}/latest/height`)).trim()}\n`);

  const parsed = [];
  const failures = [];
  for (const item of metrics) {
    try {
      const source = await getText(`${API}/${network}/program/${item.program_id}`);
      await writeText(path.join(sourceDir, `${safeName(item.program_id)}.aleo`), source);
      const data = parseProgram(item.program_id, source, item.calls ?? 0);
      await writeText(path.join(parsedDir, `${safeName(item.program_id)}.json`), JSON.stringify(data, null, 2));
      parsed.push(data);
      await new Promise((resolve) => setTimeout(resolve, 80));
    } catch (error) {
      failures.push({ program_id: item.program_id, error: String(error.message ?? error) });
    }
  }

  await writeText(path.join(rawDir, "download_failures.json"), JSON.stringify(failures, null, 2));
  await writeText(path.join(parsedDir, "programs_summary.json"), JSON.stringify(parsed, null, 2));
  const csv = [
    "program_id,calls,functions,mappings,records,imports,cross_contract_refs,async_or_conditional_paths",
    ...parsed.map((p) =>
      [
        p.program_id,
        p.calls_24h_or_metric_window,
        Object.keys(p.functions).length,
        Object.keys(p.mappings).length,
        Object.keys(p.records).length,
        `"${p.imports.join(" ")}"`,
        `"${p.cross_contract_refs.join(" ")}"`,
        `"${p.async_or_conditional_paths.join(" ")}"`,
      ].join(","),
    ),
  ].join("\n");
  await writeText(path.join(parsedDir, "programs_summary.csv"), `${csv}\n`);
  return { parsed, failures };
}

async function writeGraphs(allData) {
  const dot = ["digraph aleo_program_dependencies {", "  rankdir=LR;"];
  const md = ["# Aleo dependency graph", ""];
  for (const [network, programs] of Object.entries(allData)) {
    md.push(`## ${network}`);
    for (const program of programs) {
      const refs = unique([...program.imports, ...program.cross_contract_refs]);
      if (refs.length) {
        for (const ref of refs) dot.push(`  "${network}:${program.program_id}" -> "${network}:${ref}";`);
        md.push(`- \`${program.program_id}\` -> ${refs.map((ref) => `\`${ref}\``).join(", ")}`);
      } else {
        dot.push(`  "${network}:${program.program_id}";`);
      }
    }
    md.push("");
  }
  dot.push("}");
  await writeText(path.join(OUT, "graphs", "dependencies.dot"), `${dot.join("\n")}\n`);
  await writeText(path.join(OUT, "graphs", "dependencies.md"), md.join("\n"));
}

async function writeReports(allData, allFailures) {
  const lines = [
    "# Aleo context map",
    "",
    `Generated at: ${new Date().toISOString()}`,
    "",
    "Scope: active programs returned by Provable `/v2/{network}/metrics/programs`, with full source pulled from `/v2/{network}/program/{program_id}`.",
    "AleoScan registry pages were used as a secondary explorer reference, but local collection avoids Cloudflare-protected scraping.",
    "",
    "## Source folders",
    "",
    "- `raw/mainnet/program_sources/` and `raw/testnet/program_sources/`: downloaded Aleo Instruction sources.",
    "- `parsed/{network}/`: per-program JSON plus CSV summaries.",
    "- `graphs/dependencies.dot`: cross-program reference graph.",
    "- `reports/high_risk_async_paths.md`: async, delayed, conditional, and bridge/proof-sensitive paths.",
    "",
  ];

  for (const [network, programs] of Object.entries(allData)) {
    const totalCalls = programs.reduce((sum, p) => sum + p.calls_24h_or_metric_window, 0);
    lines.push(`## ${network}`, "", `- Programs collected: ${programs.length}`, `- Metric-window calls represented: ${totalCalls}`, `- Download failures: ${allFailures[network].length}`, "");
    lines.push("| Program | Calls | Class | Functions | Mappings | Cross refs | Async/conditional paths |");
    lines.push("|---|---:|---|---:|---:|---|---:|");
    for (const p of [...programs].sort((a, b) => b.calls_24h_or_metric_window - a.calls_24h_or_metric_window)) {
      lines.push(
        `| \`${p.program_id}\` | ${p.calls_24h_or_metric_window} | ${classifyPath(p.program_id)} | ${Object.keys(p.functions).length} | ${Object.keys(p.mappings).length} | ${p.cross_contract_refs.slice(0, 6).join(", ") || "-"} | ${p.async_or_conditional_paths.length} |`,
      );
    }
    lines.push("");
  }
  await writeText(path.join(OUT, "reports", "context_map.md"), lines.join("\n"));

  const risky = [
    "# Async, delayed, conditional, bridge/proof-sensitive paths",
    "",
    "Selection criteria: `async`, `finalize`, `.future`, `block.height`, branches/assertions/ternaries, `snark.verify`, or names indicating bridge/oracle/staking/token economic paths.",
    "",
  ];
  for (const [network, programs] of Object.entries(allData)) {
    risky.push(`## ${network}`);
    for (const p of [...programs].sort((a, b) => b.calls_24h_or_metric_window - a.calls_24h_or_metric_window)) {
      const importantName = classifyPath(p.program_id) !== "application/other";
      if (!p.async_or_conditional_paths.length && !importantName) continue;
      risky.push(`### \`${p.program_id}\` (${p.calls_24h_or_metric_window} calls, ${classifyPath(p.program_id)})`);
      if (p.cross_contract_refs.length) risky.push(`Cross-contract refs: ${p.cross_contract_refs.map((x) => `\`${x}\``).join(", ")}`);
      if (Object.keys(p.mappings).length) risky.push(`State mappings: ${Object.keys(p.mappings).map((x) => `\`${x}\``).join(", ")}`);
      for (const fn of p.async_or_conditional_paths) {
        const data = p.functions[fn];
        const flags = [];
        if (data.async) flags.push("async");
        if (data.has_finalize) flags.push("finalize");
        if (data.finalize_uses_block_height) flags.push("block.height delay");
        if (data.snark_verify) flags.push("snark.verify");
        if (data.cross_contract_refs.length) flags.push("cross-contract");
        risky.push(`- \`${fn}\`: ${flags.join(", ") || "conditional"}`);
      }
      risky.push("");
    }
  }
  await writeText(path.join(OUT, "reports", "high_risk_async_paths.md"), risky.join("\n"));

  const econ = [
    "# Economic paths and activity",
    "",
    "Calls are from Provable program metrics at collection time. TVL is not recomputed from private records; use this as a routing/activity map, not a balance attestation.",
    "",
  ];
  for (const [network, programs] of Object.entries(allData)) {
    econ.push(`## ${network}`);
    for (const p of [...programs].sort((a, b) => b.calls_24h_or_metric_window - a.calls_24h_or_metric_window)) {
      const cls = classifyPath(p.program_id);
      if (cls === "application/other" && p.calls_24h_or_metric_window < 50) continue;
      econ.push(`- \`${p.program_id}\`: ${p.calls_24h_or_metric_window} calls; class \`${cls}\`; state \`${Object.keys(p.mappings).slice(0, 8).join(", ") || "no public mappings parsed"}\`.`);
    }
    econ.push("");
  }
  await writeText(path.join(OUT, "reports", "economic_paths.md"), econ.join("\n"));
}

async function main() {
  await fs.mkdir(OUT, { recursive: true });
  const allData = {};
  const allFailures = {};
  for (const network of NETWORKS) {
    const { parsed, failures } = await collectNetwork(network);
    allData[network] = parsed;
    allFailures[network] = failures;
  }
  await writeGraphs(allData);
  await writeReports(allData, allFailures);
  await writeText(
    path.join(OUT, "sources.json"),
    JSON.stringify(
      {
        provable_v2_program_metrics: `${API}/{network}/metrics/programs`,
        provable_v2_program_source: `${API}/{network}/program/{program_id}`,
        provable_v2_program_mappings: `${API}/{network}/program/{program_id}/mappings`,
        provable_v1_latest_height: `${API_V1}/{network}/latest/height`,
        aleo_docs_programs: "https://developer.aleo.org/apis/v2/programs/",
        aleo_docs_program_metrics: "https://developer.aleo.org/apis/v2/program-metrics/",
        aleo_docs_defi: "https://developer.aleo.org/apis/v2/de-fi/",
        aleo_docs_staking: "https://developer.aleo.org/apis/v2/staking/",
        aleoscan_registry_reference: "https://aleoscan.io/programs and https://testnet.aleoscan.io/programs",
      },
      null,
      2,
    ),
  );
  console.log(`Wrote Aleo context to ${OUT}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
