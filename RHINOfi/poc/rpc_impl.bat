@echo off
set RPC=https://eth.drpc.org
set IMPL=0x3aa8e099b2c161edc19863f8d9820d65de501186

echo === Implementation bytecode ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"%IMPL%\",\"latest\"],\"id\":6}"
echo.
echo.
echo === DONE ===
