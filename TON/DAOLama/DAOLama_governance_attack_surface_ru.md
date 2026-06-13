# DAOLama Governance / Treasury / TMA Attack Surface Review

Дата: 2026-05-06

Статус анализа: частично подтвержденный review по предоставленным артефактам + приоритизированный checklist для responsible disclosure.

## 1. Executive Summary

В предоставленной папке **не найден исходный код governance-контрактов FunC/Tact**, timelock-модуля, treasury execution logic или backend-кода TMA. По факту рабочая папка содержит:

- production frontend DAOLama Lending/TMA;
- `app_config.json` с `apiBaseUrl = https://api.daolama.co`, `appBaseUrl = https://app.daolama.co`, `poolAddress = EQCkeTvOSTBwBtP06X2BX7THj_dlX67PhgYRGuKfjWtB9FVb`;
- клиентские обращения к API:
  - `/api/v1/analytics`
  - `/api/v1/nft-private-auctions`
  - `/api/v1/nft-pawn-rates/collections`
  - `/api/v1/nft-pawns/latest`
  - `/api/v1/nft-rent-fees/collections`
- чтение on-chain pool/vault данных через `@ton/core` и Ton RPC;
- явные Telegram/TMA theme hooks в HTML/CSS (`--tg-theme-*`), но **без подтвержденного client-side кода валидации `initData`** в предоставленных артефактах.

Ключевой вывод: текущий набор файлов больше похож на **DAOLama Lending frontend**, а не на исходники DAO governance. Поэтому ниже я разделяю:

1. `Подтверждено по артефактам`
2. `Высокоприоритетные проверки для governance/treasury, которые нельзя честно закрыть без исходников`

Если цель disclosure именно по DAO governance на TON, у команды в первую очередь нужно запросить:

- FunC/Tact source всех governance / timelock / treasury / token-voting контрактов;
- адреса production governance contracts;
- ABI/opcodes/message schema;
- backend-код Telegram auth / session binding;
- список admin / multisig / emergency ролей;
- deployment scripts и state init derivation logic.

## 2. Что подтверждено по текущему репозиторию

### 2.1. Репозиторий не содержит governance source

По текущей файловой структуре нет:

- `.fc`, `.func`, `.tact`, `.tolk`;
- backend source;
- тестов governance/timelock;
- скриптов deploy/upgrade governance.

Следствие: все проверки ранга `кража treasury` или `компрометация голосования` пока не могут быть закрыты доказательно.

### 2.2. Репозиторий содержит frontend для lending / auctions / rent

Подтвержденные клиентские точки:

- `app_config.json`: production API и app URLs;
- `486.f8176bf9e8a5b829.js`: analytics + чтение pool contract;
- `237.0e77cf5b50cd70cf.js`: private auctions;
- `367.938215b225074aa7.js`: collections / pawn rates / rent fees;
- `borrow.chunk.js`, `272.c2a8e79b860c1f3e.js`: borrow/rent UX.

### 2.3. Признаки TMA есть, но auth-flow не подтвержден

Есть:

- Telegram theme CSS variables в `index_daolama.html`;
- CTA на `https://t.me/daolama_bot`;
- mobile/TMA-oriented UI.

Не подтверждено:

- backend verification `initData`;
- binding Telegram user to wallet;
- anti-spoofing по `user.id`;
- session issuance logic;
- API authz middleware.

Это означает, что раздел TMA/API ниже критичен, но пока остается checklist, а не доказанной уязвимостью.

## 3. Наиболее вероятные и критичные векторы

Ниже перечислены вектора в порядке приоритета для DAO на TON, если у DAOLama действительно есть governance + treasury execution.

### P1. Несанкционированный treasury execution / withdrawal

Severity: `Critical`

Сценарий атаки:

1. Атакующий находит функцию `execute_proposal`, `withdraw`, `send_treasury`, `execute_action`.
2. Проверяет, что контракт доверяет произвольному `sender`, внешнему сообщению или payload без жесткой проверки proposal state.
3. Формирует сообщение, которое минует нормальный governance flow.
4. Treasury отправляет TON/jettons/NFT атакующему или на подставной контракт.

Что проверить в коде:

