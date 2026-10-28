CAN-FD -> Blockchain FSM -> Storage V2

1. Extract these two .v files into:
C:\Users\nadush\Desktop\projet_blockchain\Nada\Integration_Blockchain\Storage_V2

2. Run in PowerShell:
cd "C:\Users\nadush\Desktop\projet_blockchain\Nada\Integration_Blockchain\Storage_V2"
$kv = Get-ChildItem "..\..\Integration_KV_CANFD\*.v" | Where-Object { $_.Name -notmatch '_tb\.v$|before' } | ForEach-Object { $_.FullName }
$src = @(".\blockchain_system_storage_v2_tb.v", ".\blockchain_system_storage_v2_top.v", ".\blockchain_top.v", ".\blockchain_storage_adapter.v", ".\blockchain_storage.v", "..\blockchain_system_top.v", "..\blockchain_ingress.v")
iverilog -g2012 -s blockchain_system_storage_v2_tb -o full_storage_v2_test.vvp $src $kv
if ($LASTEXITCODE -eq 0) { vvp full_storage_v2_test.vvp }

Notes: This verifies behavioral storage but validator/builder/SHA remain simulated. Two separate CAN buses and independently operating Cuckoo KVS remain; not an atomic or FPGA-validated system.
