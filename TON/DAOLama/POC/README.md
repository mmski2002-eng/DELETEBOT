# DAOLama POC Workspace

Эта папка предназначена для PoC по критичным векторам.

Статус:

- `R1_unauthorized_treasury_execution` - in progress
- `R2_payload_substitution` - pending
- `R3_replay_executed_proposal` - pending
- `R4_timelock_bypass` - pending
- `R5_sender_spoofing` - pending
- `R6_fake_token_voting_power` - pending
- `R7_tma_auth_spoofing` - pending

Ограничение текущего этапа:

- в рабочей папке нет исходников governance/timelock/treasury контрактов;
- нет backend source TMA;
- нет списка governance production addresses.

Поэтому на первом проходе каждый POC состоит из:

1. `TARGET_TEMPLATE.json` - какие данные нужно собрать
2. `POC_PLAN_ru.md` - сценарий проверки и критерии успеха
3. при необходимости `scripts/` - заготовки для ускорения воспроизведения

Как только появятся реальные адреса/исходники/opcodes, эти шаблоны превращаются в исполняемые PoC.