- `recv_internal` / `recv_external` всех treasury и executor контрактов;
- сравнение `sender()` с `governance`, `timelock`, `multisig`;
- проверку state proposal: `Queued -> Executable -> Executed`;
- проверку `proposal_id`, `eta`, `operation hash`, `executed`;
- запрет прямого вызова bypass-функций.

Уязвимая реализация:

```func
if (op == op_execute) {
  send_raw_message(payload, 64);
}
```

Безопасная реализация:

```func
throw_unless(ERR_NOT_GOVERNANCE, equal_slices(sender_address, governance));
throw_unless(ERR_BAD_STATE, proposal.executed == 0);
throw_unless(ERR_TOO_EARLY, now() >= proposal.eta);
throw_unless(ERR_HASH_MISMATCH, calc_op_hash(payload) == proposal.payload_hash);
proposal.executed = 1;
send_raw_message(payload, SAFE_MODE);
```

### P2. Подмена execution payload между approve и execute

Severity: `Critical`

Сценарий атаки:

1. Proposal проходит голосование с benign payload.
2. Между `queue` и `execute` атакующий или привилегированная роль меняет целевой адрес, сумму, opcode или cell payload.
3. Сообщество видит один proposal ID, а treasury исполняет другой payload.
4. Происходит кража средств или upgrade на вредоносный код.

Что проверить:

- хранится ли в proposal именно `hash(cell payload)` или полный cell/ref;
- что именно подписывается/голосуется: human-readable text или реальный payload hash;
- есть ли повторный `recompute hash` перед execute;
- меняемы ли `target`, `value`, `body`, `state_init`, `send_mode` после approval.

Уязвимая реализация:

- proposal хранит только `proposal_id` и text description;
- actual payload берется из входящего `execute` message.

Безопасная реализация:

- при создании proposal сохраняются:
  - `target`
  - `value`
  - `body_hash`
  - `state_init_hash`
  - `send_mode`
  - `eta`
- при execute все поля сверяются byte-to-byte или по hash.

### P3. Replay исполненного proposal

Severity: `Critical`

Сценарий атаки:

1. Proposal исполняется один раз и переводит средства.
2. Флаг `executed` не выставляется до внешней отправки или не сохраняется вовсе.
3. Атакующий повторяет то же сообщение.
4. Treasury повторно отправляет средства.

Что проверить:

- `executed` / `consumed` / `status` flag;
- порядок `state update` относительно `send_raw_message`;
- наличие anti-replay по `proposal_id`, `query_id`, `op_hash`;
- поведение после bounced execution.

Уязвимая реализация:

```func
send_raw_message(msg, mode);
proposal.executed = 1;
```

Безопасная реализация:

```func
throw_unless(ERR_ALREADY_EXECUTED, proposal.executed == 0);
proposal.executed = 1;
save_data(...);
send_raw_message(msg, mode);
```

### P4. Bypass timelock / emergency bypass

Severity: `Critical` или `High`

Сценарий атаки:

1. Governance предполагает timelock для всех treasury действий.
2. В контракте остается emergency/admin path без такого же delay.
3. Компрометация admin key или злая инсайдерская роль позволяет выполнить тот же action мгновенно.
4. Treasury выводится до реакции сообщества.

Что проверить:

- `emergency_execute`, `admin_execute`, `force_upgrade`, `owner_withdraw`;
- различия между обычным и emergency paths;
- возможность обновить timelock address / delay самим admin без timelock.

Уязвимая реализация:

- admin может менять `governance`, `treasury`, `implementation`, `delay` без задержки.

Безопасная реализация:

- все чувствительные изменения идут только через тот же timelock;
- emergency роль ограничена pause-only;
- нет emergency withdraw без отдельного stronger multisig + public delay.

### P5. Sender spoofing в межконтрактных вызовах TON

Severity: `Critical`

Сценарий атаки:

1. Executor, treasury или voting contract принимает внутреннее сообщение и проверяет только opcode.
2. Атакующий деплоит контракт с тем же интерфейсом.
3. Отправляет корректный body от ложного контракта.
4. Целевой контракт исполняет привилегированную ветку, думая, что caller легитимен.

Что проверить:

- все privileged `recv_internal`;
- проверку `sender_address` на exact address;
- derivation trusted addresses из `StateInit` / known config;
- отсутствие доверия только к структуре message body.

