import { spawn } from 'node:child_process';

const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const children = [];
let stopping = false;

const startScript = (scriptName) => {
  const child = spawn(npmCmd, ['run', scriptName], {
    stdio: 'inherit',
    env: process.env,
  });
  children.push(child);
  return child;
};

const stopAll = (signal = 'SIGTERM') => {
  for (const child of children) {
    if (!child.killed) {
      child.kill(signal);
    }
  }
};

const exitWith = (code = 0) => {
  if (stopping) {
    return;
  }
  stopping = true;
  stopAll('SIGTERM');
  process.exit(code);
};

process.on('SIGINT', () => exitWith(130));
process.on('SIGTERM', () => exitWith(143));

const lanServer = startScript('lan:server');
const viteDev = startScript('dev:lan');

lanServer.on('exit', (code, signal) => {
  if (stopping) return;
  if (signal) {
    exitWith(1);
    return;
  }
  exitWith(code ?? 1);
});

viteDev.on('exit', (code, signal) => {
  if (stopping) return;
  if (signal) {
    exitWith(0);
    return;
  }
  exitWith(code ?? 1);
});
