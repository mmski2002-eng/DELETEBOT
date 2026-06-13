(async function () {
  const DELAY_ACTION = 900;
  const DELAY_AFTER_DELETE = 1800;
  const DELAY_NO_TWEETS = 3000;
  const MAX_EMPTY_ROWS = 5;

  let deleted = 0;
  let skipped = 0;
  let emptyStreak = 0;
  window._stopCleaner = false;

  const wait = ms => new Promise(r => setTimeout(r, ms));
  const click = el => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
  const pressEsc = () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
  const startURL = location.pathname;

  function log(msg) {
    console.log(`[Cleaner | del:${deleted} skip:${skipped}] ${msg}`);
  }

  async function undoRepost(article) {
    const btn = article.querySelector('[data-testid="unretweet"]');
    if (!btn) {
      log('Кнопка unretweet не найдена → пропускаю');
      return false;
    }
    click(btn);
    await wait(DELAY_ACTION);

    // Вариант 1: прямое подтверждение
    const confirm1 = document.querySelector('[data-testid="unretweetConfirm"]');
    if (confirm1) {
      click(confirm1);
      await wait(DELAY_ACTION);
      return true;
    }

    // Вариант 2: выпадающее меню с "Undo repost"
    const menu = document.querySelector('[role="menu"]');
    if (menu) {
      const undoBtn = [...menu.querySelectorAll('[role="menuitem"]')]
        .find(el => /undo repost|отменить репост/i.test(el.textContent));
      if (undoBtn) {
        click(undoBtn);
        await wait(DELAY_ACTION);
        return true;
      }
    }

    pressEsc();
    log('Не нашёл кнопку отмены репоста → пропускаю');
    return false;
  }

  async function deleteOwnTweet(article) {
    const caret = article.querySelector('[data-testid="caret"]');
    if (!caret) return false;

    click(caret);
    await wait(DELAY_ACTION);

    const menu = document.querySelector('[role="menu"]');
    if (!menu) {
      pressEsc();
      return false;
    }

    const deleteBtn = [...menu.querySelectorAll('[role="menuitem"]')]
      .find(el => /^удалить$|^delete$/i.test(el.textContent.trim()));
    if (!deleteBtn) {
      pressEsc();
      return false;
    }

    click(deleteBtn);
    await wait(DELAY_ACTION);

    const sheet = document.querySelector('[data-testid="confirmationSheetDialog"]');
    const confirmBtn = sheet?.querySelector('[data-testid="confirmationSheetConfirm"]');
    if (confirmBtn) {
      click(confirmBtn);
      await wait(DELAY_ACTION);
    }

    return true;
  }

  async function processOne() {
    if (location.pathname !== startURL) {
      log(`Страница изменилась (${location.pathname}) → стоп`);
      window._stopCleaner = true;
      return;
    }

    const articles = document.querySelectorAll('article[data-testid="tweet"]');
    if (!articles.length) {
      emptyStreak++;
      log(`Нет твитов (${emptyStreak}/${MAX_EMPTY_ROWS}) → скроллю...`);
      if (emptyStreak >= MAX_EMPTY_ROWS) {
        log('Твиты закончились → стоп. Обнови страницу и запусти снова.');
        window._stopCleaner = true;
        return;
      }
      window.scrollBy(0, 600);
      await wait(DELAY_NO_TWEETS);
      return;
    }

    emptyStreak = 0;
    const article = articles[0];

    // Репост: в шапке есть "reposted" / "репостнул" / socialContext
    const socialCtx = article.querySelector('[data-testid="socialContext"]');
    const isRepost = socialCtx && /repost|репост/i.test(socialCtx.textContent);

    let success;
    if (isRepost) {
      success = await undoRepost(article);
      if (success) {
        deleted++;
        log('Отменён репост');
      } else {
        article.scrollIntoView();
        window.scrollBy(0, article.offsetHeight + 50);
        skipped++;
      }
    } else {
      success = await deleteOwnTweet(article);
      if (success) {
        deleted++;
        log('Удалён твит');
      } else {
        log('Не свой твит или нет Delete → пропускаю');
        article.scrollIntoView();
        window.scrollBy(0, article.offsetHeight + 50);
        skipped++;
      }
    }

    await wait(success ? DELAY_AFTER_DELETE : 500);
  }

  log('Старт. Останови: window._stopCleaner = true');

  while (!window._stopCleaner) {
    try {
      await processOne();
    } catch (e) {
      log('Ошибка: ' + e.message);
      pressEsc();
      await wait(2000);
    }
  }

  log(`Завершено. Удалено: ${deleted}, пропущено: ${skipped}`);
})();