Уязвимая реализация:

```func
if (op == OP_EXECUTE) {
  ;; trust body
}
```

Безопасная реализация:

```func
throw_unless(ERR_BAD_SENDER, equal_slices(sender_address, timelock));
throw_unless(ERR_BAD_OP, op == OP_EXECUTE);
```

### P6. Fake token contract / fake jetton master

Severity: `Critical`

Сценарий атаки:

1. Governance contract принимает данные о voting power из jetton wallet/master.
2. Проверка ограничивается интерфейсом, а не exact jetton master address.
3. Атакующий подставляет фальшивый master/wallet с произвольным supply/balance.
4. Получает искусственный voting power и проводит вредоносный proposal.

Что проверить:

- где хранится canonical token master;
- проверка derive wallet address from master + owner;
- не принимаются ли arbitrary balance proofs или уведомления.

Уязвимая реализация:

- любое сообщение `token_balance_of` / `jetton_notify` считается валидным.

Безопасная реализация:

- voting contract hardcodes token master;
- wallet address вычисляется детерминированно;
- сообщения принимаются только от derived wallet/master pair.

### P7. StateInit атака / подмена адреса при первом deploy

Severity: `High` или `Critical`

Сценарий атаки:

1. Proposal или factory ожидает, что новый executor/escrow/timelock появится по предсказуемому адресу.
2. Формула адреса не фиксирует весь `StateInit`, salt или owner fields.
3. Атакующий деплоит альтернативный контракт на ожидаемый адрес или подменяет init-параметры.
4. Дальше governance взаимодействует с чужим кодом.

Что проверить:

- вычисление адресов через полный `StateInit`;
- сохранение и сверка `code_hash`;
- кто контролирует deploy salt / init data;
- допускается ли external first-deploy race.

Уязвимая реализация:

- контракт доверяет адресу, присланному в message body.

Безопасная реализация:

- адрес вычисляется локально из canonical code+data;
- при первом сообщении сверяются `state_init_hash` / `code_hash`.

## 4. Полный checklist по requested vectors

Ниже каждый requested vector дан в формате:

- `Сценарий`
- `Что проверить`
- `Severity`
- `Уязвимо vs безопасно`

---

## 4.1. Governance контракты

### 4.1.1. Flash loan / snapshot voting manipulation

Severity: `High`

Сценарий:

1. Атакующий берет мгновенную ликвидность DAO token.
2. Переводит токены на адрес голосования.
3. Если voting power считается по real-time balance, голосует с временным балансом.
4. Возвращает ликвидность в той же или соседней транзакционной цепочке.

Что проверить:

- есть ли snapshot block/lt/time при proposal creation;
- откуда берется voting power: getter current balance или historical state;
- можно ли перевести токены после snapshot и сохранить power;
- есть ли lock/stake/escrow на период голосования.

Уязвимо:

- `votes = current_balance(voter)`

Безопасно:

- `votes = balance_at(snapshot_id)` или lock-based voting.

### 4.1.2. Proposal execution раньше timelock

Severity: `Critical`

Сценарий:

1. Proposal проходит `Succeeded`.
2. Атакующий вызывает `execute` до `eta`.
3. Из-за ошибки сравнения времени, пустого delay или другой ветки bypass предложение исполняется сразу.

Что проверить:

- `now() >= eta`;
- `delay > 0`;
- единицы времени: seconds vs milliseconds;
- может ли `eta` быть 0;
- одинаково ли проверяются обычные и batched proposal.

Уязвимо:

- `if (now() > eta)` при `eta == now`;
- `eta` не записывается в queue-step.

Безопасно:

- явный lifecycle `Created -> Active -> Succeeded -> Queued -> Executable -> Executed`.

### 4.1.3. Quorum manipulation через abstain / non-participation

Severity: `Medium` или `High`

Сценарий:

1. Крупный holder намеренно не голосует.
2. Если quorum считается только по `forVotes`, proposal удобнее завалить.
3. Если quorum считается странно, можно провести proposal малым активным меньшинством.

Что проверить:

- формулу quorum: `for`, `for+against`, `for+against+abstain`;
- считается ли abstain к participation threshold;
- что происходит при supply changes во время voting.

