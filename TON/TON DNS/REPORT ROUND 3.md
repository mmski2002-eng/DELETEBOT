Candidate 6 — rewrite_sender_address may create payer / bidder / entitlement mismatch
Status

Strong candidate. Needs sandbox + production payload review.

Это не “чистая кража” как historical Finding 1, а потенциальный identity-binding / attribution bug вокруг современных payload’ов, где ты уже видел:

force_sender_address + rewrite_sender_address
Суть

В NftCollectionNoDns restrictions обрабатываются так:

int has_force_sender_address = cs~load_uint(1);

if (has_force_sender_address) {
  slice force_sender_address = cs~load_msg_addr();
  throw_unless(err::invalid_sender_address, equal_slices(force_sender_address, sender_address));
}

int has_rewrite_sender_address = cs~load_uint(1);

if (has_rewrite_sender_address) {
  slice rewrite_sender_address = cs~load_msg_addr();
  sender_address = rewrite_sender_address;
}

То есть:

force_sender_address проверяет actual sender
rewrite_sender_address заменяет bidder identity

Дальше уже rewritten sender_address передаётся в item deploy:

cell deploy_msg = pack_teleitem_msg_deploy(sender_address, bid, token_info, content, auction_config, royalty);

Это подтверждается в nft-collection-no-dns.fc: sender restriction опционален, rewrite меняет sender_address, после чего именно этот адрес передаётся в pack_teleitem_msg_deploy как bidder.

Почему это интересно

Если backend выдаёт payload вида:

force_sender_address = wallet A
rewrite_sender_address = address B

то получается разделение ролей:

actual payer / authorized sender = A
recorded bidder / future owner / refund recipient = B

Это может быть intended feature, например custodial flow или Fragment/Telegram internal mapping. Но это очень опасная зона, потому что разные системы могут считать “владельцем” разные адреса:

on-chain bidder = B
wallet signer / payer = A
backend session user = Telegram account X
marketplace UI may attribute bid to A or B
refund goes to B
ownership_assigned goes to B
Potential impact

Если production backend, wallet flow или marketplace UI не учитывают rewrite-семантику строго, возможны:

1. Telegram/Fragment entitlement desync
2. refund-to-wrong-address
3. ownership assigned to address different from payer
4. user pays for asset that becomes owned by another address
5. signed payload reuse by same forced sender to assign bidder to attacker-controlled rewrite address
6. accounting mismatch in off-chain sale records

Ключевой risk: force_sender_address не означает “этот sender станет bidder/owner”. Он означает только “этот sender имеет право отправить payload”. После этого rewrite_sender_address может подменить bidder identity.

Severity estimate

Пока:

Medium candidate

Поднять до High, если подтвердится один из сценариев:

A pays, B becomes owner unexpectedly
refunds go to B while UI/backend expects A
Telegram entitlement binds to A while NFT ownership is B
payload with rewrite can be abused to redirect ownership

Invalid/low, если rewrite полностью intended, backend и UI везде используют rewritten address как canonical owner, а payer явно понимает это до подписи.

What to test in VS Code
Test 1 — Role split on first deploy

Создать signed deploy v2:

force_sender_address = A
rewrite_sender_address = B

Отправить body от A.

Expected observations:

collection accepts message
item is deployed
last_bidder == B
owner after instant/max_bid finalization == B
A paid msg_value
B receives ownership_assigned/refund paths

Если это так — не баг само по себе, но подтверждает опасную семантику.

Test 2 — UI/backend invariant test

Проверить в production payload’ах:

actual sender
force_sender_address
rewrite_sender_address
initial bidder in item state
owner after finalization

Собрать таблицу:

tx_hash | token | actual_sender | force_sender | rewrite_sender | item_bidder | owner

Alert conditions:

actual_sender != rewrite_sender
force_sender != rewrite_sender
item_bidder != actual_sender

Это может быть normal, но если UI/API показывают payer как buyer, появляется finding.

Test 3 — Can rewrite be malformed?

Проверить, проходит ли:

rewrite_sender_address = addr_none
rewrite_sender_address = non-std address
rewrite_sender_address = uninitialized std address
rewrite_sender_address = same as beneficiary
rewrite_sender_address = collection address
rewrite_sender_address = item address

В collection check_restrictions просто делает load_msg_addr() и присваивает sender_address; parse_std_addr в этом месте не видно. Дальше item может делать проверки позже, но нужно проверить sandbox.

Expected interesting result:

collection accepts rewrite to non-std/addr_none
item deploy fails silently or locks value

Если deploy message уходит с send_raw_message(..., 64) и item deploy возвращает null при invalid config, нужно проверить, куда девается value и как выглядит tx.

Candidate 7 — Silent value sink on invalid signed deploy / invalid auction config
Status

Candidate. Needs sandbox confirmation.

В NftCollectionNoDns.deploy_item collection проверяет только:

throw_unless(err::not_enough_funds, bid >= initial_min_bid);

а более глубокие проверки auction config происходят уже в item:

cell auction = prepare_auction(auction_config);
if (cell_null?(auction)) {
  return null();
}

prepare_auction возвращает null, если:

