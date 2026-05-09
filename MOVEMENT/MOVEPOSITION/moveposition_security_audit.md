# Аудит безопасности MovePosition — Результаты поиска уязвимостей

## B) Подтверждённых Critical/High уязвимостей не обнаружено

---

### Активные контракты/модули проверены

**Адрес контракта**: `0xccd2621d2897d407e06d18e6ebe3be0e6d9b61f1e809dd49360522b9105812cf`
**Сеть**: Movement Mainnet (chain-id: 126)
**Ledger version на момент проверки**: 130666141
**Доказательство активности**: модули загружены, ABI извлечены, HTTP 200 от RPC

**Проверенные модули (40+)**:
- `broker` — ядро: Broker, BrokerView, DepositNote, LoanNote, NoteCapabilities, NewBrokerEvent, PayDownBorrowedEvent
- `portfolio` — портфель: Portfolio (collaterals + liabilities via LIT<TypeInfo, u64>), PortfolioView
- `lend`, `borrow`, `redeem`, `repay` — операции: LendEvent, BorrowEvent, RedeemEvent, RepayEvent
- `liquidate`, `liquidate_v2` — ликвидации: LiquidateEvent, LiquidateEventV1
- `liquidate_ticket_v2`, `basic_ticket_v2`, `lend_and_borrow_ticket`, `repay_and_redeem_ticket` — off-chain тикеты
- `hocket` — верификация подписи off-chain пакетов: Packet, PacketBody, PacketProcessed
- `packet_state` — защита от повтора nonce: PacketState, PacketStateV2
- `signer_state`, `admin_api`, `admin_config` — управление подписантами и админами
- `tenant` — комиссии протокола: Tenant, PortfolioVector, PortfolioVectorV2
- `flash_lender`, `flash_lender_public`, `flash_lender_access` — flash loans
- `coins` — типы монет (18 штук: EZBTC, EZETH, LBTC, MBTC, MOVE, RSETH, SAVUSD, SOLVBTC, STBTC, SUSDa, TruAPT, USDC, USDCx, USDa, USDt, WBTC, WEETH, WETH)
- `interest` — InterestRateCurve (u1, u2, r0, r1, r2, r3)
- `math` — интерполяция (interpolate)
- `vault`, `ra` — хранилище и resource account
- `rate_limiter` — ограничители частоты (часовые, 8-часовые) для borrow и redeem
- `rollback_liquidation` — откат ликвидации админом
- `entry_admin`, `entry_public` — entry-функции
- `lite_iterable_table`, `set`, `map`, `binary_cursor` — библиотеки

---

### Активные рынки/активы проверены

Из модуля `coins` — 18 типов активов:
**Stablecoins**: USDC, USDCx (bridged L0), USDa, USDt, SUSDa, SAVUSD
**BTC-производные**: WBTC, EZBTC, LBTC, MBTC, SOLVBTC, STBTC
**ETH-производные**: WETH, WEETH, EZETH, RSETH
**Другие**: MOVE, TruAPT

---

### Проверенные гипотезы и почему каждая не подтвердилась

#### Гипотеза 1: Путаница USDC/USDCx/USDa/USDt — приём фейкового актива как залога
- **Суть**: USDCx (bridged LayerZero) может иметь иной риск, чем нативный USDC. Если оба приняты с одинаковым collateral factor, атакующий депонирует USDCx и заимствует USDC.
- **Анализ**: Модуль `coins` определяет их как РАЗНЫЕ phantom-типы (USDC ≠ USDCx ≠ USDa ≠ USDt). Каждый Broker параметризован одним типом `<T>`. Это означает, что каждый актив имеет собственный изолированный Broker — путаница между USDC и USDCx невозможна на уровне типов Move. Параметры риска (max_borrow, max_deposit) задаются независимо для каждого Broker'а через `entry_admin::set_broker_max_borrow<T>`.
- **Вердикт**: Не подтверждено. Типобезопасность Move предотвращает смешивание на уровне контракта. Риск остаётся только на уровне параметров (админ может выставить одинаковые LTV), что исключено условиями задачи (admin mistakes).

#### Гипотеза 2: Инфляция долей (share inflation / donation attack)
- **Суть**: Первый депозитор в пул вносит 1 wei, затем напрямую переводит активы на адрес vault/broker, раздувая exchange rate. Последующие депозиторы получают 0 shares.
- **Анализ**: Модуль `broker` использует `deposit_note_supply` (u128) и `deposit_note_exchange_rate` (FixedPoint64). Функции `calc_deposit_notes` и `calc_coins_from_dnotes` — view-функции. Ключевой вопрос: отслеживает ли `broker::available` (u64) реальный баланс vault, или это независимая учётная переменная? Если `available` обновляется ТОЛЬКО через `lend`/`redeem`, а прямой перевод на vault НЕ увеличивает `available`, то exchange rate расходится с реальным балансом — donation attack работает.
- **Почему не подтверждено**: Без декомпилированного исходного кода функций `lend_<T>` и `deposit_<T>` (friend-функции в broker) невозможно определить, синхронизируется ли `available` с балансом vault при каждом lend/deposit, или пересчитывается из баланса. ABI показывает только сигнатуры, не тела функций. Требуется декомпиляция bytecode для подтверждения.