Уязвимо:

- неочевидная / документально несоответствующая formula.

Безопасно:

- четкая фиксированная formula и unit-tests на edge cases.

### 4.1.4. Double voting

Severity: `High`

Сценарий:

1. Атакующий голосует с адреса A.
2. Переводит токены на B или повторно вызывает vote для A.
3. При отсутствии `hasVoted` или snapshot-учета использует тот же power второй раз.

Что проверить:

- `has_voted[proposal_id][voter]`;
- снимок balance на момент snapshot, а не на момент vote;
- запрет revote без корректного netting;
- делегированный voting power не считается дважды.

Уязвимо:

- хранится только aggregate votes, без per-voter receipt.

Безопасно:

- receipt с `support`, `votes`, `has_voted`.

### 4.1.5. Proposal spam / dust proposals

Severity: `Medium`

Сценарий:

1. Атакующий создает много дешевых proposal.
2. Storage/gas/state growth мешают реальным governance действиям.
3. UI и indexers деградируют.

Что проверить:

- proposal threshold;
- creation fee / bond;
- rate limit per proposer;
- cancel/cleanup path.

Уязвимо:

- любой holder с dust balance может создавать proposal.

Безопасно:

- min threshold + refundable bond + active proposal limit.

---

## 4.2. Treasury

### 4.2.1. Кто имеет право вызвать withdrawal

Severity: `Critical`

Сценарий:

1. Любой internal sender или owner-like role вызывает withdraw path.
2. Treasury не различает governance executor и обычного пользователя.
3. Средства уходят атакующему.

Что проверить:

- exact allowlist senders;
- есть ли `recv_external` на treasury;
- нет ли leftover owner/admin path.

Уязвимо:

- `if (op == withdraw) send(...)`

Безопасно:

- strict sender check + proposal hash/state validation.

### 4.2.2. Payload не подменен между approve и execute

Severity: `Critical`

Сценарий и проверки: см. `P2`.

### 4.2.3. Replay attack повторного использования proposal

Severity: `Critical`

Сценарий и проверки: см. `P3`.

### 4.2.4. Reentrancy-подобные паттерны в асинхронной модели TON

Severity: `High`

Сценарий:

1. Treasury меняет состояние и отправляет внешние/internal сообщения.
2. Из-за bounce, callback или параллельной цепочки сообщений приходит повторный trigger.
3. Контракт снова проходит через ту же ветку в промежуточном состоянии.

Что проверить:

- все `recv_bounced`;
- state machine без промежуточных “полуисполненных” статусов;
- idempotency execution paths;
- отдельные flags `queued`, `executing`, `executed`, `failed`.

Уязвимо:

- контракт зависит от “успешности внешней отправки”, не фиксируя state заранее.

Безопасно:

- monotonic status transitions + explicit bounce recovery.

---

## 4.3. Token / voting power

### 4.3.1. Snapshot vs real-time power

Severity: `High`

Сценарий:

1. Voter покупает токены после открытия голосования.
2. Если power real-time, баланс можно накачивать точечно.
3. Можно голосовать не с тем весом, который ожидал governance.

Что проверить:

- `get_votes(account, proposal_id)` vs `balanceOf(account)`;
- сохраняется ли `snapshot_lt` / `snapshot_ts`.

Уязвимо:

- `votes = current wallet balance`.

Безопасно:

- immutable snapshot per proposal.

### 4.3.2. Circular delegation loop

Severity: `Medium` или `High`

Сценарий:

1. A делегирует B, B делегирует C, C делегирует A.
2. Алгоритм либо ломается, либо считает power бесконечно/двойно.

Что проверить:

- DFS/BFS cycle detection;
- max delegation depth;
- запрет self-delegation and loops.

Уязвимо:

- делегирование просто перезаписывает target без graph validation.

Безопасно:

- reject on cycle detection.

### 4.3.3. Манипуляция балансом между snapshot и vote

Severity: `High`

Сценарий:

1. Snapshot берется поздно или лениво при первом голосе.
2. Атакующий двигает баланс между несколькими адресами до фиксации.
3. Использует один и тот же economic power несколько раз.

Что проверить:

- когда именно фиксируется snapshot;
- нельзя ли “materialize snapshot on demand”.

