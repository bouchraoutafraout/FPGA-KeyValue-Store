${ErrorActionPreference} = 'Continue'
$ErrorActionPreference = "Stop"
Set-Location "C:\Users\nadush\Desktop\projet_blockchain"
$f=".\Nada\Integration_Finale"; $n=".\Nada\Integration_Blockchain\Storage_V2"; $d=".\Nada\Integration_KV_CANFD"
$s2=".\sanae\semaine2"; $s4=".\sanae\semaine4"; $k=".\Khadija\semaine3"; $b=".\Bouchra\SHA256_ChainValidator_2026_10_28"
$common=@(
 "$f\canfd_blockchain_chain_guarded_top.v", "$f\blockchain_kvs_search_chain_guarded_top.v",
 "$f\block_builder_nada_sha_storage_chain_safe_top.v", "$f\block_builder_safe.v",
 "$f\blockchain_storage_adapter_chain.v", "$f\cuckoo_top_atomic_overflow_safe.v",
 "$n\blockchain_storage.v", "$s4\transaction_validator.v", "$s2\cuckoo_insert.v",
 "$s2\hash_function1.v", "$s2\hash_function2.v", "$k\bram_table.v", "$k\hashtables.v",
 "$b\sha256_core.v", "$b\chain_validator.v", "$d\canfd_rx.v", "$d\canfd_tx.v",
 "$d\canfd_rx_adapter.v", "$d\cmd_decoder.v", "$d\canfd_response_encoder.v",
 "$d\canfd_bit_timer.v", "$d\canfd_stuffer.v", "$d\canfd_crc.v", "$d\canfd_crcfield.v"
)
$tests=@(
 @("canfd_blockchain_guarded_fault_tb", "CREATE BRAM fault"),
 @("canfd_blockchain_guarded_transfer_tb", "TRANSFER BRAM fault"),
 @("canfd_blockchain_guarded_collision_tb", "CUCKOO collision"),
 @("canfd_blockchain_guarded_overflow_tb", "FORCED journal overflow (diagnostic)")
)
foreach ($t in $tests) {
 $tb="$f\$($t[0]).v"
 $all=@($tb)+$common
 $missing=@($all | Where-Object { -not (Test-Path $_) })
 if ($missing.Count -gt 0) { Write-Host "MISSING for $($t[1]): $($missing -join ', ')"; continue }
 Write-Host "===== $($t[1]) ====="
 $vvp="$f\$($t[0]).vvp"
 & iverilog -g2012 -s $t[0] -o $vvp $all
 if ($LASTEXITCODE -ne 0) { Write-Host "COMPILE FAIL: $($t[0])"; continue }
 & vvp $vvp
 if ($LASTEXITCODE -ne 0) { Write-Host "SIM FAILED: $($t[0])" }
}

