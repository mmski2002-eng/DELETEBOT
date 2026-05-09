# R4 Plan: timelock bypass

## Гипотеза

Проверяем, можно ли обойти timelock / delay / queued execution:

1. исполнить действие раньше положенной задержки
2. обойти timelock через emergency/admin path
3. исполнить чувствительный action напрямую, минуя governance delay

## Что должно быть у уязвимой системы

Для подтверждения `R4` обычно нужны признаки:

- отдельный timelock contract
- queue / eta / delay / execute_after state
- admin / emergency / guardian path
- различие между regular execute и fast-path execute

## Что проверяем в текущем DAOLama attack surface

1. Есть ли признаки timelock-слоя в repo artifacts
2. Есть ли live evidence delayed governance execution
3. Есть ли wallet/admin-like входы в `vault`
4. Есть ли bypass path к чувствительным операциям без delay
5. Есть ли в observed tx history admin/emergency-style opcodes

## Критерии подтверждения

`R4` подтверждается, если найдено хотя бы одно:

- чувствительный execute проходит без required delay
- emergency/admin path позволяет обойти timelock
- тот же action исполняется напрямую и через delayed path

## Критерии опровержения

`R4` не подтверждается, если:

- timelock-layer вообще не найден в доступных контрактах/адресах
- чувствительные пути observed только как internal protocol flows
- нет evidence governance delay, который можно было бы bypass'нуть
