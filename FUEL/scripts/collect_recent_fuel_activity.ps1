$ErrorActionPreference = "Stop"

$endpoint = "https://mainnet.fuel.network/v1/graphql"

function Invoke-FuelQuery($query, $variables = $null) {
  $payload = @{ query = $query }
  if ($variables) {
    $payload.variables = $variables
  }
  $body = $payload | ConvertTo-Json -Depth 30
  $res = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json" -Body $body
  if ($res.errors) {
    throw ($res.errors | ConvertTo-Json -Depth 10)
  }
  return $res.data
}

$query = @"
query RecentTx(`$before: String) {
  transactions(last: 25, before: `$before) {
    pageInfo { startCursor hasPreviousPage }
    edges {
      cursor
      node {
        id
        inputContracts
        isScript
        isCreate
        isUpgrade
        isUpload
        isBlob
        scriptGasLimit
        status {
          __typename
          ... on SuccessStatus {
            time
            block { header { height } }
            receipts { receiptType contractId to amount assetId gas gasUsed sender recipient nonce }
          }
          ... on FailureStatus {
            time
            reason
            block { header { height } }
            receipts { receiptType contractId to amount assetId gas gasUsed sender recipient nonce }
          }
        }
      }
    }
  }
}
"@

$all = @()
$before = $null

for ($i = 0; $i -lt 40; $i++) {
  $vars = if ($before) { @{ before = $before } } else { @{} }
  $data = Invoke-FuelQuery $query $vars
  $edges = @($data.transactions.edges)
  if ($edges.Count -eq 0) {
    break
  }
  $all += $edges.node
  $before = $data.transactions.pageInfo.startCursor
  Start-Sleep -Milliseconds 200
}

$all | ConvertTo-Json -Depth 50 | Set-Content -Encoding UTF8 data/recent_transactions_sample.json

$counts = @{}
foreach ($tx in $all) {
  $contracts = New-Object System.Collections.Generic.HashSet[string]
  foreach ($c in @($tx.inputContracts)) {
    if ($c -and $c -notmatch '^0x7{64}$') {
      [void]$contracts.Add($c)
    }
  }
  foreach ($r in @($tx.status.receipts)) {
    foreach ($field in @('contractId', 'to')) {
      $v = $r.$field
      if ($v -and $v -match '^0x[0-9a-fA-F]{64}$' -and $v -notmatch '^0x7{64}$') {
        [void]$contracts.Add($v)
      }
    }
  }
  foreach ($c in $contracts) {
    if (-not $counts.ContainsKey($c)) {
      $counts[$c] = [ordered]@{
        contract = $c
        tx_count = 0
        call_receipts = 0
        transfer_amount_events = 0
        gas_used = 0
      }
    }
    $counts[$c].tx_count += 1
  }
  foreach ($r in @($tx.status.receipts)) {
    $c = $r.contractId
    if ($c -and $counts.ContainsKey($c)) {
      if ($r.receiptType -eq 'CALL') {
        $counts[$c].call_receipts += 1
      }
      if ($r.amount) {
        $counts[$c].transfer_amount_events += 1
      }
      if ($r.gasUsed) {
        $counts[$c].gas_used += [int64]$r.gasUsed
      }
    }
  }
}

$ordered = @($counts.Values | ForEach-Object { [pscustomobject]$_ } | Sort-Object tx_count -Descending)
$ordered | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 data/contract_activity_sample.json
$ordered | Select-Object -First 100 | Export-Csv -NoTypeInformation -Encoding UTF8 data/contract_activity_sample.csv

"Fetched $($all.Count) transactions; contracts: $($counts.Count)"