Уязвимо:

- snapshot per voter at vote time.

Безопасно:

- global snapshot at proposal creation / voting start.

### 4.3.4. Fake token contract с тем же интерфейсом

Severity: `Critical`

Сценарий и проверки: см. `P6`.

---

## 4.4. Timelock и access control

### 4.4.1. Кто admin: один ключ или multisig

Severity: `High`

Сценарий:

1. Компрометация single admin key.
2. Мгновенный апгрейд contracts, смена governance address или вывод treasury.

Что проверить:

- хранится ли single owner address;
- multisig ли это, и какой threshold;
- может ли owner сменить owner без timelock.

Уязвимо:

- single EOA-style control over critical addresses.

Безопасно:

- multisig + timelock + role separation.

### 4.4.2. Bypass timelock через emergency функции

Severity: `Critical` или `High`

Сценарий и проверки: см. `P4`.

### 4.4.3. Асимметричные права: admin change vs upgrade vs execution

Severity: `High`

Сценарий:

1. Даже если withdraw защищен timelock, admin может без timelock сменить implementation или governance address.
2. После этого делает вредоносный execute уже легально.

Что проверить:

- отдельно права на:
  - `set_admin`
  - `set_governance`
  - `set_timelock`
  - `upgrade_code`
  - `withdraw`
  - `pause/unpause`

Уязвимо:

- одна роль имеет быстрый путь к критичным параметрам.

Безопасно:

- все эквивалентно опасные действия идут через одинаково строгий control plane.

---

## 4.5. TMA / frontend / API

### 4.5.1. Валидация `initData` на бэкенде

Severity: `Critical`

Сценарий:

1. Атакующий подделывает запросы к backend с фальшивым `user.id`, `username`, `auth_date`.
2. Если backend доверяет данным из frontend без HMAC-SHA256 verification по Telegram secret, он создает сессию.
3. Атакующий действует от имени чужого пользователя.

Что проверить:

- backend middleware verify Telegram WebApp `initData`;
- сортировка key-value, исключение `hash`, HMAC-SHA256 через bot token secret;
- проверка `auth_date` freshness;
- one-time session issuance, не прямое доверие frontend JSON.

Уязвимо:

- frontend сам парсит `initDataUnsafe`, backend принимает `user.id`.

Безопасно:

- backend сам верифицирует сырой `initData` и выдает session.

### 4.5.2. Голосование от чужого имени через spoofed `user.id`

Severity: `Critical`

Сценарий:

1. API принимает `telegramUserId` или `walletAddress` из client body.
2. Нет server-side binding между verified Telegram session и конкретным пользователем/кошельком.
3. Атакующий голосует за другого пользователя.

Что проверить:

- server-side session principal;
- wallet ownership proof;
- связка `telegram account <-> wallet`.

Уязвимо:

- `POST /vote { userId, proposalId, support }`

Безопасно:

- user identity берется только из verified session; wallet action требует proof/signature.

### 4.5.3. XSS через proposal title/description

Severity: `High`

Сценарий:

1. Атакующий создает proposal с HTML/JS payload в title/description.
2. Governance UI рендерит это через `innerHTML`.
3. Крадутся сессии, подменяются адреса, выполняются actions от имени модераторов/админов.

Что проверить:

- `innerHTML`, markdown renderer, sanitize config;
- server-side stored content policy;
- CSP.

Уязвимо:

- unsanitized HTML rendering of user-generated fields.

Безопасно:

- escape by default; allowlist sanitizer if markdown/HTML required.

### 4.5.4. API endpoints без авторизации

Severity: `High` или `Critical`

Сценарий:

1. Находятся privileged API:
  - create proposal
  - queue execute
  - withdraw
  - moderation
  - bind wallet
2. Эндпоинты доступны без authz или только с client-supplied IDs.
3. Атакующий вызывает их напрямую.

Что проверить:

- auth middleware на всех mutating endpoints;
- role checks;
- server-side ownership checks;
- rate limits and CSRF where applicable.

Уязвимо:

- frontend скрывает кнопку, backend не проверяет право.

Безопасно:

- backend is source of truth for authn + authz.

---

## 4.6. TON-специфичные векторы

