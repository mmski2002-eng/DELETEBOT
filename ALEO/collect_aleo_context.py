#!/usr/bin/env python3
import csv
import json
import re
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "aleo_context"
API = "https://api.explorer.provable.com/v2"
API_V1 = "https://api.explorer.provable.com/v1"
NETWORKS = ("mainnet", "testnet")


def get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "aleo-context-collector/1.0"})
    with urllib.request.urlopen(req, timeout=30) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw)


def get_text(url):
    value = get_json(url)
    return value if isinstance(value, str) else json.dumps(value, indent=2)


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def safe_name(program_id):
    return program_id.replace("/", "_")


def parse_block_items(source, keyword):
    items = {}
    pattern = re.compile(rf"^{keyword}\s+([A-Za-z0-9_]+):\s*$", re.MULTILINE)
    matches = list(pattern.finditer(source))
    for index, match in enumerate(matches):
        name = match.group(1)
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(source)
        next_top = re.search(
            r"^(mapping|struct|record|function|finalize|closure|constructor)\s+[A-Za-z0-9_]+:|^import\s+",
            source[start:],
            re.MULTILINE,
        )
        if next_top:
            end = min(end, start + next_top.start())
        body = source[start:end].strip("\n")
        items[name] = body
    return items


def parse_io(body):
    inputs = re.findall(r"^\s*input\s+([A-Za-z0-9_]+)\s+as\s+([^;]+);", body, re.MULTILINE)
    outputs = re.findall(r"^\s*output\s+([A-Za-z0-9_]+)\s+as\s+([^;]+);", body, re.MULTILINE)
    return [{"register": a, "type": b.strip()} for a, b in inputs], [
        {"register": a, "type": b.strip()} for a, b in outputs
    ]


def parse_mapping(body):
    key = re.search(r"key\s+as\s+([^;]+);", body)
    value = re.search(r"value\s+as\s+([^;]+);", body)
    return {
        "key": key.group(1).strip() if key else None,
        "value": value.group(1).strip() if value else None,
    }


def parse_fields(body):
    fields = []
    for name, typ in re.findall(r"^\s*([A-Za-z0-9_]+)\s+as\s+([^;]+);", body, re.MULTILINE):
        fields.append({"name": name, "type": typ.strip()})
    return fields


def parse_program(program_id, source, calls):
    functions = parse_block_items(source, "function")
    finalizers = parse_block_items(source, "finalize")
    mappings = parse_block_items(source, "mapping")
    structs = parse_block_items(source, "struct")
    records = parse_block_items(source, "record")

    parsed_functions = {}
    cross_refs = sorted(
        set(
            ref
            for ref in re.findall(r"\b([a-z][a-z0-9_]*\.aleo)(?=/|::)", source)
            if ref != program_id
        )
    )
    imports = re.findall(r"^import\s+([a-z][a-z0-9_]*\.aleo);", source, re.MULTILINE)

    for name, body in functions.items():
        inputs, outputs = parse_io(body)
        finalize = finalizers.get(name)
        parsed_functions[name] = {
            "inputs": inputs,
            "outputs": outputs,
            "has_finalize": finalize is not None,
            "async": "async " in body,
            "returns_future": ".future" in body,
            "cross_contract_refs": sorted(
                set(ref for ref in re.findall(r"\b([a-z][a-z0-9_]*\.aleo)(?=/|::)", body) if ref != program_id)
            ),
            "state_reads": sorted(set(re.findall(r"\b(?:get|get\.or_use|contains)\s+([A-Za-z0-9_]+)\[", body))),
            "state_writes": sorted(set(re.findall(r"\b(?:set|remove)\s+[^;\n]+?\s+into\s+([A-Za-z0-9_]+)\[|\bremove\s+([A-Za-z0-9_]+)\[", body))),
            "conditional_markers": sorted(set(re.findall(r"\b(assert\.[a-z]+|branch\.[a-z]+|ternary|gte|lte|lt|gt|is\.eq|nor|and|or)\b", body))),
            "finalize_inputs": parse_io(finalize)[0] if finalize else [],
            "finalize_state_reads": sorted(set(re.findall(r"\b(?:get|get\.or_use|contains)\s+([A-Za-z0-9_]+)\[", finalize or ""))),
            "finalize_state_writes": sorted(
                set(
                    item
                    for pair in re.findall(
                        r"\bset\s+[^;\n]+?\s+into\s+([A-Za-z0-9_]+)\[|\bremove\s+([A-Za-z0-9_]+)\[",
                        finalize or "",
                    )
                    for item in pair
                    if item
                )
            ),
            "finalize_uses_block_height": "block.height" in (finalize or ""),
            "finalize_conditional_markers": sorted(
                set(re.findall(r"\b(assert\.[a-z]+|branch\.[a-z]+|ternary|gte|lte|lt|gt|is\.eq|nor|and|or)\b", finalize or ""))
            ),
            "snark_verify": "snark.verify" in body or "snark.verify" in (finalize or ""),
        }

    async_paths = [
        name
        for name, data in parsed_functions.items()
        if data["async"]
        or data["has_finalize"]
        or data["finalize_uses_block_height"]
        or data["finalize_conditional_markers"]
        or data["conditional_markers"]
    ]

    return {
        "program_id": program_id,
        "calls_24h_or_metric_window": calls,
        "imports": sorted(set(imports)),
        "mappings": {name: parse_mapping(body) for name, body in mappings.items()},
        "structs": {name: parse_fields(body) for name, body in structs.items()},
        "records": {name: parse_fields(body) for name, body in records.items()},
        "functions": parsed_functions,
        "finalizers": sorted(finalizers.keys()),
        "cross_contract_refs": cross_refs,
        "async_or_conditional_paths": async_paths,
        "state_commitment_surfaces": {
            "records": sorted(records.keys()),
            "mappings": sorted(mappings.keys()),
            "future_outputs": [
                {"function": name, "output": output["type"]}
                for name, data in parsed_functions.items()
                for output in data["outputs"]
                if output["type"].endswith(".future")
            ],
        },
        "event_model_note": "Aleo does not expose EVM-style events in program source; observable commitments are records, transitions, futures/finalize effects, and mapping updates.",
    }