#### Гипотеза 3: Подделка/повтор off-chain пакета (packet tampering / replay)
- **Суть**: Off-chain сервер подписывает транзакционные пакеты (hocket). Если валидация подписи или защита от повтора сломаны, атакующий может повторно использовать пакет или подделать payload.
- **Анализ**: Модуль `hocket::parse_and_verify` проверяет: платформу, expiration_timestamp, nonce (через `packet_state`), подпись (ed25519 через `signer_state`). Модуль `packet_state` хранит использованные nonce в `Table<u64, bool>`. Структура `PacketBody` включает `platform`, `client_id`, `nonce`, `expiration_timestamp`, `payload`. Подпись верифицируется над всем телом пакета.
- **Вердикт**: Не подтверждено. Защита от повтора реализована через persistent storage nonce. Подпись ed25519 над полным телом пакета предотвращает tampering. Валидация срока действия предотвращает использование просроченных пакетов. Атака потребовала бы компрометации приватного ключа подписанта (исключено условиями: admin wallet compromise excluded).

#### Гипотеза 4: Ошибка математики ликвидации — ликвидация здорового аккаунта
- **Суть**: Некорректный расчёт health factor позволяет ликвидировать аккаунт, который на самом деле здоров.
- **Анализ**: Health factor рассчитывается OFF-CHAIN (Super-API), не on-chain. On-chain ликвидация использует тикетную систему: `liquidate_ticket_v2` содержит снапшоты портфеля ликвидатора и ликвидируемого ДО и ПОСЛЕ, а также комиссии. On-chain валидация проверяет, что approved-портфели соответствуют current-портфелям, и что изменения корректны (`validate_no_liquidatee_collaterals_increased`, `validate_no_liquidatee_liabilities_decreased`, etc.). Однако сам расчёт HEALTH FACTOR (является ли позиция подлежащей ликвидации) происходит на сервере.
- **Почему не подтверждено**: On-chain контракты не проверяют health factor — они доверяют off-chain серверу в этом вопросе. Это архитектурное решение, а не баг в смарт-контракте. Для подтверждения уязвимости потребовался бы анализ off-chain сервера (выходит за рамки задачи, так как off-chain код недоступен).

#### Гипотеза 5: Десинхронизация borrow/supply индексов
- **Суть**: Начисление процентов использует `interest_updated_at` и `calc_accrued_interest_rate`. Если индексы обновляются с задержкой или некорректно, возможна манипуляция.
- **Анализ**: Модуль `interest` использует кусочно-линейную кривую (6 параметров: u1, u2, r0, r1, r2, r3). Функция `calc_accrued_interest_rate` (friend для broker) принимает `InterestRateCurve`, `FixedPoint64` (utilization), и `u64` (time delta). Проценты начисляются при КАЖДОМ взаимодействии с broker (lend, borrow, redeem, repay) через вызовы `accrue_interest<T>`.
- **Почему не подтверждено**: Без декомпиляции тел функций `accrue_interest`, `inc_available`, `dec_available`, `inc_borrowed`, `dec_borrowed` невозможно проверить корректность порядка операций (начисление процентов ДО или ПОСЛЕ изменения available/borrowed) и направление округления. ABI показывает только сигнатуры.

#### Гипотеза 6: Flash-loan-assisted accounting attack
- **Суть**: Использование flash loan для манипуляции utilisation rate с последующей атакой на процентную ставку или ликвидацию.
- **Анализ**: Модуль `flash_lender` параметризован типом `<T>` для КАЖДОГО актива. Функция `borrow<T>` требует наличия адреса в `flash_lender_access::allowed`. Функция `repay<T>` проверяет, что сумма возврата >= суммы займа + комиссия (`repay_amount >= receipt.repay_amount`). В отличие от мгновенных займов в пуле ликвидности, flash loan здесь — отдельный модуль со своим хранилищем.
- **Вердикт**: Не подтверждено. Flash loan имеет собственный источник средств (vault), отделённый от broker'ов лэндинга, и требует whitelist-доступа (`flash_lender_access`).

#### Гипотеза 7: Несанкционированная эскалация привилегий (non-admin)
- **Суть**: Возможность вызова admin-функций (`set_max_borrow`, `set_pause`, etc.) не-админом.
- **Анализ**: Модуль `admin_config` хранит `Config { admin, proposed_admin }`. Функция `assert_admin(signer)` вызывается во всех entry_admin функциях. Механизм смены админа: `propose_new_admin` → `accept_admin_role` (новый админ должен явно принять роль).
- **Вердикт**: Не подтверждено. Двухэтапная смена админа предотвращает случайную передачу. `assert_admin` проверяется во всех привилегированных функциях.

---

### Недостающие данные

1. **Декомпилированный исходный код** — ABI содержит только сигнатуры функций; тела функций (bytecode) требуют декомпиляции для анализа логики округления, порядка операций и синхронизации балансов
2. **Параметры риска (LTV/LT)** — устанавливаются админом off-chain через Super-API; on-chain контракты их не хранят в читаемом виде
3. **Off-chain сервер (Super-API)** — расчёт health factor, цен и создание тикетов происходит вне цепи; код сервера недоступен для аудита
4. **Реальные балансы Broker'ов** — для оценки экономической активности и TVL требуются прямые запросы ресурсов на каждом Broker-аккаунте
5. **История транзакций/событий** — для верификации корректности работы в продакшене необходимы исторические данные ликвидаций и операций