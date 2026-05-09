@echo off
REM Rhino.fi On-Chain Verification via curl
REM Все запросы read-only через JSON-RPC

set RPC=https://eth.drpc.org
set BRIDGE=0xbca3039a18c0d2f2f84ba8a028c67290bc045afa

echo ========================================
echo Rhino.fi On-Chain Verification
echo ========================================
echo.

REM ===== Шаг 1: Проверяем что контракт существует =====
echo === 1. Bridge contract exists? ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"%BRIDGE%\",\"latest\"],\"id\":1}"
echo.
echo.

REM ===== Шаг 2: Читаем EIP-1967 implementation slot =====
echo === 2. EIP-1967 Implementation slot ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getStorageAt\",\"params\":[\"%BRIDGE%\",\"0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc\",\"latest\"],\"id\":2}"
echo.
echo.

REM ===== Шаг 3: Читаем storage slot 3 (depositsDisallowed) =====
echo === 3. Storage slot 3 (depositsDisallowed) ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getStorageAt\",\"params\":[\"%BRIDGE%\",\"0x3\",\"latest\"],\"id\":3}"
echo.
echo.

REM ===== Шаг 4: Читаем storage slot 5 (BridgeVM address) =====
echo === 4. Storage slot 5 (BridgeVM address) ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getStorageAt\",\"params\":[\"%BRIDGE%\",\"0x5\",\"latest\"],\"id\":4}"
echo.
echo.

REM ===== Шаг 5: Вызываем owner() =====
echo === 5. owner() ===
curl.exe -s -X POST %RPC% -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"to\":\"%BRIDGE%\",\"data\":\"0x8da5cb5b\"},\"latest\"],\"id\":5}"
echo.
echo.

echo ===== DONE =====
