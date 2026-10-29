$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\nadush\Desktop\projet_blockchain'
$f='.\Nada\Integration_Finale'; $n='.\Nada\Integration_Blockchain\Storage_V2'; $d='.\Nada\Integration_KV_CANFD'
$s2='.\sanae\semaine2'; $s4='.\sanae\semaine4'; $k='.\Khadija\semaine3'; $b='.\Bouchra\SHA256_ChainValidator_2026_10_28'
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
$tb="$f\canfd_blockchain_journal_realwrites_tb.v"
$files=@($tb)+$common
$missing=@($files | Where-Object { -not (Test-Path $_) })
if ($missing.Count -gt 0) { Write-Host "MISSING: $($missing -join ', ')"; return }
$vvp="$f\canfd_blockchain_journal_realwrites_tb.vvp"
& iverilog -g2012 -s canfd_blockchain_journal_realwrites_tb -o $vvp $files
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL: COMPILE'; return }
& vvp $vvp