### 4.6.1. Sender spoofing

Severity: `Critical`

Сценарий и проверки: см. `P5`.

### 4.6.2. Bounce message handling

Severity: `High`

Сценарий:

1. `execute` отправляет сообщение в target contract.
2. Target reject/bounce-ит транзакцию.
3. Treasury уже пометил proposal выполненным или потерял согласованность.
4. Возникает lost funds, stuck proposal или повторное исполнение.

Что проверить:

- `recv_bounced`;
- rollback vs terminal-failure semantics;
- учитывается ли bounce от upgrade / transfer / deploy.

Уязвимо:

- нет bounce handler;
- executed=1 до учета bounced failure без recovery path.

Безопасно:

- явный обработчик bounced messages и однозначная policy.

### 4.6.3. Асинхронный race между approve и execute

Severity: `High`

Сценарий:

1. Одновременно приходят queue/execute/cancel-like messages.
2. Из-за асинхронности состояния один path читает устаревший статус.
3. Proposal исполняется в неправильной фазе.

Что проверить:

- atomic state transition modeling;
- reject unexpected messages per status;
- monotonic nonce/version checks.

Уязвимо:

- логика зависит от off-chain sequencing assumptions.

Безопасно:

- контракт принимает только сообщения, допустимые для текущего status.

### 4.6.4. StateInit атака

Severity: `High` или `Critical`

Сценарий и проверки: см. `P7`.

## 5. Что смотреть в исходниках в первую очередь

Если команда даст source, начинать стоит с этих функций/модулей:

1. `recv_internal` и `recv_external` во всех governance/timelock/treasury контрактах.
2. Proposal lifecycle:
   - `create_proposal`
   - `vote`
   - `queue`
   - `execute`
   - `cancel`
3. Access control:
   - `set_admin`
   - `set_governance`
   - `set_timelock`
   - `upgrade`
   - `emergency_*`
4. Voting power:
   - snapshot logic
   - delegate logic
   - receipt storage
5. Message verification:
   - sender address checks
   - payload hash checks
   - replay guards
6. TON-specific:
   - `recv_bounced`
   - `send_mode`
   - `raw_reserve`
   - `StateInit` derivation

## 6. Быстрые признаки уязвимой реализации

Красные флаги:

- real-time balance вместо snapshot;
- execute берет payload из входящего сообщения, а не из сохраненного proposal;
- нет `executed` flag или он ставится после external send;
- emergency/admin path может делать то же, что governance, но без delay;
- privileged handler проверяет только opcode, а не exact sender;
- token/vote logic доверяет любому jetton-like interface;
- нет `recv_bounced`;
- нет per-voter receipt;
- любой holder с dust balance может спамить proposal;
- backend доверяет `user.id` или frontend-parsed Telegram data;
- UI рендерит proposal text через `innerHTML`.

## 7. Что уже можно сообщать команде сейчас

Даже без исходников уже корректно сообщить:

1. Предоставленный пакет артефактов не позволяет подтвердить безопасность governance / treasury paths.
2. В репозитории отсутствуют исходники контрактов и backend auth-flow, поэтому критичные инварианты остаются непроверяемыми.
3. Для DAO на TON наивысший риск несут:
   - unauthorized treasury execution
   - payload substitution
   - replay execution
   - timelock bypass
   - sender spoofing
   - fake token / vote power forgery
   - missing Telegram backend auth verification
4. Попросить у команды source/addresses/scripts для точечного подтверждения или опровержения этих векторов.

## 8. Рекомендуемый follow-up пакет от команды

- Исходники всех governance/timelock/treasury contracts;
- список прод-адресов;
- описание ролей и multisig threshold;
- message schema/opcodes;
- unit/integration tests на:
  - replay
  - bounce
  - timelock
  - double voting
  - delegation loops
  - fake token sender
- backend auth middleware для Telegram WebApp;
- API spec mutating endpoints.

## 9. Итог

На текущем наборе файлов **нет оснований утверждать, что governance и treasury DAOLama безопасны**, потому что критичные компоненты просто не представлены. Самые важные и вероятные вектора для disclosure я приоритизировал выше; если команда предоставит source, их можно быстро превратить из checklist в доказательные findings с конкретными строками кода и PoC.
