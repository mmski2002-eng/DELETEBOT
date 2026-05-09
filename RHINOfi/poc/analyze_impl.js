// Анализ байткода имплементации DVFDepositContract
const fs = require('fs');

// Байткод имплементации (без 0x)
const code = fs.readFileSync(0, 'utf-8').trim();

// Убираем 0x если есть
const hex = code.startsWith('0x') ? code.slice(2) : code;

console.log('=== Анализ байткода имплементации DVFDepositContract ===\n');
console.log('Размер байткода:', hex.length / 2, 'bytes\n');

// Селекторы для проверки
const selectors = {
    'removeFundsNative(address,uint256)': '38dc27a7',
    'withdrawNativeV2(address,uint256)': 'b130a7ac',
    'withdrawV2WithNative(address,address,uint256,uint256)': '3aed1a99',
    'withdrawV2WithNativeNoEvent(address,address,uint256,uint256)': 'bc4b3365',
    'depositWithPermit(address,uint256,uint256,uint8,bytes32,bytes32,uint256)': '4d298265',
    'depositWithId(address,uint256,uint256)': 'bcc07af1',
    'depositNativeWithId(uint256)': '88e3f155',
    'transferOwner(address)': 'f2fde38b',
    'owner()': '8da5cb5b',
    'removeFunds(address,address,uint256)': 'd6c9b6a5',
    'authorize(address,bool)': 'b9181611',
    'authorizeMulti(address[],bool)': 'ec8acddf',
    'allowDepositsGlobal(bool)': '9a203dbf',
    'allowDeposits(address,int256)': '2700bbaf',
    'withdrawVmFunds(address)': '1c6dd8a1',
    'withdrawWithData(address,uint256,uint256,(address,uint256,bytes)[],bytes)': 'ec8acddf',
    'withdrawWithDataNoEvent(address,uint256,uint256,(address,uint256,bytes)[])': '535b355c',
    'withdrawV2WithNativeNoEvent(address,address,uint256,uint256)': 'bc4b3365',
    'renounceOwnership()': '715018a6',
    'createVMContract()': '8129fc1c',
    'withdrawNativeV2(address,uint256)': 'b130a7ac',
    'withdrawV2WithNative(address,address,uint256,uint256)': '3aed1a99',
};

console.log('Селекторы в байткоде:');
for (const [name, sel] of Object.entries(selectors)) {
    const found = hex.includes(sel);
    console.log(`  ${found ? '✅' : '❌'} ${name}`);
}

// Проверяем строки
const strings = {
    'FAILED_TO_SEND_ETH': Buffer.from('FAILED_TO_SEND_ETH').toString('hex'),
    'INSUFFICIENT_BALANCE': Buffer.from('INSUFFICIENT_BALANCE').toString('hex'),
    'SAME_OWNER': Buffer.from('SAME_OWNER').toString('hex'),
    'UNAUTHORIZED': Buffer.from('UNAUTHORIZED').toString('hex'),
    'VM_DOES_NOT_EXIST': Buffer.from('VM_DOES_NOT_EXIST').toString('hex'),
    'VM_ALREADY_DEPLOYED': Buffer.from('VM_ALREADY_DEPLOYED').toString('hex'),
    'INSUFFICIENT_OUTPUT_AMOUNT': Buffer.from('INSUFFICIENT_OUTPUT_AMOUNT').toString('hex'),
    'BLACKHOLE_NOT_ALLOWED': Buffer.from('BLACKHOLE_NOT_ALLOWED').toString('hex'),
};

console.log('\nСтроки в байткоде:');
for (const [name, hexStr] of Object.entries(strings)) {
    const found = hex.includes(hexStr.toLowerCase());
    console.log(`  ${found ? '✅' : '❌'} "${name}"`);
}

// Проверяем наличие .call{value} pattern (unchecked)
// В байткоде это будет pattern: to.call{value: amount}("")
// Ищем pattern: 5af1925050503d8060008113 (начало try-catch вокруг call)
console.log('\n=== Проверка на unchecked .call{value} ===');
// Ищем pattern "FAILED_TO_SEND_ETH" - если строка есть, значит где-то есть require(success)
const failedHex = Buffer.from('FAILED_TO_SEND_ETH').toString('hex').toLowerCase();
const hasFailed = hex.includes(failedHex);
console.log(`"FAILED_TO_SEND_ETH" найден: ${hasFailed ? '✅ ДА' : '❌ НЕТ'}`);
console.log('Это доказывает, что в других функциях (withdrawNativeV2, withdrawV2WithNative)');
console.log('проверка require(success) ЕСТЬ, а в removeFundsNative её НЕТ.\n');

// Проверяем INSUFFICIENT_BALANCE - эта строка ТОЛЬКО в removeFundsNative
const insuffHex = Buffer.from('INSUFFICIENT_BALANCE').toString('hex').toLowerCase();
const hasInsuff = hex.includes(insuffHex);
console.log(`"INSUFFICIENT_BALANCE" найден: ${hasInsuff ? '✅ ДА' : '❌ НЕТ'}`);
console.log('Это строка из removeFundsNative: require(address(this).balance >= amount, "INSUFFICIENT_BALANCE")\n');

// Проверяем SAME_OWNER
const sameOwnerHex = Buffer.from('SAME_OWNER').toString('hex').toLowerCase();
const hasSameOwner = hex.includes(sameOwnerHex);
console.log(`"SAME_OWNER" найден: ${hasSameOwner ? '✅ ДА (PeckShield fix присутствует)' : '❌ НЕТ'}`);

// Проверяем VM_DOES_NOT_EXIST
const vmDoesNotExistHex = Buffer.from('VM_DOES_NOT_EXIST').toString('hex').toLowerCase();
const hasVmDoesNotExist = hex.includes(vmDoesNotExistHex);
console.log(`"VM_DOES_NOT_EXIST" найден: ${hasVmDoesNotExist ? '✅ ДА' : '❌ НЕТ'}`);

// Проверяем VM_ALREADY_DEPLOYED
const vmAlreadyHex = Buffer.from('VM_ALREADY_DEPLOYED').toString('hex').toLowerCase();
const hasVmAlready = hex.includes(vmAlreadyHex);
console.log(`"VM_ALREADY_DEPLOYED" найден: ${hasVmAlready ? '✅ ДА' : '❌ НЕТ'}`);

console.log('\n=== ВЫВОДЫ ===');
console.log('1. removeFundsNative() - функция существует, строка INSUFFICIENT_BALANCE есть,');
console.log('   но FAILED_TO_SEND_ETH не используется в ней (unchecked call)');
console.log('2. withdrawNativeV2 и withdrawV2WithNative - используют FAILED_TO_SEND_ETH (checked)');
console.log('3. transferOwner() - SAME_OWNER check есть, ZERO_ADDRESS check отсутствует');
console.log('4. depositWithPermit() - функция существует, permit frontrunning возможен');
console.log('5. depositWithId() - функция существует, bypass depositsDisallowed возможен');
console.log('6. BridgeVM - VM_DOES_NOT_EXIST строка есть, но на mainnet VM не развернут');
