// Runs the page's half of the companion's multiplayer notice (the PAGE string of
// companion/nativeloader/lua/nativeloader/menu/multiplayer_notice.lua, R24) against a mocked Angular menu page.
// Usage: node multiplayer_notice_page.js <multiplayer_notice.lua>. Prints PASS lines; exits 1 on a failure.
'use strict';
const fs = require('fs');
const vm = require('vm');

const lua = fs.readFileSync(process.argv[2], 'utf8');
const start = lua.indexOf('local PAGE = [[');
const end = lua.indexOf(']]', start);
if (start < 0 || end < 0) throw new Error('PAGE not found');
const page = lua.slice(start + 'local PAGE = [['.length, end);

function check(condition, what) { if (!condition) { console.error('FAIL ' + what); process.exit(1); } }

function makePage(options) {
  const listeners = [], runs = [], received = [];
  const location = { current: '/', path() { return this.current.split('?')[0]; }, url(next) {
    if (next === undefined) return this.current;
    const event = { defaultPrevented: false, preventDefault() { this.defaultPrevented = true; } };
    const previous = this.current;
    this.current = next;
    listeners.forEach((fn) => fn(event));
    if (event.defaultPrevented) this.current = previous;
    return this;
  } };
  const root = { $on(name, fn) { if (name === '$locationChangeStart') listeners.push(fn); }, $evalAsync(fn) { fn(); } };
  const window = {
    lua: { Run(format, value) { runs.push(format.replace('%s', JSON.stringify(value))); } },
    angular: { element() { return { injector() { return { get(name) { return name === '$rootScope' ? root : location; } }; } }; } },
    NativeLoaderDiagnostics: options.loader ? { session_token: 'tok-1' } : undefined,
    NativeLoaderReceiveMenuState: options.loader ? (value) => received.push(value) : undefined,
  };
  window.window = window;
  window.document = { querySelector() { return {}; }, body: {} };
  const context = vm.createContext(window);
  const install = (off, session, ignored) => vm.runInContext(page + '(' + JSON.stringify(off) + ', ' +
    JSON.stringify(session) + ', ' + JSON.stringify(ignored) + ')', context);
  return { window, location, runs, received, install, listeners };
}

{
  const p = makePage({ loader: true });
  p.install(false, 'tok-1', '0.17.0');
  check(p.received.length === 1, 'the loader notice is told once');
  const state = p.received[0];
  check(state.multiplayer_dismissed === true && state.session_token === 'tok-1' && state.update_seen === true &&
    state.ignored_version === '0.17.0', 'the loader state keeps its update fields: ' + JSON.stringify(state));
  p.location.url('/servers/internet');
  check(p.location.current === '/', 'the server browser waits for the notice');
  check(p.runs.length === 1 && p.runs[0] === 'NativeLoaderMultiplayerNotice.Open("/servers/internet")', 'asks the menu Lua: ' + p.runs[0]);
  p.window.NativeLoaderMPNotice.go('/servers/internet');
  check(p.location.current === '/servers/internet', 'continue opens the browser once');
  p.location.url('/');
  p.location.url('/servers/internet');
  check(p.location.current === '/' && p.runs.length === 2, 'and asks again next time');
  p.location.url('/home');
  check(p.location.current === '/home', 'other routes are untouched');
  // Installed again on the same page: one listener, and the off switch follows.
  p.install(true, '', '');
  check(p.listeners.length === 1 && p.received.length === 1, 'installed once per page');
  p.location.url('/servers/internet');
  check(p.location.current === '/servers/internet', 'dismissed: the browser opens at once');
  console.log('PASS page');
}
{
  const p = makePage({ loader: false });
  p.install(false, '', '');
  check(p.received.length === 0, 'without the loader notice nothing to tell');
  p.location.url('/servers');
  check(p.runs.length === 1, 'still asks the menu Lua');
  console.log('PASS without-loader-notice');
}
{
  const p = makePage({ loader: true });
  p.install(false, 'other', '');
  check(p.received[0].update_seen === false, 'another session token: the update reminder is not marked seen');
  console.log('PASS update-seen');
}
{
  // No click is swallowed: a failing call to the menu Lua lets the browser open, and an overlong target is not held.
  const p = makePage({ loader: false });
  p.install(false, '', '');
  p.window.lua.Run = () => { throw new Error('lua.Run is unavailable'); };
  p.location.url('/servers/');
  check(p.location.current === '/servers/', 'the browser opens when the menu Lua cannot be asked');
  const q = makePage({ loader: false });
  q.install(false, '', '');
  const long = '/servers/?' + 'a'.repeat(600);
  q.location.url(long);
  check(q.location.current === long && q.runs.length === 0, 'an overlong target goes on without the notice');
  console.log('PASS never-swallowed');
}
