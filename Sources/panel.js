(() => {
  "use strict";

  let currentState = null;
  let lastHeight = 0;

  const escapeHTML = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[char]));

  const pad2 = (value) => String(value).padStart(2, "0");

  const post = (action, extra = {}) => {
    try {
      if (window.webkit?.messageHandlers?.panel) {
        window.webkit.messageHandlers.panel.postMessage({ action, ...extra });
      }
    } catch (_) {
      // The file also opens in a plain browser for quick design checks.
    }
  };

  const quoteMarkup = (quote) => escapeHTML(quote).replace(/\n/g, "<br>");

  const modelBadge = (state) => `
    <button class="model-badge ${state.modelConfigured ? "" : "unconfigured"}"
            type="button" data-action="open-models"
            title="${state.modelConfigured ? "点击切换模型" : "点击配置 API Key"}">
      <span class="model-mark">AI</span>${escapeHTML(state.modelName || "未配置模型")}
    </button>`;

  const dotsMarkup = (state) => {
    const count = Math.max(0, Math.min(state.quoteCount, 6));
    if (!count) return "";
    const active = ((state.quoteIndex % count) + count) % count;
    return Array.from({ length: count }, (_, index) =>
      `<i class="dot ${index === active ? "active" : ""}"></i>`).join("");
  };

  const calendarMarkup = (state) => {
    const { year, month, today, likedDays } = state.calendar;
    const liked = new Set(likedDays || []);
    const weekdays = ["一", "二", "三", "四", "五", "六", "日"];
    const first = new Date(year, month - 1, 1);
    const startOffset = (first.getDay() + 6) % 7;
    const daysInMonth = new Date(year, month, 0).getDate();
    const daysInPreviousMonth = new Date(year, month - 1, 0).getDate();
    const cells = [];

    for (let index = startOffset - 1; index >= 0; index -= 1) {
      cells.push({ day: daysInPreviousMonth - index, outside: true });
    }
    for (let day = 1; day <= daysInMonth; day += 1) {
      cells.push({ day, outside: false });
    }
    let nextDay = 1;
    while (cells.length < 42) {
      cells.push({ day: nextDay, outside: true });
      nextDay += 1;
    }

    return weekdays.map((day) => `<span class="weekday">${day}</span>`).join("")
      + cells.map((cell) => {
        const isLiked = !cell.outside && liked.has(cell.day);
        const isToday = !cell.outside && cell.day === today;
        const isFuture = !cell.outside && cell.day > today;
        const classes = [
          "cal-cell",
          cell.outside ? "outside" : "",
          isLiked ? "liked" : "",
          isToday ? "today" : "",
          isFuture ? "future" : "",
        ].filter(Boolean).join(" ");
        return `<span class="${classes}"><span class="cal-num">${cell.day}</span></span>`;
      }).join("");
  };

  const ctaMarkup = (state, compact = false) => {
    const done = state.likedToday;
    const label = done ? "今日已应援" : "点赞应援";
    const sub = done
      ? `明天再来 · 连续 ${state.streak} 天`
      : "每日 1 次 · 今日未应援";
    return `
      <button class="cta ${compact ? "compact" : ""} ${done ? "done" : ""}"
              type="button" data-action="like" ${done ? "disabled" : ""}>
        <span class="cta-copy">
          <span class="label">${label}</span>
          <span class="sub">${sub}</span>
        </span>
        <span class="plus">${done ? "✓" : "+1"}</span>
      </button>`;
  };

  const predictionRows = (state) => {
    if (!state.predictions.length) {
      return `<div class="empty-row">配置模型后生成比分预测；当前为示例数据。</div>`;
    }
    return state.predictions.map((prediction) => {
      const lost = prediction.igScore < prediction.opponentScore;
      const bo = prediction.bestOf
        ? `<span class="bo-pill">BO${escapeHTML(String(prediction.bestOf))}</span>`
        : "";
      return `
        <div class="pred-row">
          <div class="pred-main">
            <div class="pred-teams">
              <span class="ig">IG</span>
              <span class="versus">vs</span>
              <span class="winner">${escapeHTML(prediction.opponent)}</span>
            </div>
            <div class="pred-meta">${bo}${escapeHTML(prediction.stage)} · ${escapeHTML(prediction.dateText)}</div>
          </div>
          <div class="pred-result">
            <span class="pred-score">${prediction.igScore} : ${prediction.opponentScore}</span>
            <span class="pred-prob ${lost ? "loss" : ""}">${prediction.confidence}%</span>
          </div>
        </div>`;
    }).join("");
  };

  const predictionFoot = (state) => {
    const note = state.predictionSample
      ? `示例预测 · 点击刷新后生成 · ${escapeHTML(state.modelID || "sample")}`
      : `模型 ${escapeHTML(state.modelID || state.modelName)} · 预测仅供参考`;
    return `<span class="pred-note">${note}</span><button class="pred-refresh" type="button" data-action="refresh-prediction">刷新预测</button>`;
  };

  const fixtureRows = (state) => {
    if (!state.schedule.length) {
      return `<div class="empty-row">官网暂无 IG 赛程 · 右键「刷新赛程」。</div>`;
    }
    return state.schedule.map((fixture) => {
      const result = fixture.scoreText
        ? `<span class="result-pill">${escapeHTML(fixture.scoreText)}</span>`
        : fixture.next
          ? `<span class="next-pill">下一场</span>`
          : "";
      return `
        <div class="fixture ${fixture.next ? "next" : ""} ${fixture.completed ? "completed" : ""}">
          <div class="fixture-date">
            <b>${escapeHTML(fixture.dateText)}</b>
            <span>${escapeHTML(fixture.weekday)}</span>
          </div>
          <div class="fixture-main">
            <div class="fixture-teams">IG <em>vs</em> ${escapeHTML(fixture.opponent)}</div>
            <div class="fixture-meta">${escapeHTML(fixture.timeText)} · ${escapeHTML(fixture.stage)} · BO${fixture.bestOf}</div>
          </div>
          ${result}
        </div>`;
    }).join("");
  };

  const scheduleFootnote = (state) => state.scheduleSample
    ? "赛程示例 · 右键「刷新赛程」拉取官网"
    : "赛程源 lolesports.com · 无需 Token";

  const verticalMarkup = (state) => `
    <header class="identity">
      <div class="avatar">
        <img src="avatar_bust_white.png" alt="灰阶僵尸半身">
        <span class="avatar-dot"></span>
      </div>
      <div class="identity-copy">
        <div class="kicker">THE SHY · 应援模式</div>
        <h1>IG 加油，<br>冲冲冲！</h1>
        <div class="status">
          <span class="live-dot"></span>
          <span>应援中</span>
          <span class="slash">/</span>
          <span class="brand">INVICTUS GAMING</span>
        </div>
      </div>
    </header>

    <div class="rule"></div>

    <section class="quote-section">
      <div class="quote-head">
        <span class="quote-label">今日金句</span>
        <span>${pad2(state.quoteIndex + 1)} / ${pad2(state.quoteCount)}</span>
      </div>
      <div class="quote-text">${quoteMarkup(state.quote)}</div>
      <div class="quote-foot">
        <div class="dots">${dotsMarkup(state)}</div>
        <span class="next-quote" data-action="next-quote">换一句 ↻</span>
      </div>
    </section>

    ${ctaMarkup(state)}

    <section class="block">
      <div class="cal-card">
        <div class="cal-head">
          <div>
            <div class="cal-title">应援日历</div>
            <div class="cal-month">${state.calendar.year} 年 ${state.calendar.month} 月</div>
          </div>
          <div class="streak"><b>${state.streak}</b><span>天连续</span></div>
        </div>
        <div class="cal-grid">${calendarMarkup(state)}</div>
        <div class="legend">
          <div class="legend-group">
            <span><i class="legend-dot"></i>已应援</span>
            <span><i class="legend-dot outline"></i>今日待应援</span>
          </div>
          <span class="legend-note">每日 1 次</span>
        </div>
      </div>
    </section>

    <section class="block">
      <div class="section-head">
        <div>
          <div class="eyebrow">S16 英雄联盟全球总决赛</div>
          <div class="section-title">我的预测</div>
        </div>
        ${modelBadge(state)}
      </div>
      <div class="pred-list">${predictionRows(state)}</div>
      <div class="pred-foot">${predictionFoot(state)}</div>
    </section>

    <section class="block">
      <div class="section-head">
        <div>
          <div class="eyebrow">S16 · 赛程</div>
          <div class="section-title">IG 接下来</div>
        </div>
        <span class="sync"><i class="sync-dot"></i>${state.scheduleSample ? "示例" : "官网同步"}</span>
      </div>
      <div class="schedule-list">${fixtureRows(state)}</div>
    </section>

    <footer class="footer">
      <span>${scheduleFootnote(state)}</span>
      <span class="footer-right">${escapeHTML(state.scheduleUpdated)}</span>
    </footer>`;

  const horizontalMarkup = (state) => `
    <div class="top">
      <div class="top-left">
        <div class="avatar">
          <img src="avatar_bust_white.png" alt="灰阶僵尸半身">
          <span class="avatar-dot"></span>
        </div>
        <div class="identity-copy">
          <div class="kicker">THE SHY · 应援模式</div>
          <h1>IG 加油，冲冲冲！</h1>
          <div class="status">
            <span class="live-dot"></span>
            <span>应援中</span>
            <span class="slash">/</span>
            <span class="brand">INVICTUS GAMING</span>
          </div>
        </div>
      </div>
      <div class="daily-box">
        ${ctaMarkup(state, true)}
        <div class="streak-line">
          <span><b>${state.streak}</b> 天连续</span>
          <span class="today-state">${state.likedToday ? "今天已完成" : "今天还可应援 1 次"}</span>
        </div>
      </div>
    </div>

    <div class="quote-strip">
      <span class="quote-label">今日金句</span>
      <span class="q">${escapeHTML(state.quote).replace(/\n/g, " ")}</span>
      <span class="next-quote" data-action="next-quote">换一句 ↻</span>
    </div>

    <div class="dashboard ${state.predictions.length < 2 ? "compact-dashboard" : ""}">
      <section class="dash-card calendar-card">
        <div class="section-head">
          <div>
            <div class="eyebrow">DAILY CHEER</div>
            <div class="section-title">应援日历</div>
          </div>
          <div class="streak"><b>${state.streak}</b><span>天连续</span></div>
        </div>
        <div class="cal-card">
          <div class="cal-head">
            <div>
              <div class="cal-title">${state.calendar.year} 年 ${state.calendar.month} 月</div>
              <div class="cal-month">每天只能点赞一次</div>
            </div>
          </div>
          <div class="cal-grid">${calendarMarkup(state)}</div>
          <div class="legend">
            <div class="legend-group">
              <span><i class="legend-dot"></i>已应援</span>
              <span><i class="legend-dot outline"></i>今日待应援</span>
            </div>
          </div>
        </div>
      </section>

      <section class="dash-card prediction-card">
        <div class="section-head">
          <div>
            <div class="eyebrow">S16 全球总决赛</div>
            <div class="section-title">我的预测</div>
          </div>
        </div>
        ${modelBadge(state)}
        <div class="pred-list">${predictionRows(state)}</div>
        <div class="pred-foot">${predictionFoot(state)}</div>
      </section>

      <section class="dash-card schedule-card">
        <div class="section-head">
          <div>
            <div class="eyebrow">S16 · 赛程</div>
            <div class="section-title">IG 接下来</div>
          </div>
          <span class="sync"><i class="sync-dot"></i>${state.scheduleSample ? "示例" : "官网同步"}</span>
        </div>
        <div class="schedule-list">${fixtureRows(state)}</div>
      </section>
    </div>

    <footer class="footer">
      <span>${scheduleFootnote(state)}</span>
      <span class="footer-right">${escapeHTML(state.scheduleUpdated)}</span>
    </footer>`;

  const render = (state) => {
    currentState = state;
    document.body.dataset.mode = state.mode;
    const panel = document.getElementById("panel");
    panel.className = state.mode === "horizontal"
      ? `panel v2 ${state.predictions.length < 2 ? "compact" : ""}`
      : "panel";
    panel.innerHTML = state.mode === "horizontal"
      ? horizontalMarkup(state)
      : verticalMarkup(state);

    const toast = document.getElementById("toast");
    if (state.toast) {
      toast.textContent = state.toast;
      toast.classList.add("show");
    } else {
      toast.classList.remove("show");
      toast.textContent = "";
    }

    window.setTimeout(notifyHeight, 40);
    if (document.fonts?.ready) {
      document.fonts.ready.then(() => window.setTimeout(notifyHeight, 10));
    }
  };

  const notifyHeight = () => {
    const panel = document.getElementById("panel");
    if (!panel) return;
    const height = Math.ceil(panel.getBoundingClientRect().height + 40);
    if (height > 0 && Math.abs(height - lastHeight) > 1) {
      lastHeight = height;
      post("resize", { height });
    }
  };

  document.addEventListener("click", (event) => {
    const actionEl = event.target.closest("[data-action]");
    if (actionEl) {
      event.preventDefault();
      if (actionEl.disabled) return;
      const action = actionEl.dataset.action;
      if (action === "like") post("like");
      else if (action === "next-quote") post("nextQuote");
      else if (action === "open-models") post("openModels");
      else if (action === "refresh-prediction") post("refreshPrediction");
      return;
    }
    if (!event.target.closest("#panel")) post("dismiss");
  });

  window.renderPanel = render;
  window.setTail = (x) => {
    document.documentElement.style.setProperty("--tail-x", `${Math.round(x)}px`);
  };
  window.addEventListener("load", () => {
    if (currentState) render(currentState);
  });
})();