initial_min_bid < 2 * min_tons_for_storage
max_bid != 0 && max_bid < initial_min_bid
min_bid_step <= 0
min_extend_time > 7 days
duration > 365 days

Это видно в nft-item-no-dns.fc: prepare_auction не бросает ошибку, а возвращает null; deploy_item тоже прямо помечен комментарием “Do not throw errors here!” и возвращает null state.

Почему это интересно

Collection может принять signed payload и отправить deploy message с carry-all value:

send_raw_message(msg, 64);

Если item получает deploy, но prepare_auction возвращает null, надо проверить:

1. item остаётся uninitialized?
2. value остаётся на item address?
3. bidder получает refund?
4. collection возвращает excess?
5. можно ли повторить deploy?
6. можно ли intentionally подписать payload, который burns/locks user funds?

Такой payload должен быть signed backend’ом, поэтому это не permissionless attack. Но если backend может ошибиться или если historical payload был malformed, это может быть fund-loss footgun.

Potential impact
user signs valid backend payload
collection accepts
funds forwarded to item
item refuses initialization by returning null
value may become stuck at undeployed/uninitialized item address

Severity:

Medium if funds can be locked/burned
Low if transaction bounces/refunds cleanly
Invalid if impossible with signed production payloads
VS Code test

Сгенерировать signed deploy с:

initial_min_bid = 1 TON
min_bid_step = 0
duration > 365 days
min_extend_time > 7 days
max_bid < initial_min_bid

Отправить в collection с msg_value >= initial_min_bid.

Assert:

collection tx success?
item account created?
item state initialized?
where did value end up?
can same token be deployed again?
does sender receive refund?

Особенно интересен случай:

collection-level bid >= initial_min_bid
but item-level prepare_auction returns null

Потому что collection и item делают разные уровни валидации.

Candidate 8 — valid_since / valid_till strict-boundary mismatch
Status

Minor but easy to test.

В unwrap_signed_cmd проверка времени:

throw_unless(err::not_yet_valid_signature, valid_since < ts);
throw_unless(err::expired_signature, ts < valid_till);

То есть payload валиден только если:

valid_since < now < valid_till

Не валиден при:

now == valid_since
now == valid_till

Это видно в nft-collection-no-dns.fc around unwrap logic.

Почему это может иметь значение

Это не выглядит как high-severity vulnerability, но может дать:

off-chain/on-chain mismatch, если backend/UI считает interval inclusive;
failed purchases exactly at boundary;
grief/failure for users with short validity window;
edge around timestamp granularity.
Test
now = valid_since
now = valid_since + 1
now = valid_till - 1
now = valid_till

Expected:

valid_since exact boundary fails
valid_till exact boundary fails

Report only if UI/backend signs very short windows or tells users payload is valid inclusively.

Candidate 9 — DNS governance stale decision / decision applies to new owner
Status

Research candidate. Worth testing if DNS governance config entries are observable.

В DNS item governance path:

config = config_param(dns_config_id)
config.udict_get?(256, index)
config_op = config_value~load_uint(8)

if config_op == 0:
  transfer_ownership(... config_value ...)
if config_op == 1:
  send_msg(collection_address, 0, op::fill_up, ..., 128 + 32)

Любой может вызвать process_governance_decision, если config entry exists; sender не является authority, authority — masterchain config. Код требует только auction == null, находит config by index, затем применяет transfer или destroy.

Интересный сценарий

Не “может ли любой governance” — это intended. Интереснее другое:

governance decision created for old owner / old context
domain transfers normally before decision is executed
anyone later executes stale config decision
decision applies to current owner / current domain state

Нужно проверить, содержит ли config entry:

expected current owner;
timestamp/expiry;
target state;
replay guard;
enough context to prevent stale execution.

По текущему видимому коду item просто берёт config_value и передаёт его в transfer_ownership; если config payload — обычный transfer body без expected-owner guard, stale decision может примениться после legitimate transfer.

Impact
governance-approved transfer/destroy may affect a later innocent owner

Severity зависит от governance policy:

если governance decisions are immediate and config removed quickly — Low/Informational;
если entry can persist — Medium/High для DNS ownership safety.
VS Code / chain test
Найти/сконструировать config entry для domain index.
До исполнения transfer domain от owner A к owner B.
Вызвать process_governance_decision.
Проверить, применяется ли решение к B.

Expected concerning result:

stale governance entry transfers/destroys domain after ownership changed
Что из этого сейчас самое перспективное

Приоритет после текущего прохода:

P1 — rewrite_sender_address role split / entitlement mismatch
P1 — cross-collection replay, если найдёшь same public_key + subwallet_id
P2 — invalid auction_config value sink
P2 — historical/current scan of deploy payload restrictions
P3 — DNS governance stale decision
P4 — valid_since/valid_till boundary mismatch

Самый “живой” следующий тест: взять несколько современных production payload’ов с force_sender_address + rewrite_sender_address и построить таблицу actual sender vs forced sender vs rewritten sender vs item owner. Если где-то пользователь-плательщик отличается от on-chain owner без явной off-chain причины, это может стать хорошим report.