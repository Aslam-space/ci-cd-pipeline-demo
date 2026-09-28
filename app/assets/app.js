'use strict';

(() => {
  const $ = (id) => document.getElementById(id);
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  $('year').textContent = new Date().getFullYear();

  /* ===== Build info: written into the image by the Dockerfile ===== */
  let buildInfo = { buildNumber: 'local', gitCommit: 'unknown', gitBranch: 'unknown', buildDate: 'unknown', buildUrl: '' };

  async function loadBuildInfo() {
    try {
      const res = await fetch('build-info.json', { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      buildInfo = { ...buildInfo, ...(await res.json()) };
    } catch (err) {
      console.warn('build-info.json unavailable, showing defaults:', err);
    }

    $('build-number').textContent = /^\d+$/.test(buildInfo.buildNumber) ? `#${buildInfo.buildNumber}` : buildInfo.buildNumber;
    $('git-commit').textContent = buildInfo.gitCommit;
    $('git-branch').textContent = buildInfo.gitBranch;

    const date = new Date(buildInfo.buildDate);
    $('build-date').textContent = Number.isNaN(date.getTime()) ? buildInfo.buildDate : date.toLocaleString();
    if (!Number.isNaN(date.getTime())) $('build-date').title = date.toISOString();

    if (/^https?:\/\//.test(buildInfo.buildUrl)) {
      $('build-link').href = buildInfo.buildUrl;
      $('build-link-wrap').hidden = false;
    }
  }

  /* ===== Live health check against the container's /healthz ===== */
  async function checkHealth() {
    const started = performance.now();
    let ok = false;
    try {
      const res = await fetch('healthz', { cache: 'no-store' });
      ok = res.ok;
    } catch { /* offline or container down */ }
    const ms = Math.round(performance.now() - started);

    $('health-dot').className = `status-dot ${ok ? 'ok' : 'fail'}`;
    $('health-text').textContent = ok ? 'healthy' : 'unreachable';
    $('health-latency').textContent = ok ? `${ms} ms` : '–';
  }

  /* ===== Pipeline replay: walks through the stages Jenkins ran for this build ===== */
  const stageLog = {
    checkout: () => `git checkout ${buildInfo.gitBranch} @ ${buildInfo.gitCommit}`,
    lint: () => 'hadolint Dockerfile … 0 issues\nshellcheck scripts/*.sh … 0 issues',
    build: () => `docker build -t ci-cd-demo:${buildInfo.buildNumber} .  (multi-stage, non-root)`,
    test: () => 'smoke-test: GET /healthz 200 · GET / 200 · security headers present',
    scan: () => 'trivy image … no fixable CRITICAL CVEs, gate passed',
    push: () => `docker push <account>.dkr.ecr.ap-south-1.amazonaws.com/ci-cd-demo-repo:${buildInfo.buildNumber}`,
    deploy: () => 'deploy.sh: new container healthy → traffic switched, previous image kept for rollback',
  };

  const stages = [...document.querySelectorAll('#stages li')];
  const consoleEl = $('console');
  const replayBtn = $('replay');
  let runId = 0;

  const sleep = (ms) => new Promise((r) => setTimeout(r, reducedMotion ? 0 : ms));

  function log(line) {
    consoleEl.textContent += `${line}\n`;
    consoleEl.scrollTop = consoleEl.scrollHeight;
  }

  async function replay() {
    const id = ++runId;
    replayBtn.disabled = true;
    consoleEl.textContent = '';
    stages.forEach((li) => li.classList.remove('running', 'done'));
    log(`[PIPELINE] Build ${buildInfo.buildNumber} started`);

    for (const li of stages) {
      if (id !== runId) return;
      const name = li.dataset.stage;
      li.classList.add('running');
      log(`[${name.toUpperCase()}] ${stageLog[name]()}`);
      await sleep(700);
      li.classList.replace('running', 'done');
    }

    log(`[PIPELINE] Build ${buildInfo.buildNumber} → SUCCESS ✅`);
    replayBtn.disabled = false;
  }

  replayBtn.addEventListener('click', replay);

  /* ===== Tech cards: tap to reveal on touch devices ===== */
  document.querySelectorAll('.card').forEach((card) => {
    card.addEventListener('click', () => card.classList.toggle('active'));
  });

  /* ===== Diagram parallax tilt ===== */
  const card = $('diagram');
  const img = $('diagram-img');

  if (!reducedMotion) {
    const maxMove = 26;
    const maxTilt = 6;
    let tx = 0, ty = 0, cx = 0, cy = 0, frame = null;

    const animate = () => {
      cx += (tx - cx) * 0.12;
      cy += (ty - cy) * 0.12;
      img.style.transform = `translate3d(${cx}px, ${cy}px, 60px)`;
      card.style.transform = `rotateX(${(-cy / maxMove) * maxTilt}deg) rotateY(${(cx / maxMove) * maxTilt}deg)`;
      // Stop the loop once settled so an idle page uses no CPU.
      frame = Math.abs(tx - cx) + Math.abs(ty - cy) > 0.05 ? requestAnimationFrame(animate) : null;
    };
    const kick = () => { if (!frame) frame = requestAnimationFrame(animate); };

    const move = (clientX, clientY) => {
      const r = card.getBoundingClientRect();
      tx = -((clientX - r.left) / r.width - 0.5) * maxMove;
      ty = -((clientY - r.top) / r.height - 0.5) * maxMove;
      kick();
    };
    const reset = () => { tx = ty = 0; kick(); };

    card.addEventListener('mousemove', (e) => move(e.clientX, e.clientY));
    card.addEventListener('mouseleave', reset);
    card.addEventListener('touchmove', (e) => move(e.touches[0].clientX, e.touches[0].clientY), { passive: true });
    card.addEventListener('touchend', reset);
  }

  /* ===== Boot ===== */
  loadBuildInfo().then(replay);
  checkHealth();
  setInterval(checkHealth, 15000);
})();
