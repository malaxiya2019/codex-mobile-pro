// ============================================================
//  Codex Mobile Pro — Threadripper 会话监控（thread_start 守护进程）
//
//  用途：监控 ~/.codex/config.toml 的 model_provider 变化，用
//  better-sqlite3 同步更新 ~/.codex/sessions.db（尽力而为）。
//  bashrc-additions.sh 的 thread_start() 会 nohup 拉起本脚本，
//  cyo → thread_start → threadripper.js → codex 闭环的一环。
//
//  来源：deploy.sh install_threadripper() heredoc（手动部署路径），
//  此处抽为 asset 供 App 一键部署复制到 rootfs ~/.local/bin/。
//  两处保持一致；改动需同步 deploy.sh。
// ============================================================
const fs = require('fs');
const CONFIG_PATH = `${process.env.HOME}/.codex/config.toml`;
let current = '';
function getCurrentProvider() {
  try {
    const config = fs.readFileSync(CONFIG_PATH, 'utf8');
    const match = config.match(/model_provider\s*=\s*"([^"]+)"/);
    return match ? match[1] : '';
  } catch { return ''; }
}
try {
  const Database = require('better-sqlite3');
  const DB_PATH = `${process.env.HOME}/.codex/sessions.db`;
  fs.watchFile(CONFIG_PATH, { interval: 1000 }, () => {
    const newProvider = getCurrentProvider();
    if (newProvider && newProvider !== current) {
      try {
        const db = new Database(DB_PATH);
        db.prepare('UPDATE sessions SET provider = ?').run(newProvider);
        db.close();
        console.log(`[Threadripper] 已更新会话 provider 为: ${newProvider}`);
        current = newProvider;
      } catch (err) {
        console.error('[Threadripper] 更新失败:', err.message);
      }
    }
  });
} catch(e) {
  console.log('[Threadripper] better-sqlite3 不可用，仅监控模式');
}
console.log('[Threadripper] 已启动，监控 config.toml 变化...');
process.stdin.resume();