def collect_network(network):
    raw_dir = OUT / "raw" / network
    source_dir = raw_dir / "program_sources"
    parsed_dir = OUT / "parsed" / network

    metrics = get_json(f"{API}/{network}/metrics/programs")
    write_text(raw_dir / "program_metrics.json", json.dumps(metrics, indent=2))

    latest_height = get_text(f"{API_V1}/{network}/latest/height")
    write_text(raw_dir / "latest_height.txt", latest_height.strip() + "\n")

    parsed = []
    failures = []
    for item in metrics:
        program_id = item["program_id"]
        calls = item.get("calls", 0)
        try:
            source = get_text(f"{API}/{network}/program/{program_id}")
            write_text(source_dir / f"{safe_name(program_id)}.aleo", source)
            data = parse_program(program_id, source, calls)
            write_text(parsed_dir / f"{safe_name(program_id)}.json", json.dumps(data, indent=2))
            parsed.append(data)
            time.sleep(0.08)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            failures.append({"program_id": program_id, "error": str(exc)})

    write_text(raw_dir / "download_failures.json", json.dumps(failures, indent=2))
    write_text(parsed_dir / "programs_summary.json", json.dumps(parsed, indent=2))

    with (parsed_dir / "programs_summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "program_id",
                "calls",
                "functions",
                "mappings",
                "records",
                "imports",
                "cross_contract_refs",
                "async_or_conditional_paths",
            ]
        )
        for data in parsed:
            writer.writerow(
                [
                    data["program_id"],
                    data["calls_24h_or_metric_window"],
                    len(data["functions"]),
                    len(data["mappings"]),
                    len(data["records"]),
                    " ".join(data["imports"]),
                    " ".join(data["cross_contract_refs"]),
                    " ".join(data["async_or_conditional_paths"]),
                ]
            )

    return parsed, failures


def write_graphs(all_data):
    graph_dir = OUT / "graphs"
    lines = ["digraph aleo_program_dependencies {", "  rankdir=LR;"]
    md = ["# Aleo dependency graph", ""]
    for network, programs in all_data.items():
        md.append(f"## {network}")
        for program in programs:
            refs = sorted(set(program["imports"] + program["cross_contract_refs"]))
            if refs:
                for ref in refs:
                    lines.append(f'  "{network}:{program["program_id"]}" -> "{network}:{ref}";')
                md.append(f"- `{program['program_id']}` -> " + ", ".join(f"`{ref}`" for ref in refs))
            else:
                lines.append(f'  "{network}:{program["program_id"]}";')
        md.append("")
    lines.append("}")
    write_text(graph_dir / "dependencies.dot", "\n".join(lines) + "\n")
    write_text(graph_dir / "dependencies.md", "\n".join(md))


def classify_path(program_id):
    p = program_id.lower()
    if any(x in p for x in ("bridge", "warp", "hyp_", "mailbox", "gmp", "connection", "vlink")):
        return "bridge/cross-chain"
    if any(x in p for x in ("stake", "staking", "delegator", "validator", "pondo", "whalepool")):
        return "staking/liquid staking"
    if any(x in p for x in ("token", "stablecoin", "usdc", "usad", "wrapped", "credits")):
        return "token/credit flow"
    if any(x in p for x in ("oracle", "checksum", "rate_limit")):
        return "oracle/governance guard"
    if any(x in p for x in ("nft", "ticket", "arcade", "mint")):
        return "NFT/game asset"
    if any(x in p for x in ("pool", "swap", "lend", "flash", "arcn", "dara")):
        return "DeFi pool/lending"
    return "application/other"


