# R6 Plan: fake token / voting power spoofing

## Гипотеза

Проверяем, можно ли:

1. подменить governance token contract
2. подать fake token с тем же интерфейсом
3. исказить voting power через неверный источник баланса
4. обойти snapshot / delegation / quorum logic

## Что должно быть у уязвимой системы

Для подтверждения `R6` обычно нужны признаки:

- известный governance token / jetton address
- voting contract, который читает balance / supply
- snapshot или live-balance logic
- delegation / vote accounting path

## Что проверяем в текущих артефактах

1. Есть ли признаки governance token
2. Есть ли признаки voting / snapshot / quorum logic
3. Есть ли contract addresses для DAO token / governance executor
4. Есть ли frontend/backend routes для governance voting

## Критерии подтверждения

`R6` подтверждается, если найдено хотя бы одно:

- voting power берётся из user-supplied token address
- fake token с тем же интерфейсом может быть принят как governance token
- snapshot/live voting power можно исказить без владения реальным governance asset

## Критерии опровержения

`R6` не подтверждается, если:

- governance token layer вообще не обнаружен
- в доступном наборе нет voting contracts / token addresses / snapshot logic