def write_reports(all_data, failures):
    report_dir = OUT / "reports"
    generated_at = datetime.now(timezone.utc).isoformat()
    lines = [
        "# Aleo context map",
        "",
        f"Generated at: {generated_at}",
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
    ]
    for network, programs in all_data.items():
        total_calls = sum(p["calls_24h_or_metric_window"] for p in programs)
        lines.extend(
            [
                f"## {network}",
                "",
                f"- Programs collected: {len(programs)}",
                f"- Metric-window calls represented: {total_calls}",
                f"- Download failures: {len(failures.get(network, []))}",
                "",
                "| Program | Calls | Class | Functions | Mappings | Cross refs | Async/conditional paths |",
                "|---|---:|---|---:|---:|---|---:|",
            ]
        )
        for p in sorted(programs, key=lambda x: x["calls_24h_or_metric_window"], reverse=True):
            refs = ", ".join(p["cross_contract_refs"][:6])
            lines.append(
                f"| `{p['program_id']}` | {p['calls_24h_or_metric_window']} | {classify_path(p['program_id'])} | "
                f"{len(p['functions'])} | {len(p['mappings'])} | {refs or '-'} | {len(p['async_or_conditional_paths'])} |"
            )
        lines.append("")
    write_text(report_dir / "context_map.md", "\n".join(lines))

    risky = [
        "# Async, delayed, conditional, bridge/proof-sensitive paths",
        "",
        "Selection criteria: `async`, `finalize`, `.future`, `block.height`, branches/assertions/ternaries, `snark.verify`, or names indicating bridge/oracle/staking/token economic paths.",
        "",
    ]
    for network, programs in all_data.items():
        risky.append(f"## {network}")
        for p in sorted(programs, key=lambda x: x["calls_24h_or_metric_window"], reverse=True):
            important_name = classify_path(p["program_id"]) != "application/other"
            selected = p["async_or_conditional_paths"] or important_name
            if not selected:
                continue
            risky.append(f"### `{p['program_id']}` ({p['calls_24h_or_metric_window']} calls, {classify_path(p['program_id'])})")
            if p["cross_contract_refs"]:
                risky.append("Cross-contract refs: " + ", ".join(f"`{x}`" for x in p["cross_contract_refs"]))
            if p["mappings"]:
                risky.append("State mappings: " + ", ".join(f"`{x}`" for x in p["mappings"].keys()))
            for fn in p["async_or_conditional_paths"]:
                fndata = p["functions"][fn]
                flags = []
                if fndata["async"]:
                    flags.append("async")
                if fndata["has_finalize"]:
                    flags.append("finalize")
                if fndata["finalize_uses_block_height"]:
                    flags.append("block.height delay")
                if fndata["snark_verify"]:
                    flags.append("snark.verify")
                if fndata["cross_contract_refs"]:
                    flags.append("cross-contract")
                risky.append(f"- `{fn}`: {', '.join(flags) or 'conditional'}")
            risky.append("")
    write_text(report_dir / "high_risk_async_paths.md", "\n".join(risky))

    econ = [
        "# Economic paths and activity",
        "",
        "Calls are from Provable program metrics at collection time. TVL is not recomputed from private records; use this as a routing/activity map, not a balance attestation.",
        "",
    ]
    for network, programs in all_data.items():
        econ.append(f"## {network}")
        for p in sorted(programs, key=lambda x: x["calls_24h_or_metric_window"], reverse=True):
            cls = classify_path(p["program_id"])
            if cls == "application/other" and p["calls_24h_or_metric_window"] < 50:
                continue
            econ.append(
                f"- `{p['program_id']}`: {p['calls_24h_or_metric_window']} calls; class `{cls}`; "
                f"state `{', '.join(list(p['mappings'].keys())[:8]) or 'no public mappings parsed'}`."
            )
        econ.append("")
    write_text(report_dir / "economic_paths.md", "\n".join(econ))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    all_data = {}
    failures = {}
    for network in NETWORKS:
        programs, failed = collect_network(network)
        all_data[network] = programs
        failures[network] = failed
    write_graphs(all_data)
    write_reports(all_data, failures)
    write_text(
        OUT / "sources.json",
        json.dumps(
            {
                "provable_v2_program_metrics": f"{API}/{{network}}/metrics/programs",
                "provable_v2_program_source": f"{API}/{{network}}/program/{{program_id}}",
                "provable_v2_program_mappings": f"{API}/{{network}}/program/{{program_id}}/mappings",
                "provable_v1_latest_height": f"{API_V1}/{{network}}/latest/height",
                "aleo_docs_programs": "https://developer.aleo.org/apis/v2/programs/",
                "aleo_docs_program_metrics": "https://developer.aleo.org/apis/v2/program-metrics/",
                "aleo_docs_defi": "https://developer.aleo.org/apis/v2/de-fi/",
                "aleo_docs_staking": "https://developer.aleo.org/apis/v2/staking/",
                "aleoscan_registry_reference": "https://aleoscan.io/programs and https://testnet.aleoscan.io/programs",
            },
            indent=2,
        ),
    )
    print(f"Wrote Aleo context to {OUT}")


if __name__ == "__main__":
    main()
